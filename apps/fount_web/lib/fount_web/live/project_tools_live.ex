defmodule FountWeb.ProjectToolsLive do
  use FountWeb, :live_view

  alias FountWeb.{
    AuthoringStore,
    CreativeWorkspace,
    ProductionStore,
    ProductionTools,
    ProjectContext,
    ReadingArtifacts,
    Store,
    WorkflowManagement
  }

  @impl true
  def mount(%{"key" => key} = params, _session, socket) do
    owner = socket.assigns.current_owner

    case ProjectContext.load(owner, key) do
      {:ok, context} ->
        {:ok,
         socket
         |> assign_project(context)
         |> assign(:error, nil)
         |> assign(:notice, nil)
         |> assign(:creative_preview, nil)
         |> assign(:creative_review, nil)
         |> assign(:character_dialogue, nil)
         |> assign(:note_target_results, [])
         |> assign(:note_review_conflict, nil)
         |> assign(:cast_rename_preview, nil)
         |> assign(:selected_read, nil)
         |> assign(:table_read_conflict, nil)
         |> assign(:reaction_conflict, nil)
         |> assign(:submission_check, nil)
         |> assign_note_prefill(context.current, params)}

      _ ->
        {:ok,
         socket |> put_flash(:error, "That screenplay is not available.") |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_event("start_task", %{"task" => params}, socket) do
    journey = Map.get(params, "journey", "opening")
    command_id = Fount.ID.v4()

    case FountWeb.Launch.create_from_project(
           socket.assigns.current_owner,
           socket.assigns.project["id"],
           %{"journey" => journey, "command_id" => command_id}
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task created from the current screenplay.")
         |> push_navigate(
           to:
             "/p/#{socket.assigns.project["key"]}/activity/#{result.access["display_key"]}/setup"
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :error, task_error(reason))}
    end
  end

  def handle_event("preview_creative_task", %{"task" => params}, socket) do
    model = socket.assigns.context.current
    owner = socket.assigns.current_owner
    action = Map.get(params, "action", "rewrite")
    question = params |> Map.get("question", "") |> String.trim()
    multi? = truthy?(params["multi_launch"])

    with true <- question != "" or {:error, :question_required},
         {:ok, selection} <- CreativeWorkspace.selection_from_values(model, params["scope"]),
         {:ok, protected} <- CreativeWorkspace.protected_text(model, params["protected"]),
         {:ok, attrs} <-
           CreativeWorkspace.action_attrs(Fount.Repo, model, action, params, selection, protected),
         {:ok, actor_context} <- FountWeb.Actors.owner_context(owner, model.id),
         {:ok, policy} <- default_candidate_policy(owner, actor_context),
         {:ok, preview} <-
           WorkflowManagement.launch_preview(
             model,
             action,
             question,
             selection,
             policy,
             multi?,
             attrs
           ) do
      {:noreply,
       socket
       |> assign(:creative_preview, preview)
       |> assign(:creative_review, %{
         action: action_label(action),
         protections: protection_labels(model, protected),
         question: question
       })
       |> assign(:error, nil)
       |> assign(
         :notice,
         "Brief validated against the current screenplay. Review it before starting."
       )}
    else
      false -> {:noreply, assign(socket, :error, creative_error(:question_required))}
      {:error, reason} -> {:noreply, assign(socket, :error, creative_error(reason))}
    end
  end

  def handle_event(
        "confirm_creative_task",
        _params,
        %{assigns: %{creative_preview: nil}} = socket
      ),
      do: {:noreply, assign(socket, :error, "Review a valid brief before starting work.")}

  def handle_event("confirm_creative_task", _params, socket) do
    preview = socket.assigns.creative_preview

    results =
      WorkflowManagement.execute_launch_preview(
        socket.assigns.current_owner,
        socket.assigns.project["id"],
        preview
      )

    summary = WorkflowManagement.launch_summary(results)

    case summary["created"] do
      [first | _] ->
        note_link_result = link_notes_for_launch(socket, preview, summary["created"])

        case Store.run_access(
               Fount.Repo,
               socket.assigns.current_owner,
               first["run_id"]
             ) do
          {:ok, access} ->
            {:noreply,
             socket
             |> put_flash(
               if(note_link_result == :ok, do: :info, else: :error),
               creative_task_flash(note_link_result)
             )
             |> push_navigate(
               to: "/p/#{socket.assigns.project["key"]}/activity/#{access["display_key"]}/setup"
             )}

          _ ->
            {:noreply,
             socket
             |> assign(:creative_preview, nil)
             |> assign(:creative_review, nil)
             |> assign(:notice, "Creative task saved. Open Activity to continue.")
             |> assign(:runs, runs(socket.assigns.current_owner, socket.assigns.project["id"]))}
        end

      [] ->
        {:noreply,
         socket
         |> assign(
           :error,
           "The validated task could not be created. No screenplay material was changed."
         )
         |> assign(:notice, nil)}
    end
  end

  def handle_event("work_on_note", %{"note_id" => note_id}, socket) do
    model = socket.assigns.context.current

    case Enum.find(socket.assigns.notes, &(&1.id == note_id)) do
      nil ->
        {:noreply,
         assign(socket, :error, "That note is not available on the current screenplay.")}

      note ->
        owner = socket.assigns.current_owner
        question = note.title || note.text || "Work on this note"
        selection = note_selection(note)
        attrs = %{"note_ids" => [note.id], "external_notes" => []}

        with {:ok, actor_context} <- FountWeb.Actors.owner_context(owner, model.id),
             {:ok, policy} <- default_candidate_policy(owner, actor_context),
             {:ok, preview} <-
               WorkflowManagement.launch_preview(
                 model,
                 "notes",
                 question,
                 selection,
                 policy,
                 false,
                 attrs
               ) do
          {:noreply,
           socket
           |> assign(:creative_preview, preview)
           |> assign(:creative_review, %{
             action: "Work from notes",
             protections: [],
             question: question
           })
           |> assign(
             :notice,
             "Note-bound task validated. Review the exact source before starting."
           )
           |> assign(:error, nil)}
        else
          {:error, reason} -> {:noreply, assign(socket, :error, creative_error(reason))}
        end
    end
  end

  def handle_event("try_line", %{"line" => params}, socket) do
    model = socket.assigns.context.current
    element_id = params["element_id"]

    question =
      blank_to_default(params["direction"], "Try another line with the same dramatic intent.")

    with %{type: type} <- Fount.Query.node(model, element_id),
         true <- type in [:dialogue, :parenthetical] or {:error, :dialogue_line_required},
         block when not is_nil(block) <- Fount.Query.block_for(model, element_id),
         {:ok, selection} <-
           CreativeWorkspace.selection_from_values(model, ["element:#{element_id}"]),
         protected_values <-
           [block.cue_id | block.body_ids]
           |> Enum.reject(&(&1 == element_id))
           |> Enum.map(&"element:#{&1}"),
         {:ok, protected} <- CreativeWorkspace.protected_text(model, protected_values),
         attrs <- %{"alternatives" => 3, "protected_text" => protected},
         {:ok, actor_context} <-
           FountWeb.Actors.owner_context(socket.assigns.current_owner, model.id),
         {:ok, policy} <- default_candidate_policy(socket.assigns.current_owner, actor_context),
         {:ok, preview} <-
           WorkflowManagement.launch_preview(
             model,
             "alternatives",
             question,
             selection,
             policy,
             false,
             attrs
           ) do
      {:noreply,
       socket
       |> assign(:creative_preview, preview)
       |> assign(:creative_review, %{
         action: "Try another line · 3 alternatives",
         protections: protection_labels(model, protected),
         question: question
       })
       |> assign(
         :notice,
         "Line alternatives validated. The surrounding cue and lines are protected."
       )
       |> assign(:error, nil)}
    else
      nil -> {:noreply, assign(socket, :error, "That dialogue line is no longer in this source.")}
      false -> {:noreply, assign(socket, :error, "Choose a dialogue or parenthetical line.")}
      {:error, reason} -> {:noreply, assign(socket, :error, creative_error(reason))}
    end
  end

  def handle_event("read_character", %{"character_id" => character_id}, socket) do
    case CreativeWorkspace.character_dialogue(socket.assigns.context.current, character_id) do
      {:ok, dialogue} ->
        {:noreply,
         socket
         |> assign(:character_dialogue, dialogue)
         |> assign(:error, nil)
         |> assign(:notice, "Showing literal source dialogue only; no model call was made.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, creative_error(reason))}
    end
  end

  def handle_event("save_note", %{"note" => params}, socket) do
    model = socket.assigns.context.current

    case ProductionTools.save_note_candidate(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.project["id"],
           model.revision.id,
           params
         ) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:notice, "Note saved as a proposal. The current screenplay is unchanged.")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, note_error(reason))}
    end
  end

  def handle_event("accept_note_candidate", %{"candidate_id" => candidate_id}, socket) do
    case ProductionTools.accept_tool_candidate(
           Fount.Repo,
           socket.assigns.current_owner,
           candidate_id,
           Fount.ID.v4()
         ) do
      {:ok, _accepted} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(
           :notice,
           "Note accepted into the current screenplay. It can now start related work."
         )
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, note_error(reason))}
    end
  end

  def handle_event("filter_notes", %{"notes" => params}, socket) do
    filters = Map.take(params, ["query", "status", "category"])

    {:noreply,
     socket
     |> assign(:note_filters, filters)
     |> assign(:notes, ProductionTools.notes(socket.assigns.context.current, filters))}
  end

  def handle_event("search_note_targets", %{"target_search" => params}, socket) do
    query = Map.get(params, "query", "")

    case ProductionTools.target_search(socket.assigns.context.current, query, 80) do
      {:ok, results} ->
        {:noreply,
         socket
         |> assign(:note_target_results, results)
         |> assign(:notice, "Found #{length(results)} exact source passages in the current draft.")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Source passage search failed: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_note", %{"note_id" => note_id}, socket) do
    model = socket.assigns.context.current

    case ProductionTools.delete_note_candidate(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.project["id"],
           model.revision.id,
           note_id
         ) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:notice, "Note deletion saved as a proposal. The current screenplay is unchanged.")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, note_error(reason))}
    end
  end

  def handle_event("save_note_review", %{"review" => params}, socket) do
    model = socket.assigns.context.current
    note_id = params["note_id"]

    case ProductionTools.save_note_review(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.project,
           note_id,
           model.revision.id,
           model.revision.id,
           params
         ) do
      {:ok, _row} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:note_review_conflict, nil)
         |> assign(:notice, "Reviewer response saved for this exact screenplay revision.")
         |> assign(:error, nil)}

      {:error, {:stale_note_review, row}} ->
        {:noreply,
         socket
         |> assign(:note_review_conflict, %{note_id: note_id, attempted: params, saved: row})
         |> assign(
           :error,
           "This reviewer response changed in another tab. Your typed response is preserved below so you can compare it with the saved version before retrying."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Reviewer response was not saved: #{inspect(reason)}")}
    end
  end

  def handle_event("reload_note_review", _params, socket) do
    {:noreply,
     socket
     |> refresh_project_data()
     |> assign(:note_review_conflict, nil)
     |> assign(:notice, "Reloaded the saved reviewer response.")
     |> assign(:error, nil)}
  end

  def handle_event("build_notes_memo", %{"memo" => params}, socket) do
    selected = List.wrap(params["note_ids"])
    notes = Enum.filter(socket.assigns.notes, &(&1.id in selected))
    responses = review_map(socket.assigns.note_reviews, socket.assigns.context.current.revision.id)

    attrs =
      params
      |> Map.put("responses", responses)
      |> Map.put("include_responses", truthy?(params["include_responses"]))

    case ReadingArtifacts.build_notes_memo(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.project,
           socket.assigns.context.current,
           notes,
           attrs
         ) do
      {:ok, _artifact} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:notice, "Notes memo built from the selected verbatim notes and exact current source.")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:error, "Notes memo was not built: #{human_artifact_error(reason)}")}
    end
  end

  def handle_event("preview_cast_rename", %{"rename" => params}, socket) do
    case ProductionTools.cast_rename_preview(
           socket.assigns.context.current,
           params["character_id"],
           params["new_name"]
         ) do
      {:ok, plan} ->
        {:noreply,
         socket
         |> assign(:cast_rename_preview, %{
           character_id: params["character_id"],
           new_name: String.trim(params["new_name"] || ""),
           plan: plan
         })
         |> assign(:notice, nil)
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Name-change preview unavailable: #{inspect(reason)}")}
    end
  end

  def handle_event("save_cast_rename", _params, %{assigns: %{cast_rename_preview: nil}} = socket),
    do: {:noreply, assign(socket, :error, "Preview a name change before saving proposed work.")}

  def handle_event("save_cast_rename", _params, socket) do
    preview = socket.assigns.cast_rename_preview
    model = socket.assigns.context.current

    case ProductionTools.save_cast_rename_candidate(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.project["id"],
           model.revision.id,
           preview.character_id,
           preview.new_name
         ) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:cast_rename_preview, nil)
         |> assign(:notice, "Name change saved as a proposal. The current screenplay is unchanged.")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Name-change proposal was not saved: #{inspect(reason)}")}
    end
  end

  def handle_event("accept_tool_candidate", %{"candidate_id" => candidate_id}, socket) do
    case ProductionTools.accept_tool_candidate(
           Fount.Repo,
           socket.assigns.current_owner,
           candidate_id,
           Fount.ID.v4()
         ) do
      {:ok, _accepted} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:notice, "Reviewed proposal made current through typed Core acceptance.")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Proposal was not accepted: #{inspect(reason)}")}
    end
  end

  def handle_event("create_table_read", %{"read" => params}, socket) do
    model = socket.assigns.context.current
    values = List.wrap(params["scope"])

    with {:ok, selection} <- CreativeWorkspace.selection_from_values(model, values),
         {:ok, read} <-
           ProductionTools.create_project_table_read(
             Fount.Repo,
             socket.assigns.current_owner,
             socket.assigns.project,
             model,
             selection,
             params
           ) do
      {:noreply,
       socket
       |> refresh_project_data()
       |> assign(:selected_read, read)
       |> assign(:notice, "Saved human table-read material from the exact current draft.")
       |> assign(:error, nil)}
    else
      {:error, reason} ->
        {:noreply, assign(socket, :error, "Table read was not created: #{creative_error(reason)}")}
    end
  end

  def handle_event("select_table_read", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.table_reads, &(&1["id"] == id)) do
      nil -> {:noreply, assign(socket, :error, "That saved table read is no longer available.")}
      read -> {:noreply, socket |> assign(:selected_read, read) |> assign(:error, nil)}
    end
  end

  def handle_event("table_read_state", attrs, socket) do
    with %{} = read <- socket.assigns.selected_read,
         {:ok, saved} <-
           ProductionTools.update_table_read(
             Fount.Repo,
             socket.assigns.current_owner,
             read["id"],
             read["version"],
             %{
               bookmark_index: parse_nonnegative(attrs["bookmark_index"]),
               elapsed_ms: parse_nonnegative(attrs["elapsed_ms"]),
               scroll_mode: normalize_scroll_mode(attrs["scroll_mode"])
             }
           ) do
      {:reply, %{status: "saved", version: saved["version"]},
       socket |> assign(:selected_read, saved) |> assign(:table_read_conflict, nil)}
    else
      nil ->
        {:reply, %{status: "error"}, assign(socket, :error, "Choose a saved table read first.")}

      {:error, {:stale_table_read, row}} ->
        attempted = %{
          "bookmark_index" => parse_nonnegative(attrs["bookmark_index"]),
          "elapsed_ms" => parse_nonnegative(attrs["elapsed_ms"]),
          "scroll_mode" => normalize_scroll_mode(attrs["scroll_mode"])
        }

        preserved = Map.merge(row, attempted)

        {:reply, %{status: "stale", version: row["version"]},
         socket
         |> assign(:selected_read, preserved)
         |> assign(:table_read_conflict, %{attempted: attempted, saved: row})
         |> assign(
           :error,
           "Table-read state changed in another tab. Your bookmark, timing and navigation state are preserved for comparison and retry."
         )}

      {:error, reason} ->
        {:reply, %{status: "error"}, assign(socket, :error, "Table-read state not saved: #{inspect(reason)}")}
    end
  end

  def handle_event("record_reaction", %{"reaction" => params}, socket) do
    with %{} = read <- socket.assigns.selected_read,
         {:ok, saved} <-
           ProductionTools.record_table_reaction(
             Fount.Repo,
             socket.assigns.current_owner,
             read["id"],
             read["version"],
             Map.put(params, "observer", "human")
           ) do
      {:noreply,
       socket
       |> refresh_project_data()
       |> assign(:selected_read, saved)
       |> assign(:reaction_conflict, nil)
       |> assign(:notice, "Human reaction saved with the exact table-read packet and source revision.")
       |> assign(:error, nil)}
    else
      nil -> {:noreply, assign(socket, :error, "Choose a saved table read first.")}

      {:error, {:stale_table_read, row}} ->
        {:noreply,
         socket
         |> assign(:selected_read, row)
         |> assign(:reaction_conflict, %{attempted: params, saved: row})
         |> assign(
           :error,
           "This table read changed in another tab. Your typed reaction is preserved below; review the saved version and retry if it still applies."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Reaction was not saved: #{inspect(reason)}")}
    end
  end

  def handle_event("reload_table_read", _params, socket) do
    case socket.assigns.selected_read do
      %{} = read ->
        case ProductionStore.table_read(Fount.Repo, socket.assigns.current_owner, read["id"]) do
          {:ok, saved} ->
            {:noreply,
             socket
             |> assign(:selected_read, saved)
             |> assign(:table_read_conflict, nil)
             |> assign(:reaction_conflict, nil)
             |> assign(:notice, "Reloaded the saved table-read state.")
             |> assign(:error, nil)}

          _ ->
            {:noreply, assign(socket, :error, "That saved table read is no longer available.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save_feedback", %{"feedback" => params}, socket) do
    run_id = params["run_id"]

    with {:ok, workspace} <-
           ProductionTools.workspace(Fount.Repo, socket.assigns.current_owner, run_id),
         true <- workspace.project["id"] == socket.assigns.project["id"] or {:error, :project_mismatch},
         attrs <- feedback_attrs(workspace, params),
         {:ok, _row} <-
           ProductionTools.save_usefulness(
             Fount.Repo,
             socket.assigns.current_owner,
             workspace,
             attrs
           ) do
      {:noreply,
       socket
       |> refresh_project_data()
       |> assign(:notice, "Human feedback saved. No aggregate quality score or learning claim was calculated.")
       |> assign(:error, nil)}
    else
      false -> {:noreply, assign(socket, :error, "That task does not belong to this project.")}
      {:error, reason} -> {:noreply, assign(socket, :error, "Feedback was not saved: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_feedback", %{"id" => id}, socket) do
    case ProductionTools.delete_usefulness(Fount.Repo, socket.assigns.current_owner, id) do
      :ok ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:notice, "Feedback record deleted.")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Feedback record was not deleted: #{inspect(reason)}")}
    end
  end

  def handle_event("check_submission", %{"submission" => %{"target" => target}}, socket) do
    current = socket.assigns.context.current

    with %{} = artifact <- current_pdf_artifact(socket.assigns.project_artifacts, current.revision.id),
         {:ok, profile} <- submission_profile(target) do
      report = %{
        source_revision: artifact["revision_id"],
        pages: get_in(artifact, ["metadata", "pages"]),
        blank_pages: get_in(artifact, ["metadata", "blank_pages"]),
        page_size: submission_page_size(get_in(artifact, ["metadata", "page_size"])),
        courier_prime?: get_in(artifact, ["metadata", "courier_prime"])
      }

      check = FountWorkshop.Submission.check(current, report, profile)

      {:noreply,
       socket
       |> assign(:submission_check, check)
       |> assign(:notice, "Mechanical submission checks refreshed from the exact current PDF artifact.")
       |> assign(:error, nil)}
    else
      nil ->
        {:noreply, assign(socket, :error, "Build a ready PDF from the current draft before running submission checks.")}

      {:error, :unknown_profile} ->
        {:noreply, assign(socket, :error, "That submission-check profile is not available.")}
    end
  end

  def handle_event("build_project_export", %{"export" => %{"format" => format}}, socket) do
    case ReadingArtifacts.build_source(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.project,
           socket.assigns.context.current,
           format
         ) do
      {:ok, _artifact} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:notice, "#{String.upcase(format)} built from the exact current draft.")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> refresh_project_data()
         |> assign(:error, "Export was not built: #{human_artifact_error(reason)}")}
    end
  end

  def handle_event("save_project", %{"project" => params}, socket) do
    title = params |> Map.get("title", "") |> String.trim()

    with :ok <- validate_project_title(title),
         {:ok, logline} <- optional_text(Map.get(params, "logline"), 1_000, "Logline"),
         {:ok, synopsis} <- optional_text(Map.get(params, "synopsis"), 4_000, "Synopsis") do
      attrs = %{"title" => title, "logline" => logline, "synopsis" => synopsis}

      case Store.update_project(
             Fount.Repo,
             socket.assigns.current_owner,
             socket.assigns.project["id"],
             attrs
           ) do
        {:ok, project} ->
          {:noreply,
           socket
           |> assign(:project, project)
           |> assign(:notice, "Project details saved.")
           |> assign(:error, nil)}

        _ ->
          {:noreply, assign(socket, :error, "Project details could not be saved.")}
      end
    else
      {:error, message} -> {:noreply, assign(socket, :error, message)}
    end
  end

  defp assign_project(socket, context) do
    owner = socket.assigns.current_owner
    project_id = context.project["id"]
    project_runs = runs(owner, project_id)
    note_filters = socket.assigns[:note_filters] || %{"query" => "", "status" => "", "category" => ""}

    _ =
      ProductionTools.reconcile_note_work_links(Fount.Repo, owner, project_id, context.current.id)

    links = note_work_links(owner, project_id)
    _ = ProductionTools.sync_note_work_results(Fount.Repo, owner, context.current.id, links)
    links = note_work_links(owner, project_id)

    socket
    |> assign(:project, context.project)
    |> assign(:context, context)
    |> assign(:runs, project_runs)
    |> assign(:reviewable_runs, Enum.filter(project_runs, &reviewable_run?/1))
    |> assign(:drafts, drafts(owner, project_id))
    |> assign(:scope_options, CreativeWorkspace.scope_options(context.current))
    |> assign(:protection_options, CreativeWorkspace.protection_options(context.current))
    |> assign(:target_options, ProductionTools.target_options(context.current))
    |> assign(:characters, ProductionTools.character_profiles(context.current))
    |> assign(:locations, ProductionTools.location_profiles(context.current))
    |> assign(:estimates, FountWeb.ScreenplayIndex.estimates(context.current))
    |> assign(:note_filters, note_filters)
    |> assign(:note_categories, ProductionTools.note_categories())
    |> assign(:notes, ProductionTools.notes(context.current, note_filters))
    |> assign(:note_candidates, note_candidates(owner, project_id))
    |> assign(:cast_candidates, cast_candidates(owner, project_id))
    |> assign(:note_links, links)
    |> assign(:note_reviews, note_reviews(owner, project_id))
    |> assign(:table_reads, table_reads(owner, project_id))
    |> assign(:usefulness_rows, usefulness_rows(owner, project_id))
    |> assign(:usefulness_report, usefulness_report(owner, project_id))
    |> assign(:project_artifacts, project_artifacts(owner, project_id))
    |> assign(
      :historical_sources,
      CreativeWorkspace.historical_sources(Fount.Repo, context.current)
    )
    |> assign(:workflow_actions, WorkflowManagement.action_catalog())
    |> assign(
      :primary_workflow_actions,
      primary_workflow_actions(WorkflowManagement.action_catalog())
    )
    |> assign(
      :workflow_action_groups,
      workflow_action_groups(WorkflowManagement.action_catalog())
    )
  end

  defp assign_note_prefill(socket, model, params) do
    target = Map.get(params, "target")
    source_revision = Map.get(params, "source_revision")
    valid_targets = model |> ProductionTools.target_options() |> Enum.map(& &1.value) |> MapSet.new()

    cond do
      is_nil(target) ->
        socket |> assign(:note_prefill_target, nil) |> assign(:note_prefill_notice, nil)

      source_revision not in [nil, "", model.revision.id] ->
        socket
        |> assign(:note_prefill_target, nil)
        |> assign(
          :note_prefill_notice,
          "That selected passage came from an earlier draft. Choose its current named passage before saving a note; Fount will not silently retarget it."
        )

      MapSet.member?(valid_targets, target) ->
        socket
        |> assign(:note_prefill_target, target)
        |> assign(:note_prefill_notice, "Selected passage carried into this note from the exact current draft.")

      true ->
        socket
        |> assign(:note_prefill_target, nil)
        |> assign(:note_prefill_notice, "The selected passage is no longer available in this draft. Choose a named source passage.")
    end
  end

  defp primary_workflow_actions(actions) do
    Enum.filter(actions, &(&1["id"] in ~w(rewrite alternatives investigate)))
  end

  defp workflow_action_groups(actions) do
    [
      {"Write", ~w(develop rewrite character notes)},
      {"Explore", ~w(alternatives investigate)},
      {"Revise", ~w(pass sequence propagate)},
      {"Restore", ~w(recover)}
    ]
    |> Enum.map(fn {label, ids} ->
      %{label: label, actions: Enum.filter(actions, &(&1["id"] in ids))}
    end)
  end

  defp refresh_project_data(socket) do
    case ProjectContext.load(socket.assigns.current_owner, socket.assigns.project["key"]) do
      {:ok, context} -> assign_project(socket, context)
      _ -> socket
    end
  end

  defp default_candidate_policy(owner, context) do
    case WorkflowManagement.built_in_presets(owner, context) do
      [%{"policy" => policy} | _] -> {:ok, policy}
      _ -> {:error, :policy_unavailable}
    end
  end

  defp link_notes_for_launch(socket, preview, created) do
    note_ids = get_in(preview, ["request_attrs", "note_ids"]) || []

    results =
      for row <- created, note_id <- note_ids do
        ProductionTools.link_note_work(
          Fount.Repo,
          socket.assigns.current_owner,
          socket.assigns.project["id"],
          socket.assigns.context.current.id,
          preview["base_revision_id"],
          note_id,
          row["run_id"]
        )
      end

    if Enum.all?(results, &match?({:ok, _}, &1)), do: :ok, else: {:error, :note_link_failed}
  end

  defp creative_task_flash(:ok),
    do:
      "Creative task saved. The current screenplay is unchanged until a reviewed proposal is explicitly accepted."

  defp creative_task_flash({:error, :note_link_failed}),
    do:
      "Creative task saved, but its related-note link could not be confirmed. Reopening Notes will retry the persisted relation from the task's saved note identities."

  defp note_selection(%{target: %{"kind" => kind} = target})
       when kind in ~w(scene element character),
       do: %{"targets" => [target]}

  defp note_selection(_), do: %{"whole_screenplay" => true}

  defp note_work_links(owner, project_id) do
    case ProductionTools.note_work_links(Fount.Repo, owner, project_id) do
      rows when is_list(rows) -> rows
      _ -> []
    end
  end

  defp note_candidates(owner, project_id) do
    case ProductionTools.list_tool_candidates(Fount.Repo, owner, project_id) do
      rows when is_list(rows) -> Enum.filter(rows, &(&1["kind"] == "note"))
      _ -> []
    end
  end


  defp cast_candidates(owner, project_id) do
    case ProductionTools.list_tool_candidates(Fount.Repo, owner, project_id) do
      rows when is_list(rows) -> Enum.filter(rows, &(&1["kind"] == "cast"))
      _ -> []
    end
  end

  defp note_reviews(owner, project_id) do
    case ProductionTools.note_reviews(Fount.Repo, owner, project_id) do
      rows when is_list(rows) -> rows
      _ -> []
    end
  end

  defp table_reads(owner, project_id) do
    case ProductionTools.table_reads(Fount.Repo, owner, project_id) do
      rows when is_list(rows) -> rows
      _ -> []
    end
  end

  defp usefulness_rows(owner, project_id) do
    case ProductionStore.list_usefulness(Fount.Repo, owner, project_id, limit: 100) do
      rows when is_list(rows) -> rows
      _ -> []
    end
  end

  defp usefulness_report(owner, project_id) do
    case ProductionTools.usefulness_report(Fount.Repo, owner, project_id) do
      {:ok, report} -> report
      _ -> nil
    end
  end

  defp project_artifacts(owner, project_id) do
    case ProductionStore.project_artifacts(Fount.Repo, owner, project_id, limit: 100) do
      rows when is_list(rows) -> rows
      _ -> []
    end
  end

  defp review_map(rows, reviewed_revision_id) do
    rows
    |> Enum.filter(&(&1["reviewed_revision_id"] == reviewed_revision_id))
    |> Enum.group_by(& &1["note_id"])
    |> Map.new(fn {note_id, note_rows} -> {note_id, List.first(note_rows)} end)
  end

  defp review_for(rows, note_id, reviewed_revision_id) do
    Enum.find(rows, &(&1["note_id"] == note_id and &1["reviewed_revision_id"] == reviewed_revision_id))
  end

  defp review_history(rows, note_id), do: Enum.filter(rows, &(&1["note_id"] == note_id))

  defp review_conflict_value(%{note_id: note_id, attempted: attempted}, note_id, key, _review),
    do: Map.get(attempted, key)

  defp review_conflict_value(_conflict, _note_id, key, review) when is_map(review),
    do: Map.get(review, key)

  defp review_conflict_value(_conflict, _note_id, "response", _review), do: "open"
  defp review_conflict_value(_conflict, _note_id, _key, _review), do: nil

  defp review_conflict_version(%{note_id: note_id, saved: saved}, note_id), do: saved["version"]
  defp review_conflict_version(_conflict, _note_id), do: nil

  defp note_state_label("active"), do: "Passage unchanged"
  defp note_state_label("active_untracked"), do: "Passage resolves; earlier fingerprint unavailable"
  defp note_state_label("stale_changed"), do: "The passage changed"
  defp note_state_label("unresolved"), do: "The passage is no longer in this draft"
  defp note_state_label(value), do: value |> to_string() |> String.replace("_", " ")

  defp note_source_excerpt(model, note) do
    case Fount.Target.resolve(model, note.target) do
      {:ok, element} ->
        element
        |> Map.get(:text, "")
        |> to_string()
        |> String.replace(~r/\s+/u, " ")
        |> String.trim()
        |> String.slice(0, 220)

      _ ->
        nil
    end
  end

  defp note_bound_source_label(note, current_revision_id) do
    if note.bound_revision_id == current_revision_id, do: "Current draft", else: "Earlier bound revision"
  end

  defp review_actor_label(_row), do: "Signed-in reviewer"

  defp review_source_label(row, current_revision_id) do
    if row["reviewed_revision_id"] == current_revision_id,
      do: "Current draft",
      else: "Earlier reviewed revision"
  end

  defp review_time(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")
  defp review_time(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")
  defp review_time(_), do: "time not recorded"

  defp current_pdf_artifact(artifacts, revision_id) do
    Enum.find(artifacts, fn artifact ->
      artifact["kind"] == "pdf" and artifact["state"] == "ready" and artifact["revision_id"] == revision_id
    end)
  end

  defp submission_profile("nicholl_2026_27"), do: FountWorkshop.Submission.profile(:nicholl_2026_27)
  defp submission_profile("black_list"), do: FountWorkshop.Submission.profile(:black_list)
  defp submission_profile(_), do: {:error, :unknown_profile}

  defp submission_page_size("us_letter"), do: :us_letter
  defp submission_page_size("a4"), do: :a4
  defp submission_page_size(value) when is_atom(value), do: value
  defp submission_page_size(_), do: nil

  defp submission_item({:page_count_outside_target_range, pages, range}),
    do: "Page count #{pages} is outside the target range #{range.first}–#{range.last}."

  defp submission_item({:blank_pdf_pages, pages}),
    do: "Blank PDF pages were detected: #{Enum.join(pages, ", ")}."

  defp submission_item(value) when is_atom(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp submission_item(value), do: inspect(value)

  defp artifact_ref(artifacts, artifact), do: ReadingArtifacts.artifact_ref(artifacts, artifact)

  defp artifact_format_note(%{"kind" => "pdf"} = artifact) do
    pages = get_in(artifact, ["metadata", "pages"])
    if is_integer(pages), do: "Fixed-layout PDF · #{pages} pages", else: "Fixed-layout PDF · page count unavailable"
  end

  defp artifact_format_note(%{"kind" => kind} = artifact) when kind in ["fountain", "fdx"] do
    losses = get_in(artifact, ["metadata", "losses"]) || []
    if losses == [], do: "Editable #{String.upcase(kind)} export · no recorded conversion losses", else: "Editable #{String.upcase(kind)} export · #{length(losses)} recorded conversion note(s)"
  end

  defp artifact_format_note(%{"kind" => "notes_memo"} = artifact) do
    count = get_in(artifact, ["metadata", "note_count"]) || 0
    "Plain-text notes memo · #{count} selected note(s)"
  end

  defp artifact_format_note(_artifact), do: "Saved project artifact"

  defp feedback_attrs(workspace, params) do
    outcome =
      case params["outcome"] do
        "useful" -> "positive"
        "not_useful" -> "negative"
        _ -> "neutral"
      end

    dimensions =
      (params["dimensions"] || %{})
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    %{
      "id" => params["id"],
      "task_id" => workspace.access["display_label"] || "Saved task",
      "condition" => "fount_assisted",
      "outcome" => outcome,
      "kept_original" => params["kept_original"],
      "preference" => if(params["kept_original"] in [true, "true", "on", "1"], do: "original", else: nil),
      "notes" => params["notes"],
      "dimensions" => dimensions,
      "output_refs" => feedback_output_refs(workspace),
      "friction" => params["friction"]
    }
  end

  defp reviewable_run?(run),
    do: run["status"] in ~w(completed_candidate completed_accepted)

  defp feedback_for(rows, run), do: Enum.find(rows, &(&1["run_id"] == run["run_id"]))

  defp feedback_response(nil), do: %{}
  defp feedback_response(row), do: get_in(row, ["record", "human_response"]) || %{}

  defp feedback_outcome(row) do
    case feedback_response(row)["outcome"] do
      "positive" -> "useful"
      "negative" -> "not_useful"
      "neutral" -> "mixed"
      _ -> nil
    end
  end

  defp feedback_kept_original?(row), do: feedback_response(row)["kept_original"] == true
  defp feedback_notes(row), do: feedback_response(row)["notes"] |> List.wrap() |> Enum.join("\n")
  defp feedback_friction(row), do: feedback_response(row)["friction"] |> List.wrap() |> Enum.join("\n")
  defp feedback_dimension(row, key), do: get_in(feedback_response(row), ["dimensions", key])

  defp feedback_output_refs(workspace) do
    refs =
      [
        workspace.run["selected_candidate_id"],
        Enum.find_value(workspace.progress["steps"] || [], &get_in(&1, ["result", "candidate_id"]))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.join(refs, "\n")
  end

  defp feedback_feature(run, feature) do
    text = String.downcase((run["display_label"] || "") <> " " <> inspect(run["plan"] || %{}))

    case feature do
      :voice -> String.contains?(text, "dialogue") or String.contains?(text, "character")
      :alternatives -> String.contains?(text, "alternative")
    end
  end

  defp parse_nonnegative(value) when is_integer(value) and value >= 0, do: value

  defp parse_nonnegative(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> number
      _ -> 0
    end
  end

  defp parse_nonnegative(_), do: 0

  defp normalize_scroll_mode(value) when value in ["manual", "auto", "paused"], do: value
  defp normalize_scroll_mode(_), do: "manual"

  defp human_artifact_error(reason) when is_binary(reason), do: reason
  defp human_artifact_error(reason), do: inspect(reason)

  defp table_read_ref(reads, read) do
    case Enum.find_index(reads, &(&1["id"] == read["id"])) do
      nil -> nil
      index -> "read-#{index + 1}"
    end
  end

  defp read_title(read) do
    case get_in(read, ["packet", "display_title"]) do
      title when is_binary(title) and title != "" -> title
      _ ->
        scenes = get_in(read, ["packet", "scene_context"]) || []

        case scenes do
          [] -> "Saved table read"
          [%{"heading" => heading}] -> heading || "One-scene table read"
          _ -> "#{length(scenes)}-scene table read"
        end
    end
  end

  defp read_saved_time(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")
  defp read_saved_time(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")
  defp read_saved_time(_), do: "date not recorded"

  defp read_source_label(read, current_revision_id) do
    if read["revision_id"] == current_revision_id, do: "Current draft", else: "Earlier saved draft"
  end

  defp reaction_value(%{attempted: attempted}, key), do: Map.get(attempted, key)
  defp reaction_value(_conflict, _key), do: nil

  defp protection_labels(model, passages) do
    Enum.map(passages, fn passage ->
      target = passage["target"]

      case Fount.Target.resolve(model, target) do
        {:ok, element} ->
          "#{human_type(element.type)} · #{String.slice(element.text || "", 0, 90)}"

        _ ->
          "Protected passage"
      end
    end)
  end

  defp validate_project_title(""), do: {:error, "Project title cannot be blank."}

  defp validate_project_title(title) when byte_size(title) > 160,
    do: {:error, "Keep the project title under 160 bytes."}

  defp validate_project_title(_title), do: :ok

  defp optional_text(value, max_bytes, label) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:ok, nil}

      byte_size(value) > max_bytes ->
        {:error, "#{label} is too long. Keep it under #{max_bytes} bytes."}

      true ->
        {:ok, value}
    end
  end

  defp optional_text(_, _max_bytes, _label), do: {:ok, nil}

  defp runs(owner, project_id) do
    case Store.list_project_runs(Fount.Repo, owner, project_id, limit: 30) do
      rows when is_list(rows) -> rows
      _ -> []
    end
  end

  defp drafts(owner, project_id) do
    case AuthoringStore.list_project_drafts(Fount.Repo, owner, project_id, 12) do
      rows when is_list(rows) -> rows
      _ -> []
    end
  end

  defp human_status(status) do
    status
    |> to_string()
    |> String.replace("completed_candidate", "proposed writing ready")
    |> String.replace("completed_accepted", "accepted")
    |> String.replace("waiting_for_decision", "needs a decision")
    |> String.replace("waiting_for_approval", "needs review")
    |> String.replace("_", " ")
  end

  defp target_value(%{"kind" => kind, "id" => id}) when is_binary(kind) and is_binary(id),
    do: "#{kind}:#{id}"

  defp target_value(_), do: ""

  defp human_type(type), do: type |> to_string() |> String.replace("_", " ")
  defp task_label(run), do: run["display_label"] || "Saved task"
  defp task_key(run), do: run["display_key"]

  defp action_label(id),
    do:
      (Enum.find(WorkflowManagement.action_catalog(), &(&1["id"] == id)) || %{})["label"] ||
        "Creative work"

  defp task_error(:project_screenplay_mismatch),
    do: "The project source changed and this task could not be created."

  defp task_error(_),
    do: "The task could not be created. Manual reading and writing remain available."

  defp creative_error(:question_required),
    do: "Start with the creative question or direction you want the task to answer."

  defp creative_error(:selection_required),
    do: "Choose at least one named source passage, scene or character."

  defp creative_error(:selection_limit),
    do: "Choose at most #{CreativeWorkspace.max_scope()} source targets for one task."

  defp creative_error(:multi_launch_limit),
    do:
      "Multi-launch supports at most #{WorkflowManagement.max_multi_launch()} independent selected targets."

  defp creative_error(:selection_stale),
    do:
      "The selected screenplay material changed. Reload Work on it and choose the current named source."

  defp creative_error(:protection_limit),
    do: "Protect at most #{CreativeWorkspace.max_protected()} exact passages in one task."

  defp creative_error(:invalid_protected_passage),
    do: "One protected passage is no longer present in this screenplay source."

  defp creative_error(:character_required),
    do: "Choose the named character this task should work on."

  defp creative_error(:note_required), do: "Choose at least one accepted note."

  defp creative_error(:historical_source_required),
    do: "Choose an earlier saved revision to recover from."

  defp creative_error(:historical_scene_required),
    do: "Choose at least one named scene from that historical revision."

  defp creative_error(:recovery_targets_missing_from_history),
    do: "The selected material is not present with the same identity in that historical revision."

  defp creative_error(:direction_required), do: "Give this pass a specific writing direction."

  defp creative_error(:invalid_target_scene_count),
    do: "Sequence work needs a positive target scene count."

  defp creative_error(:number_required),
    do: "This task needs the requested numeric value before it can be reviewed."

  defp creative_error(:invalid_number), do: "Enter a supported finite numeric value."

  defp creative_error(:policy_unavailable),
    do: "Default candidate-review settings are unavailable for this owner."

  defp creative_error(reason), do: "The brief did not validate: #{inspect(reason)}"

  defp note_error(:candidate_base_stale),
    do:
      "This note proposal is based on an older draft. Reopen Notes and save it again against the current screenplay."

  defp note_error({:stale_revision, _}),
    do: "The screenplay changed before the note was saved. Reload Notes and try again."

  defp note_error(:note_text_required), do: "Write the note before saving it."
  defp note_error(reason), do: "The note could not be saved or accepted: #{inspect(reason)}"

  defp blank_to_default(value, default) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: default, else: value
  end

  defp blank_to_default(_, default), do: default

  defp truthy?(value), do: value in [true, "true", "on", "1"]

  defp section(:work), do: "work"
  defp section(:changes), do: "changes"
  defp section(:notes), do: "notes"
  defp section(:feedback), do: "script"
  defp section(_), do: "script"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :section, section(assigns.live_action))

    ~H"""
    <main class="project-workspace project-tool-screen">
      <FountWeb.CoreComponents.project_header
        project={@project}
        section={@section}
        view="reading"
        source_label="Current draft"
        example={@project["project_kind"] == "example"}
      />

      <FountWeb.CoreComponents.alert :if={@error} kind="warning" title="Project notice">
        {@error}
      </FountWeb.CoreComponents.alert>
      <FountWeb.CoreComponents.alert :if={@notice} kind="info" title="Saved">
        {@notice}
      </FountWeb.CoreComponents.alert>

      <section :if={@live_action == :work} class="tool-page creative-workspace">
        <header class="compact-page-heading">
          <div>
            <p class="eyebrow">Creative work</p><h1>Work on it</h1>
          </div>
          <a href="/help#work-on-it">Help</a>
        </header>
        <p>
          Ask one short question, bind it to actual screenplay material, then review the saved brief before a durable task is created.
        </p>

        <form
          id="creative-brief"
          phx-hook="CreativeBrief"
          phx-submit="preview_creative_task"
          class="creative-brief stack"
        >
          <label class="brief-question">
            <span>What do you want to change or understand?</span>
            <textarea
              name="task[question]"
              maxlength="4096"
              required
              placeholder="Make the handoff between Scenes 12 and 13 feel inevitable without making Nora explain it."
            ></textarea>
          </label>

          <div class="brief-two-column">
            <details id="creative-scope-picker">
              <summary>Work on · whole screenplay by default</summary>
              <fieldset id="creative-scope" class="choice-picker" phx-hook="ChoiceFilter">
                <legend>Work on</legend>
                <input
                  type="search"
                  data-choice-filter
                  placeholder="Find a scene, character or line"
                  aria-label="Find screenplay material"
                />
                <p class="scope-note">
                  Choose up to {CreativeWorkspace.max_scope()} exact source targets, or the whole screenplay. Search is capped at 300 named choices.
                </p>
                <div class="choice-list" data-choice-list>
                  <label :for={option <- @scope_options} data-choice={String.downcase(option.label)}>
                    <input
                      type="checkbox"
                      name="task[scope][]"
                      value={option.value}
                      checked={option.value == "whole"}
                    />
                    <span>{option.label}</span>
                  </label>
                </div>
              </fieldset>
            </details>
            <details id="creative-protection-picker">
              <summary>Protect exact text · optional</summary>
              <fieldset id="creative-protections" class="choice-picker" phx-hook="ChoiceFilter">
                <legend>Protect exact text <span class="optional">optional</span></legend>
                <input
                  type="search"
                  data-choice-filter
                  placeholder="Find a passage to protect"
                  aria-label="Find passages to protect"
                />
                <p class="scope-note">
                  Protected text is checked byte-for-byte before and after the proposed writing. Choose up to {CreativeWorkspace.max_protected()} passages from a 300-choice searchable list.
                </p>
                <div class="choice-list" data-choice-list>
                  <label
                    :for={option <- @protection_options}
                    data-choice={String.downcase(option.label)}
                  >
                    <input type="checkbox" name="task[protected][]" value={option.value} />
                    <span>{option.label}</span>
                  </label>
                </div>
              </fieldset>
            </details>
          </div>

          <fieldset class="creative-family-grid creative-family-grid--primary">
            <legend>Choose the kind of work</legend>
            <label :for={action <- @primary_workflow_actions} class="creative-family">
              <input
                type="radio"
                name="task[action]"
                value={action["id"]}
                checked={action["id"] == "rewrite"}
              />
              <strong>{action["label"]}</strong><span>{action["summary"]}</span>
            </label>
          </fieldset>

          <div class="brief-shortcuts" aria-label="Common screenplay questions">
            <span>Quick starts:</span>
            <button
              type="button"
              data-creative-preset
              data-action="pass"
              data-profile="dialogue_subtext"
              data-question="Let the dialogue imply more without changing the facts."
            >Let the dialogue imply more</button>
            <button
              type="button"
              data-creative-preset
              data-action="investigate"
              data-question="Where is exposition doing work the audience could understand another way?"
            >Look for exposition</button>
            <button
              type="button"
              data-creative-preset
              data-action="investigate"
              data-question="Where does the upper hand shift in this selected material, and is the shift legible on the page?"
            >Explore who has the upper hand</button>
          </div>

          <details class="all-tasks">
            <summary>All tasks</summary>
            <div id="creative-task-catalog" class="choice-picker" phx-hook="ChoiceFilter">
              <label class="sr-only" for="creative-task-search">Find a creative task</label>
              <input
                id="creative-task-search"
                type="search"
                data-choice-filter
                placeholder="Find a task"
              />
              <div :for={group <- @workflow_action_groups} class="creative-task-group">
                <h3>{group.label}</h3>
                <div class="creative-family-grid creative-family-grid--catalog">
                  <label
                    :for={action <- group.actions}
                    class="creative-family"
                    data-choice={String.downcase(action["label"] <> " " <> action["summary"])}
                  >
                    <input type="radio" name="task[action]" value={action["id"]} />
                    <strong>{action["label"]}</strong><span>{action["summary"]}</span>
                  </label>
                </div>
              </div>
            </div>
          </details>

          <details class="task-details">
            <summary>Details for this task</summary>
            <div class="compact-form-grid">
              <label data-task-actions="pass">
                Focused-pass profile
                <select name="task[profile]">
                  <option :for={profile <- CreativeWorkspace.pass_profiles()} value={profile}>
                    {String.replace(profile, "_", " ")}
                  </option>
                </select>
              </label>
              <label data-task-actions="alternatives">Alternative count
              <input type="number" name="task[alternatives]" min="2" max="6" value="3" /></label>
              <label data-task-actions="sequence">Target scene count
              <input type="number" name="task[target_scene_count]" min="1" max="80" /></label>
              <label data-task-actions="character">
                Character
                <select name="task[character_id]"><option value="">Choose a character</option><option
                  :for={character <- @characters}
                  value={character.id}
                >
                  {character.display_name}
                </option></select>
              </label>
              <label data-task-actions="develop">
                Placement
                <select name="task[placement]"><option value="start">Start of screenplay</option><option
                  :for={scene <- @context.index.scenes}
                  value={"after_scene:#{scene.id}"}
                >
                  After Scene {scene.ordinal} · {scene.heading}
                </option></select>
              </label>
              <label data-task-actions="recover">
                Historical source
                <select name="task[source_revision_id]"><option value="">
                  Choose an earlier revision
                </option><option :for={revision <- @historical_sources} value={revision.id}>
                  {revision.label}
                </option></select>
              </label>
              <label class="full-span" data-task-actions="recover">
                Historical scene(s) to recover
                <select name="task[source_targets][]" multiple size="6">
                  <optgroup :for={revision <- @historical_sources} label={revision.label}>
                    <option :for={scene <- revision.scenes} value={scene.value}>{scene.label}</option>
                  </optgroup>
                </select>
                <span class="scope-note">Choose scenes from the same named historical source. The list is capped at 12 prior revisions and 40 scenes per revision.</span>
              </label>
              <label data-task-actions="recover">
                Recovery destination
                <select name="task[destination]"><option value="start">
                  Start of current screenplay
                </option><option
                  :for={scene <- @context.index.scenes}
                  value={"after_scene:#{scene.id}"}
                >
                  After Scene {scene.ordinal} · {scene.heading}
                </option></select>
              </label>
              <fieldset
                id="creative-note-picker"
                class="choice-picker full-span"
                data-task-actions="notes"
                phx-hook="ChoiceFilter"
              >
                <legend>Accepted notes</legend>
                <input
                  type="search"
                  data-choice-filter
                  placeholder="Find an accepted note"
                  aria-label="Find accepted notes"
                />
                <p class="scope-note">
                  Choose from up to 100 accepted notes bound to this screenplay source.
                </p>
                <div class="choice-list" data-choice-list>
                  <label
                    :for={note <- Enum.take(@notes, 100)}
                    data-choice={String.downcase((note.title || "") <> " " <> (note.text || ""))}
                  >
                    <input type="checkbox" name="task[note_ids][]" value={note.id} />
                    <span>{note.title || String.slice(note.text || "Untitled note", 0, 100)} · {String.replace(
                      note.target_state,
                      "_",
                      " "
                    )}</span>
                  </label>
                </div>
              </fieldset>
              <label class="full-span" data-task-actions="alternatives">Distinct approaches
              <span class="optional">one per line</span><textarea
                name="task[approaches]"
                maxlength="2000"
              ></textarea></label>
              <label
                class="full-span"
                data-task-actions="develop rewrite pass alternatives sequence character propagate notes"
              >What must stay strong?
              <span class="optional">one per line</span><textarea
                name="task[protected_strengths]"
                maxlength="2000"
              ></textarea></label>
              <label data-task-actions="develop rewrite pass alternatives sequence character propagate notes">Intended effect
              <input name="task[intended_effect]" maxlength="500" /></label>
              <label data-task-actions="develop rewrite pass alternatives sequence character propagate notes investigate">Open question
              <input name="task[pending_question]" maxlength="500" /></label>
              <label class="inline-check" data-task-actions="alternatives"><input
                type="checkbox"
                name="task[allow_brief_departure]"
                value="true"
              /> Alternatives may depart from the brief</label>
              <label class="inline-check" data-task-actions="recover"><input
                type="checkbox"
                name="task[adapt]"
                value="true"
              /> Adapt recovered material to the current destination</label>
              <label
                class="inline-check full-span"
                data-task-actions="rewrite pass alternatives sequence character propagate investigate"
              >
                <input type="checkbox" name="task[multi_launch]" value="true" />
                Start one independent task for each selected target (maximum {WorkflowManagement.max_multi_launch()})
              </label>
            </div>
          </details>

          <button type="submit">Review brief</button>
        </form>

        <section
          :if={@creative_preview}
          class="card creative-review"
          aria-label="Validated creative brief"
        >
          <p class="eyebrow">Validated brief</p><h2>{@creative_review.action}</h2>
          <p><strong>Question:</strong> {@creative_review.question}</p>
          <div :for={entry <- @creative_preview["entries"]}>
            <h3>Selected source</h3>
            <ul>
              <li :for={target <- entry["preview"]}>{target["label"]}</li>
            </ul>
            <div :if={entry["passages"] != []} class="brief-passage-preview">
              <h3>Passage preview</h3>
              <blockquote :for={passage <- entry["passages"]}>
                <span>{human_type(passage["type"])}</span>
                <p>{passage["excerpt"]}</p>
              </blockquote>
              <p class="scope-note">
                Preview is capped at 12 selected source fragments; the saved task keeps the exact full selection.
              </p>
            </div>
          </div>
          <div :if={@creative_review.protections != []}>
            <h3>Protected passages</h3><ul>
              <li :for={label <- @creative_review.protections}>{label}</li>
            </ul>
          </div>
          <p class="scope-note">
            Starting this saves a durable task. Proposed writing remains separate from the current screenplay until explicit acceptance.
          </p>
          <button type="button" phx-click="confirm_creative_task">Start this work</button>
        </section>

        <.task_list runs={@runs} project={@project} />
      </section>

      <section :if={@live_action == :changes} class="tool-page">
        <header class="compact-page-heading">
          <div>
            <p class="eyebrow">Saved work</p><h1>Changes</h1>
          </div><a href="/help#changes">Help</a>
        </header>
        <p>
          Strategy choices and actual proposed pages are distinct. Open Review to compare the exact current source with saved proposed writing; acceptance remains a separate decision.
        </p>
        <.task_list runs={@runs} project={@project} mode="changes" />
      </section>

      <section :if={@live_action == :notes} class="tool-page notes-workspace">
        <header class="compact-page-heading">
          <div><p class="eyebrow">Source-bound annotations</p><h1>Notes</h1></div>
          <a href="/help#notes">Help</a>
        </header>
        <p>
          Notes stay bound to exact screenplay material. Saving, editing, deleting or remapping creates proposed work first. A reviewer response records what a human did with a note on a named revision; it never accepts pages or resolves itself from model output.
        </p>
        <p :if={@note_prefill_notice} class="source-note">{@note_prefill_notice}</p>

        <div class="review-split">
          <form phx-submit="save_note" class="card compact-form note-compose">
            <h2>Add a note</h2>
            <label>
              Source passage
              <select name="note[target]" required>
                <option :for={option <- @target_options} value={option.value} selected={option.value == @note_prefill_target}>{option.label}</option>
              </select>
            </label>
            <label>Title <input name="note[title]" maxlength="200" /></label>
            <label>
              Category <span class="optional">optional and clearable</span>
              <select name="note[category]">
                <option value="">No category</option>
                <option :for={category <- @note_categories} value={category}>{category}</option>
              </select>
            </label>
            <label>Note <textarea name="note[text]" maxlength="20000" required></textarea></label>
            <button type="submit">Save proposed note</button>
            <p class="scope-note">This does not change the current screenplay.</p>
          </form>

          <form phx-submit="search_note_targets" class="card compact-form">
            <h2>Find a passage to remap</h2>
            <label>Exact literal search <input name="target_search[query]" maxlength="500" /></label>
            <button type="submit">Find passages</button>
            <p class="scope-note">Current draft only · literal source search · up to 80 distinct passage choices.</p>
            <ol :if={@note_target_results != []} class="compact-results named-target-results">
              <li :for={result <- @note_target_results}><span>{result.label}</span></li>
            </ol>
          </form>
        </div>

        <form phx-submit="filter_notes" class="card compact-form note-filters">
          <div class="compact-page-heading"><h2>Find notes</h2><span>{length(@notes)} shown</span></div>
          <div class="compact-form-grid">
            <label>Text <input name="notes[query]" value={@note_filters["query"]} maxlength="500" /></label>
            <label>
              Source status
              <select name="notes[status]">
                <option value="" selected={@note_filters["status"] in [nil, ""]}>All</option>
                <option value="active" selected={@note_filters["status"] == "active"}>Passage unchanged</option>
                <option value="active_untracked" selected={@note_filters["status"] == "active_untracked"}>Passage resolves; earlier fingerprint unavailable</option>
                <option value="stale_changed" selected={@note_filters["status"] == "stale_changed"}>The passage changed</option>
                <option value="unresolved" selected={@note_filters["status"] == "unresolved"}>The passage is no longer in this draft</option>
              </select>
            </label>
            <label>
              Category
              <select name="notes[category]">
                <option value="" selected={@note_filters["category"] in [nil, ""]}>All</option>
                <option :for={category <- @note_categories} value={category} selected={@note_filters["category"] == category}>{category}</option>
              </select>
            </label>
          </div>
          <button type="submit">Filter notes</button>
        </form>

        <section :if={@note_candidates != []} class="card">
          <h2>Proposed note changes</h2>
          <article :for={candidate <- @note_candidates} class="note-row">
            <div>
              <strong>{if get_in(candidate, ["metadata", "action"]) == "delete", do: "Proposed note deletion", else: "Proposed note change"}</strong>
              <span> · {human_status(candidate["decision"])}</span>
            </div>
            <button
              :if={candidate["decision"] == "proposed"}
              type="button"
              phx-click="accept_note_candidate"
              phx-value-candidate_id={candidate["candidate_id"]}
            >Make this note change current</button>
          </article>
        </section>

        <form :if={@notes != []} phx-submit="build_notes_memo" class="card compact-form notes-memo-builder">
          <h2>Notes memo</h2>
          <p>Select exact accepted notes for a deterministic memo. Nothing is sent automatically.</p>
          <div class="choice-list notes-memo-choices">
            <label :for={note <- @notes}>
              <input type="checkbox" name="memo[note_ids][]" value={note.id} />
              <span>{note.title || String.slice(note.text || "Untitled note", 0, 100)}</span>
            </label>
          </div>
          <div class="compact-form-grid">
            <label>From <input name="memo[from]" maxlength="200" /></label>
            <label>To <input name="memo[to]" maxlength="200" /></label>
          </div>
          <label class="inline-check"><input type="checkbox" name="memo[include_responses]" value="true" /> Include actual saved reviewer responses on this exact draft</label>
          <button type="submit">Build notes memo</button>
        </form>

        <section :if={Enum.any?(@project_artifacts, &(&1["kind"] == "notes_memo"))} class="card notes-memo-artifacts">
          <h2>Built notes memos</h2>
          <article :for={artifact <- Enum.filter(@project_artifacts, &(&1["kind"] == "notes_memo"))} class="artifact-row">
            <div>
              <strong>{artifact["filename"]}</strong>
              <span> · {artifact["source_label"]} · {human_status(artifact["state"])}</span>
            </div>
            <p :if={artifact["error"]} class="ui-field__error">{artifact["error"]}</p>
            <nav :if={artifact["state"] == "ready" and artifact_ref(@project_artifacts, artifact)}>
              <a href={"/p/#{@project["key"]}/artifacts/#{artifact_ref(@project_artifacts, artifact)}/preview"}>Preview memo</a>
              <a href={"/p/#{@project["key"]}/artifacts/#{artifact_ref(@project_artifacts, artifact)}/download"}>Download memo</a>
            </nav>
          </article>
        </section>

        <p :if={@notes != []} class="inline-actions"><a href={"/p/#{@project["key"]}/notes/export.json"}>Export accepted notes JSON</a></p>

        <section class="note-list">
          <p :if={@notes == []}>No accepted source-bound notes match these filters.</p>
          <article :for={note <- @notes} class="card note-card" id={"note-#{note.id}"}>
            <% review = review_for(@note_reviews, note.id, @context.current.revision.id) %>
            <% review_response = review_conflict_value(@note_review_conflict, note.id, "response", review) %>
            <% review_comment = review_conflict_value(@note_review_conflict, note.id, "comment", review) %>
            <% review_version = review_conflict_version(@note_review_conflict, note.id) || if(review, do: review["version"], else: 0) %>
            <% history = review_history(@note_reviews, note.id) %>
            <% source_excerpt = note_source_excerpt(@context.current, note) %>
            <div class="note-card-heading">
              <div>
                <p class="eyebrow">{note_state_label(note.target_state)}</p>
                <h2>{note.title || "Untitled note"}</h2>
              </div>
              <button type="button" phx-click="work_on_note" phx-value-note_id={note.id}>Work on this note now</button>
            </div>
            <p>{note.text}</p>
            <p :if={note.category} class="note-category">Category: <strong>{note.category}</strong></p>
            <blockquote :if={source_excerpt} class="source-excerpt">{source_excerpt}</blockquote>
            <p :if={is_nil(source_excerpt)} class="scope-note">The bound source passage is not available in the current draft.</p>
            <p class="scope-note">
              Source status: <strong>{note_state_label(note.target_state)}</strong> · {note_bound_source_label(note, @context.current.revision.id)}. Exact source identity is retained internally.
            </p>

            <details class="note-edit-panel">
              <summary>Edit or remap this note</summary>
              <form phx-submit="save_note" class="compact-form">
                <input type="hidden" name="note[id]" value={note.id} />
                <input type="hidden" name="note[target]" value={target_value(note.target)} />
                <label>Title <input name="note[title]" value={note.title} maxlength="200" /></label>
                <label>
                  Category <span class="optional">optional and clearable</span>
                  <select name="note[category]">
                    <option value="" selected={is_nil(note.category)}>No category</option>
                    <option :for={category <- @note_categories} value={category} selected={note.category == category}>{category}</option>
                  </select>
                </label>
                <label>Note <textarea name="note[text]" maxlength="20000" required>{note.text}</textarea></label>
                <label>
                  Remap to a named search result <span class="optional">optional</span>
                  <select name="note[target_override]">
                    <option value="">Keep current exact target</option>
                    <option :for={result <- @note_target_results} value={result.value}>{result.label}</option>
                  </select>
                </label>
                <div class="inline-actions">
                  <button type="submit">Save proposed change</button>
                  <button type="button" phx-click="delete_note" phx-value-note_id={note.id}>Propose deletion</button>
                </div>
              </form>
            </details>

            <div :if={@note_review_conflict && @note_review_conflict.note_id == note.id} class="conflict-panel note-review-conflict" role="alert">
              <strong>Reviewer response changed in another tab.</strong>
              <p>Your attempted response is preserved: {human_status(@note_review_conflict.attempted["response"] || "open")}.</p>
              <p>Saved response: {human_status(@note_review_conflict.saved["response"])} · {review_time(@note_review_conflict.saved["updated_at"])}.</p>
              <button type="button" phx-click="reload_note_review">Reload saved response instead</button>
            </div>

            <form phx-submit="save_note_review" class="note-review-response compact-form">
              <h3>Human response on current draft</h3>
              <input type="hidden" name="review[note_id]" value={note.id} />
              <input type="hidden" name="review[version]" value={review_version} />
              <label>
                Response
                <select name="review[response]">
                  <option value="open" selected={review_response in [nil, "open"]}>Open — no response recorded</option>
                  <option value="addressed" selected={review_response == "addressed"}>Addressed</option>
                  <option value="not_addressed" selected={review_response == "not_addressed"}>Not addressed</option>
                  <option value="deferred" selected={review_response == "deferred"}>Deferred</option>
                </select>
              </label>
              <label>Comment <textarea name="review[comment]" maxlength="4000">{review_comment}</textarea></label>
              <button type="submit">Save reviewer response</button>
              <p class="scope-note">Open means no reviewer-response record for this revision. This action does not accept screenplay changes.</p>
            </form>

            <details :if={history != []} class="review-history">
              <summary>Reviewer response history</summary>
              <ol>
                <li :for={row <- history}>
                  <strong>{human_status(row["response"])}</strong>
                  <span> · {review_source_label(row, @context.current.revision.id)} · {review_actor_label(row)} · {review_time(row["updated_at"])}</span>
                  <p :if={row["comment"]}>{row["comment"]}</p>
                </li>
              </ol>
            </details>

            <div :for={link <- Enum.filter(@note_links, &(&1["note_id"] == note.id))} class="related-work-row">
              <span>Related work · {link["display_label"] || "Saved task"} · {human_status(link["status"])}</span>
              <a href={"/p/#{@project["key"]}/activity/#{link["display_key"]}"}>Open activity</a>
              <a :if={link["proposal_candidate_id"]} href={"/p/#{@project["key"]}/changes/#{link["display_key"]}"}>Open linked proposal</a>
            </div>
          </article>
        </section>

        <section :if={@creative_preview} class="card creative-review">
          <p class="eyebrow">Related work</p><h2>{@creative_review.action}</h2><p>{@creative_review.question}</p>
          <button type="button" phx-click="confirm_creative_task">Start this work</button>
        </section>
      </section>

      <section :if={@live_action == :analysis} class="tool-page">
        <header>
          <p class="eyebrow">Evidence</p><h1>Analysis</h1>
        </header>
        <p>
          Open saved findings from a real task. Investigate creates a durable source-bound task; this screen does not run inference merely to populate labels.
        </p>
        <.task_list runs={@runs} project={@project} mode="analysis" />
      </section>

      <section :if={@live_action == :cast} class="tool-page character-workspace">
        <header class="compact-page-heading">
          <div><p class="eyebrow">Source facts</p><h1>Cast & locations</h1></div>
          <a href="/help#cast-locations">Help</a>
        </header>
        <p>
          Confirmed cue names, aliases, appearances and scene headings come from the selected screenplay source. Unknown or unparsed location/time facts stay unknown; this is not a production schedule.
        </p>
        <p class="scope-note">Approximate length: {@estimates.pages.label} · Read duration: {@estimates.duration.label}. These are derived reading approximations, not production page locks or schedule estimates.</p>

        <div class="character-grid">
          <article :for={character <- @characters} class="card compact-character-card">
            <h2>{character.display_name}</h2>
            <p>{character.dialogue_block_count} dialogue blocks · {character.appearance_count} scenes · {character.confirmed_mentions} confirmed mentions</p>
            <p :if={character.aliases != []}>Aliases: {Enum.join(character.aliases, ", ")}</p>
            <div class="inline-actions">
              <button type="button" phx-click="read_character" phx-value-character_id={character.id}>Read this character’s dialogue</button>
            </div>
            <form phx-submit="preview_cast_rename" class="compact-form">
              <input type="hidden" name="rename[character_id]" value={character.id} />
              <label>Prepare name change <input name="rename[new_name]" maxlength="120" required /></label>
              <button type="submit">Preview affected source</button>
            </form>
          </article>
        </div>

        <section :if={@cast_rename_preview} class="card creative-review">
          <p class="eyebrow">Proposed name change</p>
          <h2>Prepare {@cast_rename_preview.new_name}</h2>
          <p>
            {length(@cast_rename_preview.plan.cue_operations)} confirmed cue edits will be included.
            {length(@cast_rename_preview.plan.review)} suggested prose mentions remain review-only and are not silently rewritten.
          </p>
          <button type="button" phx-click="save_cast_rename">Save proposed name change</button>
          <p class="scope-note">Saving creates proposed work only. Current pages remain unchanged until deliberate Core acceptance.</p>
        </section>

        <section :if={@cast_candidates != []} class="card">
          <h2>Saved cast proposals</h2>
          <article :for={candidate <- @cast_candidates} class="note-row">
            <div><strong>{get_in(candidate, ["metadata", "new_name"]) || "Name change"}</strong><span> · {human_status(candidate["decision"])}</span></div>
            <button :if={candidate["decision"] == "proposed"} type="button" phx-click="accept_tool_candidate" phx-value-candidate_id={candidate["candidate_id"]}>Make reviewed name change current</button>
          </article>
        </section>

        <section :if={@character_dialogue} class="character-dialogue-reader">
          <header>
            <p class="eyebrow">Provider-free source reading</p><h2>{@character_dialogue.character.display_name}</h2>
            <p>Showing {length(@character_dialogue.rows)} of {@character_dialogue.total} dialogue blocks.</p>
          </header>
          <article :for={row <- @character_dialogue.rows} class="dialogue-return-card">
            <div class="dialogue-return-heading">
              <strong>{row.scene_heading || "Scene"}</strong><a href={"/p/#{@project["key"]}?source=current#node-#{row.cue_id}"}>Return to passage</a>
            </div>
            <p class="character-cue">{row.character}</p>
            <div :for={line <- row.lines} class="dialogue-line-audition">
              <p>{line.text}</p>
              <form :if={line.type in [:dialogue, :parenthetical]} phx-submit="try_line" class="inline-form">
                <input type="hidden" name="line[element_id]" value={line.id} />
                <input name="line[direction]" maxlength="500" aria-label="Direction for another line" placeholder="Optional direction" />
                <button type="submit">Try another line</button>
              </form>
            </div>
          </article>
        </section>

        <section class="location-list">
          <header><p class="eyebrow">Scene headings</p><h2>Locations</h2></header>
          <p :if={@locations == []}>No parseable scene locations in this draft.</p>
          <details :for={location <- @locations} class="card location-card">
            <summary><strong>{location.location}</strong><span>{length(location.entries)} scenes</span></summary>
            <ol>
              <li :for={entry <- location.entries}>
                <a href={"/p/#{@project["key"]}?scene=#{entry.ordinal}"}>Scene {entry.ordinal} · {entry.heading || "Untitled"}</a>
                <span>{entry.parsed_context} · {entry.parsed_time}</span>
              </li>
            </ol>
          </details>
        </section>

        <section :if={@creative_preview} class="card creative-review">
          <h2>{@creative_review.action}</h2><p>{@creative_review.question}</p>
          <p>Surrounding source protected: {length(@creative_review.protections)} passages.</p>
          <button type="button" phx-click="confirm_creative_task">Start line alternatives</button>
        </section>
      </section>

      <section :if={@live_action == :read} class="tool-page table-read-destination">
        <header class="compact-page-heading">
          <div><p class="eyebrow">Human rehearsal</p><h1>Table read</h1></div>
          <a href="/help#table-read">Help</a>
        </header>
        <p>
          Read exact saved screenplay material with human reader labels, navigation, bookmarks, elapsed time and reactions. Starting or navigating a table read does not create a Run. Microphone capture and automatic performance scoring are not available.
        </p>

        <form phx-submit="create_table_read" class="card compact-form">
          <h2>New saved read</h2>
          <label>Read title <span class="optional">optional</span><input name="read[title]" maxlength="160" placeholder="Act Two table read" /></label>
          <label>
            Material
            <select name="read[scope][]" multiple size="6">
              <option :for={option <- @scope_options} value={option.value} selected={option.value == "whole"}>{option.label}</option>
            </select>
          </label>
          <button type="submit">Save table-read material</button>
          <p class="scope-note">The selection is bound to the exact Current draft shown now. No provider is called.</p>
        </form>

        <section class="saved-read-list card">
          <h2>Saved table reads</h2>
          <p :if={@table_reads == []}>No saved table reads yet.</p>
          <button :for={read <- @table_reads} type="button" phx-click="select_table_read" phx-value-id={read["id"]} class="saved-read-row">
            <strong>{read_title(read)}</strong>
            <span>{length(get_in(read, ["packet", "turns"]) || [])} turns · {read_source_label(read, @context.current.revision.id)} · saved {read_saved_time(read["inserted_at"])}</span>
          </button>
        </section>

        <section
          :if={@selected_read}
          id="table-read-workspace"
          class="table-read-workspace card"
          phx-hook="TableReadWorkspace"
          data-version={@selected_read["version"]}
          data-bookmark-index={@selected_read["bookmark_index"] || 0}
          data-elapsed-ms={@selected_read["elapsed_ms"] || 0}
          data-scroll-mode={@selected_read["scroll_mode"] || "manual"}
        >
          <header>
            <div><p class="eyebrow">Exact saved material</p><h2>{read_title(@selected_read)}</h2></div>
            <p>{ProductionTools.tts_status().label}</p>
          </header>
          <div :if={@table_read_conflict} class="conflict-panel table-read-conflict" role="alert">
            <strong>Table-read navigation changed in another tab.</strong>
            <p>Your local bookmark/timing state is still shown. Saved state: passage {@table_read_conflict.saved["bookmark_index"] + 1}, elapsed {div(@table_read_conflict.saved["elapsed_ms"] || 0, 1000)} seconds.</p>
            <button type="button" phx-click="reload_table_read">Reload saved state instead</button>
          </div>
          <div class="table-read-controls" role="group" aria-label="Table-read controls">
            <button type="button" data-read-prev>Previous</button>
            <button type="button" data-read-toggle>Start / pause</button>
            <button type="button" data-read-next>Next</button>
            <label>Auto-scroll speed
              <select data-read-speed>
                <option value="0.5">0.5×</option><option value="1" selected>1×</option><option value="1.5">1.5×</option><option value="2">2×</option>
              </select>
            </label>
            <button type="button" data-read-bookmark>Bookmark current passage</button>
            <span data-read-elapsed>00:00</span>
          </div>
          <p class="scope-note">Reduced-motion preference keeps manual navigation and disables automatic scrolling.</p>
          <div :if={(get_in(@selected_read, ["packet", "roles"]) || []) != []} class="table-read-roles">
            <strong>Reader roles</strong>
            <span :for={role <- get_in(@selected_read, ["packet", "roles"]) || []}>{role["cue"] || "Reader"}</span>
          </div>
          <ol class="table-read-turns" data-read-turns>
            <li :for={{turn, index} <- Enum.with_index(@selected_read["packet"]["turns"] || [])} data-read-turn data-index={index} tabindex="0" class={if index == (@selected_read["bookmark_index"] || 0), do: "is-bookmarked"}>
              <strong>{turn["cue"]}</strong>
              <p>{turn["dialogue"]}</p>
            </li>
          </ol>
          <div :if={@reaction_conflict} class="conflict-panel reaction-conflict" role="alert">
            <strong>Reaction not saved yet.</strong>
            <p>The table read changed in another tab. Your typed reaction remains in the form below; compare it with the saved read and submit again if it still applies.</p>
            <button type="button" phx-click="reload_table_read">Discard my typed reaction and reload saved state</button>
          </div>
          <form phx-submit="record_reaction" class="compact-form">
            <h3>Human reaction to the current source</h3>
            <label>Reader <input name="reaction[reader_id]" value={reaction_value(@reaction_conflict, "reader_id")} maxlength="120" /></label>
            <label>Reaction <textarea name="reaction[reaction]" maxlength="4000" required>{reaction_value(@reaction_conflict, "reaction")}</textarea></label>
            <label>Reader delivery <input name="reaction[reader_delivery]" value={reaction_value(@reaction_conflict, "reader_delivery")} maxlength="500" /></label>
            <label>Listening conditions <input name="reaction[listening_conditions]" value={reaction_value(@reaction_conflict, "listening_conditions")} maxlength="500" /></label>
            <button type="submit">Save reaction</button>
          </form>
          <ul class="reaction-list">
            <li :for={reaction <- @selected_read["packet"]["reactions"] || []}><strong>{reaction["reader_id"] || "Human reader"}</strong>: {reaction["reaction"]}</li>
          </ul>
          <a :if={table_read_ref(@table_reads, @selected_read)} href={"/p/#{@project["key"]}/table-reads/#{table_read_ref(@table_reads, @selected_read)}/export.json"}>Export saved table-read JSON</a>
        </section>
      </section>

      <section :if={@live_action == :history} class="tool-page">
        <header>
          <p class="eyebrow">Recovery</p><h1>History</h1>
        </header>
        <p>
          Working-draft history is recovery material and does not replace the current screenplay. Creative Recover uses a named committed revision and exact source targets.
        </p>
        <ol class="history-list">
          <li :for={draft <- @drafts}>
            <strong>{if draft["status"] == "active", do: "Working draft", else: "Discarded draft"}</strong><span> · version {draft[
              "version"
            ]} · {human_status(draft["status"])}</span>
          </li>
        </ol>
        <p :if={@drafts == []}>No working-draft recovery history yet.</p>
      </section>

      <section :if={@live_action == :exports} class="tool-page exports-destination">
        <header class="compact-page-heading">
          <div><p class="eyebrow">Exact named source</p><h1>Exports</h1></div>
          <a href="/help#exports">Help</a>
        </header>
        <p>
          Build an artifact from the exact current saved revision. Fountain and FDX remain editable interchange formats; PDF uses the configured real screenplay renderer and inspection pipeline. Build errors are recorded and retryable without changing screenplay state.
        </p>
        <form phx-submit="build_project_export" class="export-build-grid">
          <button type="submit" name="export[format]" value="fountain">Build Fountain</button>
          <button type="submit" name="export[format]" value="fdx">Build FDX</button>
          <button type="submit" name="export[format]" value="pdf">Build PDF</button>
        </form>
        <p class="scope-note">Source: Current draft. Exact source identity is retained with each artifact. A PDF page map is shown only if the renderer actually supplies a verified mapping; it is never inferred from responsive HTML.</p>

        <section class="artifact-list">
          <h2>Project artifacts</h2>
          <p :if={@project_artifacts == []}>No project-level exports built yet.</p>
          <article :for={artifact <- @project_artifacts} class="card artifact-row">
            <div>
              <strong>{artifact["filename"]}</strong>
              <span> · {artifact["source_label"]} · {human_status(artifact["state"])}</span>
            </div>
            <p class="scope-note">{artifact_format_note(artifact)}</p>
            <p :if={artifact["error"]} class="ui-field__error">{artifact["error"]}</p>
            <nav :if={artifact["state"] == "ready" and artifact_ref(@project_artifacts, artifact)}>
              <a :if={artifact["kind"] in ["fountain", "fdx", "notes_memo"]} href={"/p/#{@project["key"]}/artifacts/#{artifact_ref(@project_artifacts, artifact)}/preview"}>Preview</a>
              <a :if={artifact["kind"] == "pdf"} href={"/p/#{@project["key"]}/pages/#{artifact_ref(@project_artifacts, artifact)}"}>Read numbered PDF pages</a>
              <a href={"/p/#{@project["key"]}/artifacts/#{artifact_ref(@project_artifacts, artifact)}/download"}>Download</a>
            </nav>
          </article>
        </section>

        <section class="card submission-checks">
          <h2>Optional dated submission checks</h2>
          <p>These are mechanical checks against a named saved profile, not legal advice, acceptance, endorsement or a current-rule guarantee. The profile shows the date and source it records.</p>
          <form phx-submit="check_submission" class="compact-form">
            <label>Target
              <select name="submission[target]">
                <option value="nicholl_2026_27">Nicholl 2026–27</option>
                <option value="black_list">The Black List</option>
              </select>
            </label>
            <button type="submit" disabled={is_nil(current_pdf_artifact(@project_artifacts, @context.current.revision.id))}>Check current PDF</button>
            <p :if={is_nil(current_pdf_artifact(@project_artifacts, @context.current.revision.id))} class="scope-note">Build the current-draft PDF first. Checks never run against responsive HTML or a stale PDF.</p>
          </form>
          <div :if={@submission_check} class="submission-check-result">
            <p><strong>{human_status(@submission_check.status)}</strong> · checked profile dated {Date.to_iso8601(@submission_check.checked_on)}</p>
            <p><a href={@submission_check.source_url} rel="noreferrer">Recorded rule source</a></p>
            <div class="review-split">
              <section>
                <h3>Mechanical findings</h3>
                <p :if={@submission_check.mechanical_problems == []}>No mechanical problem recorded by this profile.</p>
                <ul><li :for={item <- @submission_check.mechanical_problems}>{submission_item(item)}</li></ul>
              </section>
              <section>
                <h3>Writer review still required</h3>
                <p :if={@submission_check.requires_writer_review == []}>No additional writer-review item recorded by this profile.</p>
                <ul><li :for={item <- @submission_check.requires_writer_review}>{submission_item(item)}</li></ul>
              </section>
            </div>
          </div>
        </section>

        <section :if={@table_reads != []} class="card table-read-export-list">
          <h2>Table-read packets</h2>
          <p>Human table-read exports are exact saved packet JSON, including source binding, reader roles, bookmarks and actual reactions.</p>
          <ul>
            <li :for={read <- @table_reads}>
              <strong>{read_title(read)}</strong> · {read_source_label(read, @context.current.revision.id)}
              <a :if={table_read_ref(@table_reads, read)} href={"/p/#{@project["key"]}/table-reads/#{table_read_ref(@table_reads, read)}/export.json"}>Download table-read JSON</a>
            </li>
          </ul>
        </section>

        <details class="task-bound-exports">
          <summary>Exports from saved tasks</summary>
          <p>Task delivery remains bound to that task’s exact source, checks and acceptance state.</p>
          <.task_list runs={@runs} project={@project} mode="exports" />
        </details>
      </section>

      <section :if={@live_action == :feedback} class="tool-page feedback-destination">
        <header class="compact-page-heading">
          <div><p class="eyebrow">Optional human feedback</p><h1>Feedback</h1></div>
          <a href="/help#feedback">Help</a>
        </header>
        <p>
          Feedback is descriptive human evidence about a real reviewed task. It does not train a preference model here, rank screenplay quality or create an aggregate winner. Engineering facts are attached automatically from the selected task.
        </p>
        <p :if={@reviewable_runs == []}>No completed task result exists to review yet.</p>
        <article :for={run <- @reviewable_runs} class="card feedback-task-card">
          <% saved_feedback = feedback_for(@usefulness_rows, run) %>
          <% saved_outcome = feedback_outcome(saved_feedback) %>
          <h2>{task_label(run)}</h2>
          <p>{human_status(run["status"])}<span :if={saved_feedback}> · saved response reopened below</span></p>
          <form phx-submit="save_feedback" class="compact-form feedback-form">
            <input type="hidden" name="feedback[run_id]" value={run["run_id"]} />
            <input :if={saved_feedback} type="hidden" name="feedback[id]" value={saved_feedback["id"]} />
            <fieldset class="segmented-choice">
              <legend>Was this useful?</legend>
              <label><input type="radio" name="feedback[outcome]" value="useful" checked={saved_outcome == "useful"} required /> Useful</label>
              <label><input type="radio" name="feedback[outcome]" value="mixed" checked={saved_outcome == "mixed"} /> Mixed</label>
              <label><input type="radio" name="feedback[outcome]" value="not_useful" checked={saved_outcome == "not_useful"} /> Not useful</label>
            </fieldset>
            <label class="inline-check"><input type="checkbox" name="feedback[kept_original]" value="true" checked={feedback_kept_original?(saved_feedback)} /> I kept my original</label>
            <fieldset :if={feedback_feature(run, :voice)} class="segmented-choice">
              <legend>Did this keep the character’s voice? <span class="optional">optional</span></legend>
              <label><input type="radio" name="feedback[dimensions][voice_retention]" value="yes" checked={feedback_dimension(saved_feedback, "voice_retention") == "yes"} /> Yes</label>
              <label><input type="radio" name="feedback[dimensions][voice_retention]" value="partly" checked={feedback_dimension(saved_feedback, "voice_retention") == "partly"} /> Partly</label>
              <label><input type="radio" name="feedback[dimensions][voice_retention]" value="no" checked={feedback_dimension(saved_feedback, "voice_retention") == "no"} /> No</label>
              <label><input type="radio" name="feedback[dimensions][voice_retention]" value="" checked={is_nil(feedback_dimension(saved_feedback, "voice_retention"))} /> Clear</label>
            </fieldset>
            <fieldset :if={feedback_feature(run, :alternatives)} class="segmented-choice">
              <legend>Did the alternatives give you different options? <span class="optional">optional</span></legend>
              <label><input type="radio" name="feedback[dimensions][alternative_diversity]" value="yes" checked={feedback_dimension(saved_feedback, "alternative_diversity") == "yes"} /> Yes</label>
              <label><input type="radio" name="feedback[dimensions][alternative_diversity]" value="partly" checked={feedback_dimension(saved_feedback, "alternative_diversity") == "partly"} /> Partly</label>
              <label><input type="radio" name="feedback[dimensions][alternative_diversity]" value="no" checked={feedback_dimension(saved_feedback, "alternative_diversity") == "no"} /> No</label>
              <label><input type="radio" name="feedback[dimensions][alternative_diversity]" value="" checked={is_nil(feedback_dimension(saved_feedback, "alternative_diversity"))} /> Clear</label>
            </fieldset>
            <label>Notes <span class="optional">optional</span><textarea name="feedback[notes]" maxlength="6000">{feedback_notes(saved_feedback)}</textarea></label>
            <details>
              <summary>More detail</summary>
              <p class="scope-note">These independent dimensions are stored separately; none is combined into a score.</p>
              <div class="compact-form-grid">
                <label>Task completion <input name="feedback[dimensions][task_completion]" value={feedback_dimension(saved_feedback, "task_completion")} maxlength="300" /></label>
                <label>Next decision <input name="feedback[dimensions][next_decision]" value={feedback_dimension(saved_feedback, "next_decision")} maxlength="300" /></label>
                <label>Agency <input name="feedback[dimensions][agency]" value={feedback_dimension(saved_feedback, "agency")} maxlength="300" /></label>
                <label>Consequence usefulness <input name="feedback[dimensions][consequence_usefulness]" value={feedback_dimension(saved_feedback, "consequence_usefulness")} maxlength="300" /></label>
                <label>Rejection time (ms) <input type="number" min="0" name="feedback[dimensions][rejection_time_ms]" value={feedback_dimension(saved_feedback, "rejection_time_ms")} /></label>
              </div>
              <label>Friction <span class="optional">one item per line</span><textarea name="feedback[friction]" maxlength="4000">{feedback_friction(saved_feedback)}</textarea></label>
            </details>
            <button type="submit">{if saved_feedback, do: "Update optional feedback", else: "Save optional feedback"}</button>
          </form>
        </article>

        <section class="card feedback-report">
          <div class="compact-page-heading"><h2>Saved responses</h2><a href={"/p/#{@project["key"]}/feedback/export.json"}>Export saved feedback JSON</a></div>
          <%= if @usefulness_report do %>
            <p>{@usefulness_report["sample_label"]}</p>
            <p>{@usefulness_report["missing_data_label"]}</p>
          <% else %>
            <p>No feedback report is available.</p>
          <% end %>
          <article :for={row <- @usefulness_rows} class="evidence-row">
            <div>
              <strong>{row["task_id"]}</strong>
              <span> · {get_in(row, ["record", "human_response", "outcome"])}{if get_in(row, ["record", "human_response", "kept_original"]), do: " · kept original", else: ""}</span>
            </div>
            <button type="button" phx-click="delete_feedback" phx-value-id={row["id"]}>Delete</button>
          </article>
          <p class="scope-note">Every optional dimension remains independent. No combined quality, learning or preference score is computed.</p>
        </section>
      </section>

      <section :if={@live_action == :activity} class="tool-page">
        <header>
          <p class="eyebrow">Durable tasks</p><h1>Activity</h1>
        </header>
        <p>
          Saved stages, decisions, proposed writing and recovery state stay attached to each task. Pause, resume, stop and versioned controls are inside the task.
        </p>
        <.task_list runs={@runs} project={@project} mode="activity" />
      </section>

      <section :if={@live_action == :settings} class="tool-page settings-page">
        <header>
          <p class="eyebrow">Project</p><h1>Project settings</h1>
        </header>
        <form phx-submit="save_project" class="stack">
          <label for="project-title">Title</label><input
            id="project-title"
            name="project[title]"
            value={@project["title"]}
            maxlength="160"
            required
          />
          <label for="project-logline">Logline</label><textarea
            id="project-logline"
            name="project[logline]"
            maxlength="1000"
          >{@project["logline"]}</textarea>
          <label for="project-synopsis">Synopsis</label><textarea
            id="project-synopsis"
            name="project[synopsis]"
            maxlength="4000"
          >{@project["synopsis"]}</textarea>
          <button type="submit">Save project details</button>
        </form>
        <details class="technical-details">
          <summary>Technical details</summary><dl>
            <div>
              <dt>Project identity</dt><dd><code>{@project["id"]}</code></dd>
            </div><div>
              <dt>Screenplay identity</dt><dd><code>{@project["screenplay_id"]}</code></dd>
            </div><div>
              <dt>Internal project key</dt><dd><code>{@project["key"]}</code></dd>
            </div>
          </dl>
        </details>
      </section>
    </main>
    """
  end

  attr :runs, :list, required: true
  attr :project, :map, required: true
  attr :mode, :string, default: "activity"

  def task_list(assigns) do
    ~H"""
    <div class="task-list">
      <p :if={@runs == []}>
        No saved tasks yet. The screenplay is still fully available for reading and writing.
      </p>
      <article :for={run <- @runs} class="task-row">
        <div><strong>{task_label(run)}</strong><span>{human_status(run["status"])}</span></div>
        <nav aria-label={"#{task_label(run)} actions"}>
          <a
            :if={@mode in ["activity", "changes"]}
            href={"/p/#{@project["key"]}/activity/#{task_key(run)}"}
          >Activity</a>
          <a :if={@mode == "changes"} href={"/p/#{@project["key"]}/changes/#{task_key(run)}"}>Review</a>
          <a :if={@mode == "analysis"} href={"/p/#{@project["key"]}/analysis/#{task_key(run)}"}>Open analysis</a>
          <a :if={@mode == "exports"} href={"/p/#{@project["key"]}/exports/#{task_key(run)}"}>Open exports</a>
          <a :if={@mode == "activity"} href={"/p/#{@project["key"]}/activity/#{task_key(run)}/setup"}>Controls</a>
        </nav>
      </article>
    </div>
    """
  end
end
