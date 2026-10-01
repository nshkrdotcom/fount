defmodule FountWeb.ProjectToolsLive do
  use FountWeb, :live_view

  alias FountWeb.{
    AuthoringStore,
    CreativeWorkspace,
    ProductionTools,
    ProjectContext,
    Store,
    WorkflowManagement
  }

  @impl true
  def mount(%{"key" => key}, _session, socket) do
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
         |> assign(:character_dialogue, nil)}

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

    _ =
      ProductionTools.reconcile_note_work_links(Fount.Repo, owner, project_id, context.current.id)

    links = note_work_links(owner, project_id)
    _ = ProductionTools.sync_note_work_results(Fount.Repo, owner, context.current.id, links)
    links = note_work_links(owner, project_id)

    socket
    |> assign(:project, context.project)
    |> assign(:context, context)
    |> assign(:runs, runs(owner, project_id))
    |> assign(:drafts, drafts(owner, project_id))
    |> assign(:scope_options, CreativeWorkspace.scope_options(context.current))
    |> assign(:protection_options, CreativeWorkspace.protection_options(context.current))
    |> assign(:target_options, ProductionTools.target_options(context.current))
    |> assign(:characters, ProductionTools.character_profiles(context.current))
    |> assign(:notes, ProductionTools.notes(context.current))
    |> assign(:note_candidates, note_candidates(owner, project_id))
    |> assign(:note_links, links)
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
          <div>
            <p class="eyebrow">Source-bound annotations</p><h1>Notes</h1>
          </div><a href="/help#notes">Help</a>
        </header>
        <p>
          Notes are exact source facts. Saving a note creates a proposal first; accepting that proposal is separate. A related-work link records that a task was launched from a note, not that the note was resolved.
        </p>

        <form phx-submit="save_note" class="card compact-form note-compose">
          <h2>Add a note</h2>
          <label>
            Source passage
            <select name="note[target]" required><option
              :for={option <- @target_options}
              value={option.value}
            >
              {option.label}
            </option></select>
          </label>
          <label>Title <input name="note[title]" maxlength="200" /></label>
          <label>Note <textarea name="note[text]" maxlength="20000" required></textarea></label>
          <button type="submit">Save proposed note</button>
        </form>

        <section :if={@note_candidates != []} class="card">
          <h2>Proposed notes</h2>
          <article :for={candidate <- @note_candidates} class="note-row">
            <div>
              <strong>Proposed note</strong><span> · {human_status(candidate["decision"])}</span>
            </div>
            <button
              :if={candidate["decision"] == "proposed"}
              type="button"
              phx-click="accept_note_candidate"
              phx-value-candidate_id={candidate["candidate_id"]}
            >Make note current</button>
          </article>
        </section>

        <section class="note-list">
          <p :if={@notes == []}>No accepted source-bound notes yet.</p>
          <article :for={note <- @notes} class="card note-card">
            <div class="note-card-heading">
              <div>
                <p class="eyebrow">{String.replace(note.target_state, "_", " ")}</p><h2>
                  {note.title || "Untitled note"}
                </h2>
              </div><button type="button" phx-click="work_on_note" phx-value-note_id={note.id}>Work on this note now</button>
            </div>
            <p>{note.text}</p>
            <p class="scope-note">
              Source status: <strong>{String.replace(note.target_state, "_", " ")}</strong>. This status describes source binding only.
            </p>
            <div
              :for={link <- Enum.filter(@note_links, &(&1["note_id"] == note.id))}
              class="related-work-row"
            >
              <span>Related work · {link["display_label"] || "Saved task"} · {human_status(
                link["status"]
              )}</span>
              <a href={"/p/#{@project["key"]}/activity/#{link["display_key"]}"}>Open activity</a>
              <a
                :if={link["proposal_candidate_id"]}
                href={"/p/#{@project["key"]}/changes/#{link["display_key"]}"}
              >Open linked proposal</a>
            </div>
          </article>
        </section>

        <section :if={@creative_preview} class="card creative-review">
          <p class="eyebrow">Related work</p><h2>{@creative_review.action}</h2><p>
            {@creative_review.question}
          </p><button type="button" phx-click="confirm_creative_task">Start this work</button>
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
        <header>
          <p class="eyebrow">Source facts</p><h1>Characters</h1>
        </header>
        <p>
          These are literal cue-derived identities. Read one character’s dialogue in source order without creating a task or provider call.
        </p>
        <div class="character-grid">
          <article :for={character <- @characters} class="card compact-character-card">
            <h2>{character.display_name}</h2><p>
              {character.dialogue_block_count} dialogue blocks · {character.appearance_count} scenes
            </p>
            <button type="button" phx-click="read_character" phx-value-character_id={character.id}>Read this character’s dialogue</button>
          </article>
        </div>
        <section :if={@character_dialogue} class="character-dialogue-reader">
          <header>
            <p class="eyebrow">Provider-free source reading</p><h2>
              {@character_dialogue.character.display_name}
            </h2><p>
              Showing {length(@character_dialogue.rows)} of {@character_dialogue.total} dialogue blocks.
            </p>
          </header>
          <article :for={row <- @character_dialogue.rows} class="dialogue-return-card">
            <div class="dialogue-return-heading">
              <strong>{row.scene_heading || "Scene"}</strong><a href={"/p/#{@project["key"]}?source=current#node-#{row.cue_id}"}>Return to passage</a>
            </div>
            <p class="character-cue">{row.character}</p>
            <div :for={line <- row.lines} class="dialogue-line-audition">
              <p>{line.text}</p>
              <form
                :if={line.type in [:dialogue, :parenthetical]}
                phx-submit="try_line"
                class="inline-form"
              >
                <input type="hidden" name="line[element_id]" value={line.id} />
                <input
                  name="line[direction]"
                  maxlength="500"
                  aria-label="Direction for another line"
                  placeholder="Optional direction"
                />
                <button type="submit">Try another line</button>
              </form>
            </div>
          </article>
        </section>
        <section :if={@creative_preview} class="card creative-review">
          <h2>{@creative_review.action}</h2><p>{@creative_review.question}</p><p>
            Surrounding source protected: {length(@creative_review.protections)} passages.
          </p><button type="button" phx-click="confirm_creative_task">Start line alternatives</button>
        </section>
      </section>

      <section :if={@live_action == :read} class="tool-page">
        <header>
          <p class="eyebrow">Performance tools</p><h1>Table read</h1>
        </header>
        <p>
          Existing table-read controls remain task-bound. Microphone capture and automatic performance scoring are not part of this program.
        </p>
        <.task_list runs={@runs} project={@project} mode="tools" />
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

      <section :if={@live_action == :exports} class="tool-page">
        <header>
          <p class="eyebrow">Deliverables</p><h1>Exports</h1>
        </header>
        <p>
          Task-bound delivery artifacts remain available below. Exact fixed-layout screenplay reading remains UX03.
        </p>
        <.task_list runs={@runs} project={@project} mode="exports" />
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
          <a :if={@mode in ["notes", "tools"]} href={"/p/#{@project["key"]}/tools/#{task_key(run)}"}>Open tools</a>
          <a :if={@mode == "exports"} href={"/p/#{@project["key"]}/exports/#{task_key(run)}"}>Open exports</a>
          <a :if={@mode == "activity"} href={"/p/#{@project["key"]}/activity/#{task_key(run)}/setup"}>Controls</a>
        </nav>
      </article>
    </div>
    """
  end
end
