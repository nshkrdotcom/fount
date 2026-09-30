defmodule FountWeb.EditorLive do
  use FountWeb, :live_view

  alias FountWeb.{Authoring, AuthoringStore}

  @autosave_default_ms 60_000
  @structural_history_limit 50

  @impl true
  def mount(%{"id" => run_id}, _session, socket) do
    owner = socket.assigns.current_owner

    with {:ok, access} <- FountWeb.Store.run_access(Fount.Repo, owner, run_id),
         {:ok, workspace} <- Authoring.open_workspace(owner, access["project_id"]) do
      if connected?(socket), do: Process.send_after(self(), :autosave, autosave_ms())

      {:ok,
       socket
       |> assign(:live_connected, connected?(socket))
       |> assign(:run_id, run_id)
       |> assign(:access, access)
       |> assign(:project, workspace.project)
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
         |> put_flash(:error, "Editor unavailable for this owner or Run.")
         |> redirect(to: ~p"/")}
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
          {:ok, draft, candidate, _fidelity} ->
            {:noreply,
             socket
             |> assign(:draft, draft)
             |> assign(:notice, "Candidate #{candidate.id} saved. The approved screenplay is unchanged.")
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
             |> push_navigate(to: ~p"/runs/#{result.run["id"]}/timeline")}

          {:error, reason} ->
            {:noreply, assign(socket, :error, human_error(reason))}
        end
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
         |> assign(:notice, "Draft rebound to the current accepted base. The approved screenplay was not changed.")}

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
        {:noreply, push_navigate(socket, to: ~p"/runs/#{socket.assigns.run_id}/viewer")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("structural_edit", %{"edit" => params}, socket) do
    with true <- valid_preview?(socket.assigns.preview),
         current <- socket.assigns.preview.screenplay,
         {:ok, operation} <- structural_operation(params, current),
         {:ok, draft, next, changes} <-
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
       |> assign(
         :notice,
         "Structure changes saved to the draft. The approved screenplay is unchanged."
       )
       |> assign(:error, nil)
       |> push_event("authoring:replace_source", %{
         source: raw,
         expected_client_seq: socket.assigns.client_seq,
         reset_history: false
       })}
    else
      false ->
        {:noreply, assign(socket, :error, "Structural commands require valid Fountain source.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
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
          next = preview_screenplay(preview, restored)

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
           |> assign(:notice, "Structural undo applied to draft only (#{next.revision.id}).")}
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

  defp preview_screenplay(%{valid?: true, screenplay: screenplay}, _fallback), do: screenplay
  defp preview_screenplay(_, fallback), do: fallback

  defp refreshed_draft(socket) do
    case AuthoringStore.get(Fount.Repo, socket.assigns.current_owner, socket.assigns.draft["id"]) do
      {:ok, draft} -> draft
      _ -> socket.assigns.draft
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

  defp human_error(reason), do: "Authoring operation failed: #{inspect(reason)}"

  defp diagnostic_text(diagnostic) do
    severity = Map.get(diagnostic, :severity, :info)
    code = Map.get(diagnostic, :code, :diagnostic)
    message = Map.get(diagnostic, :message, "")
    "#{severity}: #{code} #{message}"
  end

  @impl true
  def render(assigns) do
    preview_screenplay =
      if valid_preview?(assigns.preview),
        do: assigns.preview.screenplay,
        else: assigns.last_valid.screenplay

    assigns = assign(assigns, :preview_screenplay, preview_screenplay)

    ~H"""
    <main
      id={"editor-#{@run_id}"}
      class={"authoring-shell mode-#{@mode}"}
      phx-hook="AuthoringEditor"
      data-dirty={to_string(@dirty)}
      data-draft-status={@draft["status"]}
    >
      <nav class="context-nav" aria-label="Run">
        <a href={~p"/"}>Projects</a>
        <a href={~p"/runs/#{@run_id}/timeline"}>Timeline</a>
        <a href={~p"/runs/#{@run_id}/viewer"}>Viewer</a>
        <a href={~p"/runs/#{@run_id}/edit"} aria-current="page">Editor</a>
        <a href={~p"/runs/#{@run_id}/review"}>Review</a>
        <a href={~p"/runs/#{@run_id}/analysis"}>Intelligence</a>
      </nav>

      <header class="workspace-header">
        <div>
          <p class="eyebrow">Screenplay editor</p>
          <h1>{@access["title"]}</h1>
          <p>
            Accepted base <code>{@draft["base_revision_id"]}</code>
            · draft <code>{@draft["id"]}</code>
            v{@draft["version"]}
          </p>
        </div>
        <div class="authoring-status" role="status" aria-live="polite">
          <strong>{@save_state}</strong>
          <span>{if @dirty, do: "Unsaved local changes", else: "Draft synchronized"}</span>
        </div>
      </header>

      <p class={"analysis-draft-marker #{if @dirty, do: "is-stale", else: "is-saved"}"} role="status">
        <strong>Analysis evidence:</strong>
        <%= if @dirty do %>
          This unsaved draft has not been analyzed. Previous analysis applies to its original screenplay version.
        <% else %>
          Saved analysis applies to the version it examined. Open Intelligence to review it.
        <% end %>
      </p>

      <FountWeb.CoreComponents.alert :if={@error} kind="warning" title="Authoring notice">
        {@error}
      </FountWeb.CoreComponents.alert>
      <FountWeb.CoreComponents.alert :if={@notice} kind="info" title="Authoring status">
        {@notice}
      </FountWeb.CoreComponents.alert>

      <section :if={@conflict} id="draft-conflict" class="authoring-conflict" role="alert">
        <h2>Draft conflict</h2>
        <p>Another tab saved version {@conflict["version"]}. No text was overwritten.</p>
        <button type="button" phx-click="reload_server">Use newer server draft</button>
        <button type="button" data-authoring-fork>Keep my text as a new recovery draft</button>
      </section>

      <section class="authoring-toolbar" aria-label="Authoring controls">
        <div role="group" aria-label="Workspace mode">
          <button
            :for={mode <- ["editor", "split", "preview"]}
            type="button"
            phx-click="set_mode"
            phx-value-mode={mode}
            aria-pressed={to_string(@mode == mode)}
          >{String.capitalize(mode)}</button>
        </div>
        <div role="group" aria-label="Text history">
          <button type="button" phx-click="text_undo" disabled={@draft["status"] != "active"}>Undo text</button>
          <button type="button" phx-click="text_redo" disabled={@draft["status"] != "active"}>Redo text</button>
        </div>
        <div role="group" aria-label="Structural history">
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
        <button
          id="authoring-save"
          type="button"
          data-authoring-save
          disabled={@draft["status"] != "active"}
        >Save draft</button>
        <button
          id="candidate-save"
          type="button"
          data-authoring-candidate
          disabled={not valid_preview?(@preview) or @draft["status"] != "active"}
        >Save candidate</button>
        <button
          id="ai-assist"
          type="button"
          phx-click="start_ai_assist"
          disabled={
            not @live_connected or @dirty or @draft["status"] != "active" or
              not is_binary(@draft["saved_candidate_id"])
          }
        >AI assist via Run</button>
        <button
          id="candidate-accept"
          type="button"
          phx-click="accept_candidate"
          disabled={
            not @live_connected or @dirty or @draft["status"] != "active" or
              not is_binary(@draft["saved_candidate_id"])
          }
        >Accept exact candidate</button>
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
            Fountain syntax assistance: scene headings such as <code>INT. OFFICE - DAY</code>, character cues, dialogue, transitions, notes, and sections remain plain editable text.
          </p>

          <div
            id="authoring-diagnostics"
            class="authoring-diagnostics"
            aria-live="polite"
            aria-atomic="false"
          >
            <h2>Source diagnostics</h2>
            <p :if={@diagnostics == []}>No blocking source diagnostics.</p>
            <ul>
              <li :for={diagnostic <- Enum.take(@diagnostics, 12)}>{diagnostic_text(diagnostic)}</li>
            </ul>
            <p :if={not valid_preview?(@preview)}>
              Preview is showing the last valid draft while the invalid raw source remains editable and recoverable.
            </p>
            <p :if={valid_preview?(@preview)} class="scope-note">
              Fidelity: exact raw round-trip {to_string(@preview.fidelity["exact_source_round_trip"])} · preserved element IDs {length(
                @preview.fidelity["preserved_element_ids"]
              )} · source SHA-256 <code>{@preview.fidelity["source_sha256"]}</code>.
            </p>
          </div>
        </section>

        <section class="authoring-preview-pane" aria-label="Screenplay preview" data-authoring-preview>
          <p class="scope-note">
            Preview is debounced and best-effort. Stable source identities anchor editor-to-preview navigation.
          </p>
          <FountWeb.Components.ScreenplayRenderer.screenplay screenplay={@preview_screenplay} />
        </section>
      </div>

      <section class="authoring-lower-grid">
        <FountWeb.CoreComponents.card>
          <h2>Validated structural commands</h2>
          <p>
            These commands use the existing screenplay edit algebra and stable IDs. Generic element move/split/merge is intentionally not offered.
          </p>
          <form phx-submit="structural_edit" class="authoring-command-form">
            <label>
              Operation
              <select name="edit[kind]">
                <option value="replace_text">Replace element text</option>
                <option value="set_character_cue">Change character cue</option>
                <option value="insert_scene">Insert scene after</option>
                <option value="insert_element_after">Insert action element after</option>
                <option value="delete_element">Delete element</option>
                <option value="delete_scene">Delete scene</option>
                <option value="move_scene">Move scene after</option>
              </select>
            </label>
            <label>Target stable ID <input name="edit[target]" required /></label>
            <label>Value / destination ID <input name="edit[value]" /></label>
            <button type="submit" disabled={@draft["status"] != "active"}>Apply to draft</button>
          </form>
          <p :if={@affected_scope != []} id="affected-scope">
            Affected stable IDs: {Enum.join(@affected_scope, ", ")}
          </p>
        </FountWeb.CoreComponents.card>

        <FountWeb.CoreComponents.card>
          <h2>Recovery history</h2>
          <p>
            Recent drafts are kept in history. Restoring one creates a new draft and leaves the approved screenplay unchanged.
          </p>
          <ol class="draft-history">
            <li :for={item <- @history}>
              <span>v{item["draft_version"]} · {item["reason"]}</span>
              <button type="button" phx-click="restore_history" phx-value-history_id={item["id"]}>Restore as new draft</button>
            </li>
          </ol>
          <button type="button" phx-click="rebase_draft" disabled={@draft["status"] != "active"}>Rebase draft to current accepted head</button>
          <button type="button" phx-click="discard_draft" disabled={@draft["status"] != "active"}>Discard working draft</button>
        </FountWeb.CoreComponents.card>
      </section>

      <p class="scope-note">
        Saving a proposed revision leaves the approved screenplay unchanged. To replace it, use the approval action above.
      </p>
    </main>
    """
  end
end
