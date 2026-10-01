defmodule FountWeb.EditorLive do
  use FountWeb, :live_view

  alias FountWeb.{Authoring, AuthoringStore, ScreenplayIndex}

  @autosave_default_ms 60_000
  @structural_history_limit 50

  @impl true
  def mount(%{"key" => project_key}, _session, socket) do
    owner = socket.assigns.current_owner

    with {:ok, project} <- FountWeb.Store.project_by_key(Fount.Repo, owner, project_key),
         {:ok, workspace} <- Authoring.open_workspace(owner, project["id"]) do
      if connected?(socket), do: Process.send_after(self(), :autosave, autosave_ms())
      _ = FountWeb.ProjectContext.remember(owner, project_key, "writing")

      {:ok,
       socket
       |> assign(:live_connected, connected?(socket))
       |> assign(:project, workspace.project)
       |> assign(:preferences, FountWeb.Store.owner_preferences(Fount.Repo, owner))
       |> assign(:base, workspace.base)
       |> assign(:draft, workspace.draft)
       |> assign(:raw_source, workspace.draft["raw_source"])
       |> assign(:preview, workspace.preview)
       |> assign(:last_valid, workspace.preview)
       |> assign(:diagnostics, workspace.preview.diagnostics)
       |> assign(:dirty, false)
       |> assign(:client_seq, 0)
       |> assign(:cursor, %{line: 1, column: 1})
       |> assign(:mode, "split")
       |> assign(:save_state, "saved")
       |> assign(:conflict, nil)
       |> assign(:notice, nil)
       |> assign(:error, nil)
       |> assign(:structural_undo, [])
       |> assign(:structural_redo, [])
       |> assign(:history, history(owner, workspace.draft["id"]))
       |> assign(:affected_scope, [])}
    else
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Writing view is not available for that screenplay.")
         |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_info(:autosave, socket) do
    Process.send_after(self(), :autosave, autosave_ms())

    if socket.assigns.dirty and is_nil(socket.assigns.conflict) do
      {:noreply,
       persist_source(socket, socket.assigns.raw_source, socket.assigns.client_seq, "autosave")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("preview_source", params, socket) do
    raw = Map.get(params, "source", "")
    seq = integer(Map.get(params, "client_seq"), socket.assigns.client_seq)

    if seq < socket.assigns.client_seq do
      {:noreply, socket}
    else
      cursor = %{
        line: integer(Map.get(params, "line"), 1),
        column: integer(Map.get(params, "column"), 1)
      }

      case Authoring.preview(socket.assigns.base, raw,
             prior_source: Fount.Screenplay.to_fountain(socket.assigns.last_valid.screenplay),
             identity_anchors: socket.assigns.last_valid.identity_anchors
           ) do
        {:ok, %{valid?: true} = preview} ->
          socket =
            socket
            |> assign(:raw_source, raw)
            |> assign(:client_seq, seq)
            |> assign(:cursor, cursor)
            |> assign(:preview, preview)
            |> assign(:last_valid, preview)
            |> assign(:diagnostics, preview.diagnostics)
            |> assign(:dirty, raw != socket.assigns.draft["raw_source"])
            |> assign(:save_state, preview_save_state(raw, socket.assigns.draft))
            |> assign(:error, nil)
            |> sync_preview(cursor.line, preview.anchors)

          {:noreply, socket}

        {:ok, %{valid?: false} = invalid} ->
          {:noreply,
           socket
           |> assign(:raw_source, raw)
           |> assign(:client_seq, seq)
           |> assign(:cursor, cursor)
           |> assign(:preview, invalid)
           |> assign(:diagnostics, invalid.diagnostics)
           |> assign(:dirty, raw != socket.assigns.draft["raw_source"])
           |> assign(:save_state, "invalid-unsaved")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:raw_source, raw)
           |> assign(:client_seq, seq)
           |> assign(:dirty, true)
           |> assign(:save_state, "unsaved")
           |> assign(:error, human_error(reason))}
      end
    end
  end

  def handle_event("save_source", params, socket) do
    raw = Map.get(params, "source", socket.assigns.raw_source)
    seq = integer(Map.get(params, "client_seq"), socket.assigns.client_seq)

    if seq < socket.assigns.client_seq do
      {:noreply, socket}
    else
      {:noreply, persist_source(socket, raw, seq, "manual")}
    end
  end

  def handle_event("save_candidate_requested", params, socket) do
    raw = Map.get(params, "source", socket.assigns.raw_source)
    seq = integer(Map.get(params, "client_seq"), socket.assigns.client_seq)

    socket =
      if raw != socket.assigns.draft["raw_source"],
        do: persist_source(socket, raw, seq, "candidate_save"),
        else: socket

    cond do
      socket.assigns.conflict ->
        {:noreply, socket}

      socket.assigns.dirty ->
        {:noreply, assign(socket, :error, "Save the current draft before creating a candidate.")}

      not valid_preview?(socket.assigns.preview) ->
        {:noreply,
         assign(
           socket,
           :error,
           "Fix Fountain errors before saving a candidate. Raw invalid draft remains saved."
         )}

      true ->
        case Authoring.save_candidate(
               socket.assigns.current_owner,
               socket.assigns.draft["id"],
               socket.assigns.draft["version"]
             ) do
          {:ok, draft, _candidate, _fidelity} ->
            {:noreply,
             socket
             |> assign(:draft, draft)
             |> assign(
               :notice,
               "Proposed change saved. The current screenplay is unchanged."
             )
             |> assign(:error, nil)
             |> assign(:save_state, "candidate-saved")}

          {:error, reason} ->
            {:noreply, assign(socket, :error, human_error(reason))}
        end
    end
  end

  def handle_event("accept_candidate", params, socket) do
    candidate_id = socket.assigns.draft["saved_candidate_id"]

    cond do
      unsaved_source?(socket, params) ->
        {:noreply,
         assign(socket, :error, "Unsaved text cannot be accepted. Save a candidate first.")}

      not is_binary(candidate_id) ->
        {:noreply, assign(socket, :error, "No current draft-bound candidate to accept.")}

      true ->
        case Authoring.accept_candidate(
               socket.assigns.current_owner,
               socket.assigns.draft["id"],
               candidate_id,
               Fount.ID.v4()
             ) do
          {:ok, _accepted} ->
            updated = refreshed_draft(socket)

            {:noreply,
             socket
             |> assign(:draft, updated)
             |> assign(
               :notice,
               "Revision approved and saved as the current screenplay. Open a new draft to continue editing."
             )
             |> assign(:error, nil)
             |> assign(:save_state, "accepted")}

          {:error, reason} ->
            {:noreply, assign(socket, :error, human_error(reason))}
        end
    end
  end

  def handle_event("start_ai_assist", params, socket) do
    cond do
      unsaved_source?(socket, params) ->
        {:noreply,
         assign(socket, :error, "Save the draft and candidate before starting AI assistance.")}

      not is_binary(socket.assigns.draft["saved_candidate_id"]) ->
        {:noreply,
         assign(socket, :error, "A saved manual candidate is required before AI assistance.")}

      true ->
        command = Fount.ID.v5(socket.assigns.draft["id"], "ai:#{socket.assigns.draft["version"]}")

        case Authoring.start_ai_assist(
               socket.assigns.current_owner,
               socket.assigns.draft["id"],
               command
             ) do
          {:ok, result} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "AI assistance started. The approved screenplay is unchanged."
             )
             |> push_navigate(
               to: "/p/#{socket.assigns.project["key"]}/activity/#{result.access["display_key"]}"
             )}

          {:error, reason} ->
            {:noreply, assign(socket, :error, human_error(reason))}
        end
    end
  end

  def handle_event("dismiss_hint", %{"slug" => slug}, socket) do
    dismissed =
      socket.assigns.preferences
      |> Map.get("dismissed_hints", [])
      |> List.wrap()
      |> MapSet.new()
      |> MapSet.put(slug)
      |> MapSet.to_list()

    case FountWeb.Store.put_owner_preferences(Fount.Repo, socket.assigns.current_owner, %{
           "dismissed_hints" => dismissed
         }) do
      {:ok, prefs} -> {:noreply, assign(socket, :preferences, prefs)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_mode", %{"mode" => mode}, socket)
      when mode in ["editor", "preview", "split"],
      do: {:noreply, assign(socket, :mode, mode)}

  def handle_event("set_mode", _, socket), do: {:noreply, socket}

  def handle_event("reload_server", _params, socket) do
    case AuthoringStore.get(Fount.Repo, socket.assigns.current_owner, socket.assigns.draft["id"]) do
      {:ok, draft} ->
        {:noreply,
         socket
         |> load_draft(draft)
         |> assign(:conflict, nil)
         |> assign(:notice, "Loaded the newer server draft.")
         |> push_event("authoring:replace_source", %{
           source: draft["raw_source"],
           expected_client_seq: socket.assigns.client_seq,
           reset_history: true
         })}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("fork_conflict", params, socket) do
    raw = Map.get(params, "source", socket.assigns.raw_source)

    case AuthoringStore.fork(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.draft["id"],
           raw
         ) do
      {:ok, draft} ->
        {:noreply,
         socket
         |> load_draft(draft)
         |> assign(:conflict, nil)
         |> assign(:notice, "Kept this tab's text in a separate recovery draft.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("rebase_draft", _params, socket) do
    case Authoring.rebase(
           socket.assigns.current_owner,
           socket.assigns.draft["id"],
           socket.assigns.draft["version"]
         ) do
      {:ok, draft} ->
        {:ok, base} =
          Fount.Persistence.load_revision(
            Fount.Repo,
            draft["screenplay_id"],
            draft["base_revision_id"]
          )

        {:ok, preview} =
          Authoring.preview(base, draft["raw_source"],
            prior_source: draft["last_valid_source"],
            identity_anchors: draft["identity_anchors"] || []
          )

        {:noreply,
         socket
         |> assign(:draft, draft)
         |> assign(:base, base)
         |> assign(:preview, preview)
         |> assign(:last_valid, if(preview.valid?, do: preview, else: socket.assigns.last_valid))
         |> assign(:dirty, false)
         |> assign(:conflict, nil)
         |> assign(
           :notice,
           "Draft rebound to the current accepted base. The approved screenplay was not changed."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("restore_history", %{"history_id" => history_id}, socket) do
    case AuthoringStore.restore(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.draft["id"],
           history_id
         ) do
      {:ok, draft} ->
        socket = load_draft(socket, draft)

        {:noreply,
         socket
         |> assign(
           :notice,
           "History restored into a new draft. The approved screenplay is unchanged."
         )
         |> push_event("authoring:replace_source", %{
           source: draft["raw_source"],
           expected_client_seq: socket.assigns.client_seq,
           reset_history: true
         })}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("discard_draft", _params, socket) do
    case AuthoringStore.discard(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.draft["id"],
           socket.assigns.draft["version"]
         ) do
      {:ok, _draft} ->
        {:noreply, push_navigate(socket, to: "/p/#{socket.assigns.project["key"]}")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("structural_edit", %{"edit" => params}, socket) do
    with true <- valid_preview?(socket.assigns.preview),
         current <- socket.assigns.preview.screenplay,
         {:ok, operation} <- structural_operation(params, current) do
      apply_structural_operation(socket, current, operation)
    else
      false ->
        {:noreply, assign(socket, :error, "Structural commands require valid Fountain source.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("scene_move", %{"scene_id" => scene_id, "direction" => direction}, socket)
      when direction in ["up", "down"] do
    with true <- valid_preview?(socket.assigns.preview),
         current <- socket.assigns.preview.screenplay,
         {:ok, operation} <- scene_move_operation(current, scene_id, direction) do
      apply_structural_operation(socket, current, operation)
    else
      false -> {:noreply, assign(socket, :error, "Scene moves require valid Fountain source.")}
      {:error, :scene_at_boundary} -> {:noreply, socket}
      {:error, reason} -> {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("toggle_scene_omission", %{"scene_id" => scene_id, "omit" => omit}, socket) do
    with true <- valid_preview?(socket.assigns.preview),
         current <- socket.assigns.preview.screenplay,
         scene when not is_nil(scene) <- Fount.Query.scene(current, scene_id) do
      apply_structural_operation(socket, current, Fount.Edit.omit_scene(scene_id, omit == "true"))
    else
      false -> {:noreply, assign(socket, :error, "Scene omission requires valid Fountain source.")}
      nil -> {:noreply, assign(socket, :error, "That scene is no longer in this working draft.")}
    end
  end

  defp apply_structural_operation(socket, current, operation) do
    with {:ok, draft, next, changes} <-
           Authoring.structural_edit(
             socket.assigns.current_owner,
             socket.assigns.draft["id"],
             socket.assigns.draft["version"],
             current,
             operation
           ),
         next_raw <- Fount.Screenplay.to_fountain(next),
         {:ok, next_preview} <-
           Authoring.preview(socket.assigns.base, next_raw,
             prior_source: next_raw,
             identity_anchors: Fount.Identity.anchors(next.ir)
           ) do
      undo = [current | socket.assigns.structural_undo] |> Enum.take(@structural_history_limit)
      raw = draft["raw_source"]

      {:noreply,
       socket
       |> assign(:draft, draft)
       |> assign(:raw_source, raw)
       |> assign(:preview, next_preview)
       |> assign(:last_valid, next_preview)
       |> assign(:diagnostics, next_preview.diagnostics)
       |> assign(:dirty, false)
       |> assign(:save_state, "saved")
       |> assign(:structural_undo, undo)
       |> assign(:structural_redo, [])
       |> assign(:affected_scope, affected_ids(changes))
       |> assign(:history, history(socket.assigns.current_owner, draft["id"]))
       |> assign(:notice, "Structure changes saved to the draft. The approved screenplay is unchanged.")
       |> assign(:error, nil)
       |> push_event("authoring:replace_source", %{
         source: raw,
         expected_client_seq: socket.assigns.client_seq,
         reset_history: false
       })}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("structural_undo", _params, socket), do: structural_restore(socket, :undo)
  def handle_event("structural_redo", _params, socket), do: structural_restore(socket, :redo)

  def handle_event("text_undo", _params, socket),
    do: {:noreply, push_event(socket, "authoring:undo_text", %{})}

  def handle_event("text_redo", _params, socket),
    do: {:noreply, push_event(socket, "authoring:redo_text", %{})}

  def handle_event("replace_source_rejected", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :error,
       "A newer local edit prevented a server replacement. Your current text was left untouched."
     )
     |> assign(:save_state, "unsaved")}
  end

  defp persist_source(socket, raw, seq, reason) do
    case Authoring.save_draft(
           socket.assigns.current_owner,
           socket.assigns.draft["id"],
           socket.assigns.draft["version"],
           raw,
           reason
         ) do
      {:ok, draft, preview} ->
        last_valid = if preview.valid?, do: preview, else: socket.assigns.last_valid

        socket
        |> assign(:draft, draft)
        |> assign(:raw_source, raw)
        |> assign(:client_seq, max(seq, socket.assigns.client_seq))
        |> assign(:preview, preview)
        |> assign(:last_valid, last_valid)
        |> assign(:diagnostics, preview.diagnostics)
        |> assign(:dirty, false)
        |> assign(:save_state, if(preview.valid?, do: "saved", else: "invalid-saved"))
        |> assign(:conflict, nil)
        |> assign(:history, history(socket.assigns.current_owner, draft["id"]))
        |> assign(:error, nil)
        |> push_event("authoring:mark_saved", %{client_seq: seq, version: draft["version"]})

      {:error, {:stale_draft, conflict}} ->
        socket
        |> assign(:raw_source, raw)
        |> assign(:client_seq, max(seq, socket.assigns.client_seq))
        |> assign(:dirty, true)
        |> assign(:save_state, "conflict")
        |> assign(:conflict, conflict)
        |> assign(
          :error,
          "This draft changed in another tab. Choose a recovery action; nothing was overwritten."
        )

      {:error, reason} ->
        socket |> assign(:save_state, "save-failed") |> assign(:error, human_error(reason))
    end
  end

  defp structural_restore(socket, :undo) do
    case socket.assigns.structural_undo do
      [prior | rest] ->
        current = current_screenplay(socket)

        with {:ok, restored} <- Fount.Screenplay.undo(current, prior),
             raw <- Fount.Screenplay.to_fountain(restored),
             {:ok, draft, preview} <-
               Authoring.save_draft(
                 socket.assigns.current_owner,
                 socket.assigns.draft["id"],
                 socket.assigns.draft["version"],
                 raw,
                 "structural_undo",
                 prior_source: raw,
                 identity_anchors: Fount.Identity.anchors(restored.ir)
               ) do
          {:noreply,
           socket
           |> assign(:draft, draft)
           |> assign(:raw_source, raw)
           |> assign(:preview, preview)
           |> assign(
             :last_valid,
             if(preview.valid?, do: preview, else: socket.assigns.last_valid)
           )
           |> assign(:dirty, false)
           |> assign(:structural_undo, rest)
           |> assign(
             :structural_redo,
             [current | socket.assigns.structural_redo] |> Enum.take(@structural_history_limit)
           )
           |> push_event("authoring:replace_source", %{
             source: raw,
             expected_client_seq: socket.assigns.client_seq,
             reset_history: false
           })
           |> assign(:notice, "Structural undo applied to the working draft only.")}
        else
          {:error, reason} -> {:noreply, assign(socket, :error, human_error(reason))}
        end

      [] ->
        {:noreply, socket}
    end
  end

  defp structural_restore(socket, :redo) do
    case socket.assigns.structural_redo do
      [subsequent | rest] ->
        current = current_screenplay(socket)

        with {:ok, restored} <- Fount.Screenplay.redo(current, subsequent),
             raw <- Fount.Screenplay.to_fountain(restored),
             {:ok, draft, preview} <-
               Authoring.save_draft(
                 socket.assigns.current_owner,
                 socket.assigns.draft["id"],
                 socket.assigns.draft["version"],
                 raw,
                 "structural_redo",
                 prior_source: raw,
                 identity_anchors: Fount.Identity.anchors(restored.ir)
               ) do
          {:noreply,
           socket
           |> assign(:draft, draft)
           |> assign(:raw_source, raw)
           |> assign(:preview, preview)
           |> assign(
             :last_valid,
             if(preview.valid?, do: preview, else: socket.assigns.last_valid)
           )
           |> assign(:dirty, false)
           |> assign(:structural_redo, rest)
           |> assign(
             :structural_undo,
             [current | socket.assigns.structural_undo] |> Enum.take(@structural_history_limit)
           )
           |> push_event("authoring:replace_source", %{
             source: raw,
             expected_client_seq: socket.assigns.client_seq,
             reset_history: false
           })}
        else
          {:error, reason} -> {:noreply, assign(socket, :error, human_error(reason))}
        end

      [] ->
        {:noreply, socket}
    end
  end

  defp unsaved_source?(socket, params) do
    socket.assigns.dirty or
      Map.get(params, "source", socket.assigns.raw_source) != socket.assigns.draft["raw_source"]
  end

  defp preview_save_state(raw, draft),
    do: if(raw == draft["raw_source"], do: "saved", else: "unsaved")

  defp refreshed_draft(socket) do
    case AuthoringStore.get(Fount.Repo, socket.assigns.current_owner, socket.assigns.draft["id"]) do
      {:ok, draft} -> draft
      _ -> socket.assigns.draft
    end
  end

  defp scene_move_operation(screenplay, scene_id, direction) do
    scenes = List.wrap(screenplay.ir.scenes)
    index = Enum.find_index(scenes, &(&1.id == scene_id))

    cond do
      is_nil(index) -> {:error, {:unknown_scene, scene_id}}
      direction == "down" and index >= length(scenes) - 1 -> {:error, :scene_at_boundary}
      direction == "down" -> {:ok, Fount.Edit.move_scene(scene_id, Enum.at(scenes, index + 1).id)}
      direction == "up" and index == 0 -> {:error, :scene_at_boundary}
      direction == "up" and index == 1 -> {:ok, Fount.Edit.move_scene(Enum.at(scenes, 0).id, scene_id)}
      direction == "up" -> {:ok, Fount.Edit.move_scene(scene_id, Enum.at(scenes, index - 2).id)}
    end
  end

  defp structural_operation(
         %{"kind" => "replace_text", "target" => target, "value" => value},
         _model
       )
       when is_binary(target) and is_binary(value),
       do: {:ok, Fount.Edit.replace_text(target, value)}

  defp structural_operation(
         %{"kind" => "set_character_cue", "target" => target, "value" => value},
         _model
       )
       when is_binary(target) and is_binary(value),
       do: {:ok, Fount.Edit.set_character_cue(target, value)}

  defp structural_operation(
         %{"kind" => "insert_scene", "target" => after_id, "value" => heading},
         _model
       )
       when is_binary(after_id) and is_binary(heading),
       do: {:ok, Fount.Edit.insert_scene_after(after_id, heading)}

  defp structural_operation(%{"kind" => "delete_scene", "target" => target}, _model)
       when is_binary(target),
       do: {:ok, Fount.Edit.delete_scene(target)}

  defp structural_operation(
         %{"kind" => "insert_element_after", "target" => anchor_id, "value" => text},
         model
       )
       when is_binary(anchor_id) and is_binary(text) do
    case Fount.Query.scene_for(model, anchor_id) do
      %{id: scene_id} ->
        {:ok,
         %{
           "kind" => "insert_elements",
           "target" => %{"kind" => "scene", "id" => scene_id},
           "value" => %{
             "position" => "after",
             "anchor_id" => anchor_id,
             "elements" => [
               %{
                 "local_id" => "new:a-#{Fount.ID.v4()}",
                 "type" => "action",
                 "text" => text,
                 "attrs" => %{}
               }
             ]
           }
         }}

      _ ->
        {:error, {:unknown_element, anchor_id}}
    end
  end

  defp structural_operation(%{"kind" => "delete_element", "target" => target}, _model)
       when is_binary(target),
       do: {:ok, %{"kind" => "delete_elements", "value" => %{"ids" => [target]}}}

  defp structural_operation(
         %{"kind" => "move_scene", "target" => target, "value" => after_id},
         _model
       )
       when is_binary(target) and is_binary(after_id),
       do: {:ok, Fount.Edit.move_scene(target, after_id)}

  defp structural_operation(_, _model), do: {:error, :unsupported_structural_operation}

  defp load_draft(socket, draft) do
    {:ok, base} =
      Fount.Persistence.load_revision(
        Fount.Repo,
        draft["screenplay_id"],
        draft["base_revision_id"]
      )

    {:ok, preview} =
      Authoring.preview(base, draft["raw_source"],
        prior_source: draft["last_valid_source"],
        identity_anchors: draft["identity_anchors"] || []
      )

    socket
    |> assign(:draft, draft)
    |> assign(:base, base)
    |> assign(:raw_source, draft["raw_source"])
    |> assign(:preview, preview)
    |> assign(:last_valid, if(preview.valid?, do: preview, else: socket.assigns.last_valid))
    |> assign(:diagnostics, preview.diagnostics)
    |> assign(:dirty, false)
    |> assign(:save_state, if(preview.valid?, do: "saved", else: "invalid-saved"))
    |> assign(:history, history(socket.assigns.current_owner, draft["id"]))
    |> assign(:structural_undo, [])
    |> assign(:structural_redo, [])
    |> assign(:affected_scope, [])
  end

  defp affected_ids(changes) do
    operation_targets =
      changes
      |> Map.get(:operations, [])
      |> Enum.map(& &1["target"])
      |> Enum.filter(&is_map/1)

    [:changed_targets, :inserted_targets, :removed_targets]
    |> Enum.flat_map(&Map.get(changes, &1, []))
    |> Kernel.++(operation_targets)
    |> Enum.map(fn
      %{id: id} -> id
      %{"id" => id} -> id
      other -> inspect(other)
    end)
    |> Enum.uniq()
    |> Enum.take(40)
  end

  defp sync_preview(socket, line, anchors) do
    anchor =
      anchors
      |> Enum.filter(&(&1["line_start"] <= line))
      |> Enum.max_by(& &1["line_start"], fn -> nil end)

    if anchor,
      do: push_event(socket, "authoring:sync_preview", %{node_id: anchor["id"]}),
      else: socket
  end

  defp current_screenplay(socket) do
    if valid_preview?(socket.assigns.preview),
      do: socket.assigns.preview.screenplay,
      else: socket.assigns.last_valid.screenplay
  end

  defp history(owner, draft_id) do
    case AuthoringStore.history(Fount.Repo, owner, draft_id, 12) do
      rows when is_list(rows) -> rows
      _ -> []
    end
  end

  defp valid_preview?(%{valid?: true, screenplay: %Fount.Screenplay{}}), do: true
  defp valid_preview?(_), do: false

  defp autosave_ms do
    config = Application.get_env(:fount_web, :authoring, [])
    Keyword.get(config, :autosave_ms, @autosave_default_ms) |> max(5_000)
  end

  defp integer(value, _default) when is_integer(value), do: value

  defp integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> default
    end
  end

  defp integer(_, default), do: default

  defp human_error({:stale_revision, _}),
    do: "The accepted screenplay changed. Rebase this draft before saving a candidate."

  defp human_error({:stale_base, _}),
    do: "The accepted screenplay changed. Rebase this draft before continuing."

  defp human_error({:invalid_source, _, _}),
    do: "Fountain source is invalid; the raw draft is preserved but cannot become a candidate."

  defp human_error({:source_too_large, _}),
    do: "Draft exceeds the configured authoring size limit."

  defp human_error(:candidate_contains_no_change),
    do: "This draft has no change relative to its accepted base."

  defp human_error(:saved_candidate_required),
    do: "Save a candidate before starting AI assistance."

  defp human_error(:saved_candidate_stale),
    do: "The saved candidate no longer matches this draft version."

  defp human_error(:draft_limit_reached),
    do: "Draft history is full. Discard an older draft first."

  defp human_error(_reason),
    do: "That writing action could not be completed. Your working text has been kept."

  defp diagnostic_text(diagnostic) do
    severity = Map.get(diagnostic, :severity, :info)
    code = Map.get(diagnostic, :code, :diagnostic)
    message = Map.get(diagnostic, :message, "")
    "#{severity}: #{code} #{message}"
  end

  defp element_label(element) do
    text = element.text |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()
    preview = if String.length(text) > 72, do: String.slice(text, 0, 69) <> "...", else: text
    type = element.type |> to_string() |> String.replace("_", " ")
    if preview == "", do: type, else: "#{type} · #{preview}"
  end

  defp dismissed?(prefs, slug), do: slug in List.wrap(Map.get(prefs, "dismissed_hints", []))

  defp save_state_label("saved"), do: "Saved working draft"
  defp save_state_label("candidate-saved"), do: "Proposed change saved"
  defp save_state_label("accepted"), do: "Current screenplay updated"
  defp save_state_label("invalid-saved"), do: "Saved working draft · Fountain needs attention"
  defp save_state_label("invalid-unsaved"), do: "Unsaved text · Fountain needs attention"
  defp save_state_label("unsaved"), do: "Unsaved local changes"
  defp save_state_label("save-failed"), do: "Save failed · local text kept"
  defp save_state_label(other), do: other |> to_string() |> String.replace("-", " ")

  @impl true
  def render(assigns) do
    preview_screenplay =
      if valid_preview?(assigns.preview),
        do: assigns.preview.screenplay,
        else: assigns.last_valid.screenplay

    assigns =
      assigns
      |> assign(:preview_screenplay, preview_screenplay)
      |> assign(:writing_index, ScreenplayIndex.build(preview_screenplay))
      |> assign(:writing_elements, List.wrap(preview_screenplay.ir.elements))
      |> assign(:writing_hint_dismissed, dismissed?(assigns.preferences, "writing"))

    ~H"""
    <main
      id="project-editor"
      class={"project-workspace authoring-shell mode-#{@mode}"}
      phx-hook="AuthoringEditor"
      data-dirty={to_string(@dirty)}
      data-draft-status={@draft["status"]}
      data-project-key={@project["key"]}
    >
      <FountWeb.CoreComponents.project_header
        project={@project}
        section="script"
        view="writing"
        source_label="Working draft"
        example={@project["project_kind"] == "example"}
      />

      <section class="script-context writing-context" aria-label="Writing status">
        <div>
          <h1>{@project["title"]}</h1>
          <p>
            <strong>Working draft</strong>
            · separate from the current screenplay until you explicitly make a saved proposal current.
          </p>
        </div>
        <div class="authoring-status" role="status" aria-live="polite">
          <strong>{save_state_label(@save_state)}</strong>
          <span>Draft version {@draft["version"]}</span>
        </div>
      </section>

      <FountWeb.CoreComponents.contextual_help
        slug="writing"
        title="Working text is recoverable, not automatically current"
        dismissed={@writing_hint_dismissed}
        project_key={@project["key"]}
      >
        <p>
          Save freely. Saving a proposed change still does not replace the current screenplay; that requires the separate Make current action.
        </p>
      </FountWeb.CoreComponents.contextual_help>

      <FountWeb.CoreComponents.alert :if={@error} kind="warning" title="Writing notice">
        {@error}
      </FountWeb.CoreComponents.alert>
      <FountWeb.CoreComponents.alert :if={@notice} kind="info" title="Writing status">
        {@notice}
      </FountWeb.CoreComponents.alert>

      <section :if={@conflict} id="draft-conflict" class="authoring-conflict" role="alert">
        <h2>This draft changed in another tab</h2>
        <p>Your local text has not been overwritten. Choose which recovery path to keep.</p>
        <button type="button" phx-click="reload_server">Use the newer saved draft</button>
        <button type="button" data-authoring-fork>Keep my text as a separate recovery draft</button>
      </section>

      <section class="authoring-toolbar" aria-label="Writing controls">
        <div role="group" aria-label="Writing layout">
          <button
            :for={
              {mode, label} <- [
                {"editor", "Source"},
                {"split", "Source + pages"},
                {"preview", "Pages"}
              ]
            }
            type="button"
            phx-click="set_mode"
            phx-value-mode={mode}
            aria-pressed={to_string(@mode == mode)}
          >{label}</button>
        </div>
        <button
          id="authoring-focus"
          type="button"
          data-authoring-focus
          aria-pressed="false"
          title="Hide surrounding controls. Press Escape to leave Focus."
        >Focus</button>
        <button
          id="authoring-typewriter"
          type="button"
          data-authoring-typewriter
          aria-pressed="false"
          title="Optional cursor-following scroll. Off by default and disabled when reduced motion is requested."
        >Typewriter scroll off</button>
        <span class="focus-save-state" role="status">{save_state_label(@save_state)}</span>
        <button
          id="authoring-save"
          type="button"
          data-authoring-save
          disabled={@draft["status"] != "active"}
        >Save working draft</button>
        <button
          id="candidate-save"
          type="button"
          data-authoring-candidate
          disabled={not valid_preview?(@preview) or @draft["status"] != "active"}
        >Save proposed change</button>
        <button
          id="candidate-accept"
          type="button"
          phx-click="accept_candidate"
          disabled={
            not @live_connected or @dirty or @draft["status"] != "active" or
              not is_binary(@draft["saved_candidate_id"])
          }
        >Make proposed change current</button>
      </section>

      <div class="authoring-grid">
        <section class="authoring-editor-pane" aria-label="Fountain editor">
          <div class="authoring-editor-meta">
            <span>Fountain source</span>
            <output id="editor-position" data-editor-position>Line {@cursor.line}, column {@cursor.column}</output>
          </div>
          <div id="source-editor-wrap" phx-update="ignore">
            <label for="source-editor" class="sr-only">Fountain screenplay source</label>
            <textarea
              id="source-editor"
              data-authoring-source
              spellcheck="false"
              autocapitalize="off"
              autocomplete="off"
              aria-describedby="fountain-syntax-help authoring-diagnostics"
              readonly={@draft["status"] != "active"}
            >{@raw_source}</textarea>
          </div>
          <p id="fountain-syntax-help" class="scope-note">
            Plain Fountain text. Scene headings such as <code>INT. OFFICE - DAY</code>, character cues and dialogue preview on the right.
          </p>

          <div id="authoring-diagnostics" class="authoring-diagnostics" aria-live="polite">
            <h2>Source check</h2>
            <p :if={@diagnostics == []}>No blocking Fountain diagnostics.</p>
            <ul>
              <li :for={diagnostic <- Enum.take(@diagnostics, 12)}>{diagnostic_text(diagnostic)}</li>
            </ul>
            <p :if={not valid_preview?(@preview)}>
              Your raw text is kept in this editor. Save working draft to store it. Pages continue to show the last valid draft until the Fountain source can be reconciled.
            </p>
          </div>
        </section>

        <section
          class="authoring-preview-pane"
          aria-label="Responsive screenplay preview"
          data-authoring-preview
        >
          <div class="reader-paper__label">
            <span>Responsive screenplay preview</span><a href="/help#reading">About page references</a>
          </div>
          <FountWeb.Components.ScreenplayRenderer.screenplay screenplay={@preview_screenplay} />
        </section>
      </div>

      <div class="authoring-secondary">
        <FountWeb.CoreComponents.disclosure
          id="text-history"
          title="Undo and recovery"
          summary="Local text, structure and saved history"
        >
          <div class="button-row" role="group" aria-label="Text history">
            <button type="button" phx-click="text_undo" disabled={@draft["status"] != "active"}>Undo text</button>
            <button type="button" phx-click="text_redo" disabled={@draft["status"] != "active"}>Redo text</button>
            <button
              type="button"
              phx-click="structural_undo"
              disabled={@draft["status"] != "active" or @structural_undo == []}
            >Undo structure</button>
            <button
              type="button"
              phx-click="structural_redo"
              disabled={@draft["status"] != "active" or @structural_redo == []}
            >Redo structure</button>
          </div>
          <ol class="draft-history">
            <li :for={item <- @history}>
              <span>Version {item["draft_version"]} · {item["reason"]}</span>
              <button type="button" phx-click="restore_history" phx-value-history_id={item["id"]}>Restore as new draft</button>
            </li>
          </ol>
          <div class="button-row">
            <button type="button" phx-click="rebase_draft" disabled={@draft["status"] != "active"}>Rebase onto current screenplay</button>
            <button type="button" phx-click="discard_draft" disabled={@draft["status"] != "active"}>Discard working draft</button>
          </div>
        </FountWeb.CoreComponents.disclosure>

        <FountWeb.CoreComponents.disclosure
          id="scene-cards"
          title="Scene cards and exact edits"
          summary="Named structural controls; no stable IDs to copy"
        >
          <p class="scope-note">
            Scene moves and omission are saved to this working draft only. Use the buttons or focus a scene card and press Alt+Arrow Up/Down. Generic element move/split/merge is intentionally not offered. This unsaved draft has not been analyzed; analysis remains tied to saved task sources.
          </p>
          <ol class="scene-card-list" data-scene-cards>
            <li
              :for={{scene, index} <- Enum.with_index(@writing_index.scenes)}
              class="scene-card"
              tabindex="0"
              data-scene-card
              data-scene-id={scene.id}
            >
              <div>
                <strong>Scene {scene.ordinal} · {scene.heading || "Untitled scene"}</strong>
                <span :if={scene.omitted?} class="status-chip">Omitted</span>
              </div>
              <div class="button-row" role="group" aria-label={"Move Scene #{scene.ordinal}"}>
                <button type="button" phx-click="scene_move" phx-value-scene_id={scene.id} phx-value-direction="up" disabled={@draft["status"] != "active" or index == 0}>Up</button>
                <button type="button" phx-click="scene_move" phx-value-scene_id={scene.id} phx-value-direction="down" disabled={@draft["status"] != "active" or index == length(@writing_index.scenes) - 1}>Down</button>
                <button type="button" phx-click="toggle_scene_omission" phx-value-scene_id={scene.id} phx-value-omit={to_string(!scene.omitted?)} disabled={@draft["status"] != "active"}>{if scene.omitted?, do: "Include", else: "Omit"}</button>
              </div>
            </li>
          </ol>

          <div class="exact-edit-grid">
            <form phx-submit="structural_edit" class="authoring-command-form">
              <input type="hidden" name="edit[kind]" value="replace_text" />
              <label>Element <select name="edit[target]" required><option :for={element <- @writing_elements} value={element.id}>{element_label(element)}</option></select></label>
              <label>Replacement text <textarea name="edit[value]" maxlength="4000" required></textarea></label>
              <button type="submit" disabled={@draft["status"] != "active"}>Replace text</button>
            </form>
            <form phx-submit="structural_edit" class="authoring-command-form">
              <input type="hidden" name="edit[kind]" value="set_character_cue" />
              <label>Character cue <select name="edit[target]" required><option :for={element <- Enum.filter(@writing_elements, &(&1.type == :character))} value={element.id}>{element_label(element)}</option></select></label>
              <label>New cue <input name="edit[value]" maxlength="160" required /></label>
              <button type="submit" disabled={@draft["status"] != "active"}>Change cue</button>
            </form>
            <form phx-submit="structural_edit" class="authoring-command-form">
              <input type="hidden" name="edit[kind]" value="insert_scene" />
              <label>After <select name="edit[target]" required><option :for={scene <- @writing_index.scenes} value={scene.id}>Scene {scene.ordinal} · {scene.heading || "Untitled"}</option></select></label>
              <label>Scene heading <input name="edit[value]" maxlength="240" placeholder="INT. OFFICE - DAY" required /></label>
              <button type="submit" disabled={@draft["status"] != "active"}>Insert scene</button>
            </form>
            <form phx-submit="structural_edit" class="authoring-command-form">
              <input type="hidden" name="edit[kind]" value="insert_element_after" />
              <label>After element <select name="edit[target]" required><option :for={element <- @writing_elements} value={element.id}>{element_label(element)}</option></select></label>
              <label>Action text <textarea name="edit[value]" maxlength="4000" required></textarea></label>
              <button type="submit" disabled={@draft["status"] != "active"}>Insert action</button>
            </form>
            <form phx-submit="structural_edit" class="authoring-command-form compact-command">
              <input type="hidden" name="edit[kind]" value="delete_element" />
              <label>Element <select name="edit[target]" required><option :for={element <- @writing_elements} value={element.id}>{element_label(element)}</option></select></label>
              <button type="submit" disabled={@draft["status"] != "active"}>Delete element</button>
            </form>
            <form phx-submit="structural_edit" class="authoring-command-form compact-command">
              <input type="hidden" name="edit[kind]" value="delete_scene" />
              <label>Scene <select name="edit[target]" required><option :for={scene <- @writing_index.scenes} value={scene.id}>Scene {scene.ordinal} · {scene.heading || "Untitled"}</option></select></label>
              <button type="submit" disabled={@draft["status"] != "active"}>Delete scene</button>
            </form>
          </div>
          <p :if={@affected_scope != []}>Affected source elements are retained internally for exact recovery and review.</p>
          <p><a href={"/p/#{@project["key"]}/work"}>Work on a selected passage with the creative workshop</a></p>
        </FountWeb.CoreComponents.disclosure>

        <details class="technical-details">
          <summary>Technical details</summary>
          <dl>
            <div>
              <dt>Project identity</dt><dd><code>{@project["id"]}</code></dd>
            </div>
            <div>
              <dt>Draft identity</dt><dd><code>{@draft["id"]}</code></dd>
            </div>
            <div>
              <dt>Base revision</dt><dd><code>{@draft["base_revision_id"]}</code></dd>
            </div>
            <div :if={is_binary(@draft["saved_candidate_id"])}>
              <dt>Saved proposal</dt><dd><code>{@draft["saved_candidate_id"]}</code></dd>
            </div>
            <div :if={valid_preview?(@preview)}>
              <dt>Source SHA-256</dt><dd><code>{@preview.fidelity["source_sha256"]}</code></dd>
            </div>
          </dl>
        </details>
      </div>
    </main>
    """
  end
end
