defmodule FountWeb.TaskSourceLive do
  use FountWeb, :live_view

  alias FountWeb.{ScreenplayIndex, ScreenplayViews, Store, WorkflowManagement}

  @impl true
  def mount(%{"key" => project_key, "task_key" => task_key} = params, _session, socket) do
    owner = socket.assigns.current_owner

    with {:ok, access} <- Store.run_access_by_task_key(Fount.Repo, owner, project_key, task_key),
         {:ok, context} <- FountWeb.Actors.owner_context(owner, access["screenplay_id"]),
         {:ok, run} <- FountRun.get_run(Fount.Repo, access["run_id"], context),
         {:ok, progress} <- FountRun.progress(Fount.Repo, access["run_id"], context),
         {:ok, workspace} <- ScreenplayViews.load(Fount.Repo, access, run, progress, params["view"]),
         {:ok, base_screenplay} <- load_base_screenplay(run, access) do
      index = ScreenplayIndex.build(workspace.screenplay)
      {workflow_selection, scope_error} = load_workflow_selection(owner, run, context)

      {:ok,
       socket
       |> assign(:project_key, project_key)
       |> assign(:task_key, task_key)
       |> assign(:access, access)
       |> assign(:run, run)
       |> assign(:progress, progress)
       |> assign(:actor_context, context)
       |> assign(:workspace, workspace)
       |> assign(:base_screenplay, base_screenplay)
       |> assign(:workflow_selection, workflow_selection)
       |> assign(:scope_notice, nil)
       |> assign(:scope_error, scope_error)
       |> assign(:index, index)
       |> assign(:selected_scene_id, selected_scene_id(index.scenes, params["scene"]))
       |> assign(:error, nil)}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "That saved task source is not available.")
         |> redirect(to: "/p/#{project_key}")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns[:run] do
      case ScreenplayViews.load(
             Fount.Repo,
             socket.assigns.access,
             socket.assigns.run,
             socket.assigns.progress,
             params["view"]
           ) do
        {:ok, workspace} ->
          index = ScreenplayIndex.build(workspace.screenplay)

          {:noreply,
           socket
           |> assign(:workspace, workspace)
           |> assign(:index, index)
           |> assign(:selected_scene_id, selected_scene_id(index.scenes, params["scene"]))
           |> assign(:error, nil)}

        {:error, _} ->
          {:noreply, assign(socket, :error, "That saved source is stale or no longer bound to this task.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_workflow_scope", %{"scope" => params}, socket) do
    with {:ok, selection} <- WorkflowManagement.selection_from_params(params),
         {:ok, saved} <-
           WorkflowManagement.save_selection(
             Fount.Repo,
             socket.assigns.current_owner,
             socket.assigns.run,
             selection,
             socket.assigns.actor_context
           ) do
      {:noreply,
       socket
       |> assign(:workflow_selection, saved)
       |> assign(:scope_notice, "Task scope saved against this task's exact base screenplay.")
       |> assign(:scope_error, nil)
       |> assign(:error, nil)}
    else
      {:error, :invalid_scope_selection} ->
        {:noreply, assign(socket, :error, "Choose the whole screenplay or at least one scene or element.")}

      {:error, _} ->
        {:noreply, assign(socket, :error, "That scope no longer matches this task's base screenplay. Choose it again.")}
    end
  end

  defp load_base_screenplay(run, access) do
    revision_id = get_in(run, ["plan", "base_revision_id"])

    case Fount.Persistence.load_revision(Fount.Repo, access["screenplay_id"], revision_id) do
      {:ok, screenplay} -> {:ok, screenplay}
      _ -> {:error, :base_revision_unavailable}
    end
  end

  defp load_workflow_selection(owner, run, context) do
    case WorkflowManagement.load_selection(Fount.Repo, owner, run, context) do
      {:ok, saved} ->
        {saved, nil}

      {:error, reason} when reason in [:selection_screenplay_stale, :selection_base_stale, :selection_stale, :invalid_scope_selection] ->
        _ = Store.delete_workflow_selection(Fount.Repo, owner, run["id"])
        {nil, "Saved task scope is stale. Choose material again from this task's exact base screenplay."}

      {:error, _} ->
        {nil, nil}
    end
  end

  defp scope_whole?(%{"selection" => %{"whole_screenplay" => true}}), do: true
  defp scope_whole?(_), do: false

  defp scope_target?(%{"selection" => %{"targets" => targets}}, kind, id) when is_list(targets),
    do: Enum.any?(targets, &(&1["kind"] == kind and &1["id"] == id))

  defp scope_target?(_, _kind, _id), do: false

  defp scope_scene_label(screenplay, scene, ordinal) do
    heading =
      case Fount.Query.node(screenplay, scene.heading_id) do
        nil -> nil
        node -> node.text
      end

    "Scene #{ordinal} · #{heading || "Untitled scene"}"
  end

  defp scope_element_label(element, ordinal) do
    text = element.text |> to_string() |> String.replace(~r/\s+/u, " ") |> String.trim() |> String.slice(0, 68)
    type = element.type |> to_string() |> String.replace("_", " ")
    if text == "", do: "Element #{ordinal} · #{type}", else: "Element #{ordinal} · #{type} · #{text}"
  end

  defp selected_scene_id(_scenes, nil), do: nil
  defp selected_scene_id(scenes, value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> case Enum.find(scenes, &(&1.ordinal == number)) do nil -> nil; scene -> scene.id end
      _ -> nil
    end
  end

  defp display_label(%{display_ref: "task-base"}), do: "Task base"
  defp display_label(%{display_ref: "current"}), do: "Current screenplay"
  defp display_label(%{display_ref: "proposal-" <> n}), do: "Proposal #{n}"
  defp display_label(%{display_ref: "accepted-" <> n}), do: "Accepted result #{n}"
  defp display_label(%{display_ref: "evidence-" <> n, label: label}), do: "Evidence #{n} · #{String.replace_prefix(label, "Analysis evidence · ", "")}"
  defp display_label(option), do: option.label || "Saved source"

  defp source_path(project_key, task_key, option) do
    "/p/#{project_key}/source/#{task_key}?" <> URI.encode_query(%{"view" => option.display_ref})
  end

  @impl true
  def render(assigns) do
    selected = assigns.workspace.selection
    assigns = assign(assigns, :selected, selected)

    ~H"""
    <main class="project-workspace reading-workspace task-source-workspace" phx-hook="SceneNavigator" data-project-key={@project_key}>
      <FountWeb.CoreComponents.project_header
        project={%{"key" => @project_key, "title" => @access["title"], "project_kind" => "screenplay"}}
        section="work"
        view="reading"
        source_label={display_label(@selected)}
      />

      <nav class="task-subnav" aria-label="Task source">
        <strong>{@access["display_label"] || "Saved task"}</strong>
        <a href={"/p/#{@project_key}/activity/#{@task_key}"}>Activity</a>
        <a href={"/p/#{@project_key}/changes/#{@task_key}"}>Review</a>
        <a href={"/p/#{@project_key}/analysis/#{@task_key}"}>Analysis</a>
        <a href={"/p/#{@project_key}/source/#{@task_key}"} aria-current="page">Sources</a>
      </nav>

      <FountWeb.CoreComponents.alert :if={@error} kind="warning" title="Source notice">{@error}</FountWeb.CoreComponents.alert>
      <FountWeb.CoreComponents.alert :if={@scope_error} kind="warning" title="Task scope">{@scope_error}</FountWeb.CoreComponents.alert>
      <p :if={@scope_notice} class="save-state" role="status">{@scope_notice}</p>

      <section class="script-context">
        <div><h1>{@access["title"]}</h1><p><strong>{display_label(@selected)}</strong> · exact saved task source</p></div>
        <div class="named-source-picker" aria-label="Task source">
          <span>Source</span>
          <a
            :for={option <- @workspace.options}
            href={source_path(@project_key, @task_key, option)}
            aria-current={if option.display_ref == @selected.display_ref, do: "page"}
          >{display_label(option)}</a>
        </div>
      </section>

      <FountWeb.CoreComponents.disclosure
        id="task-scope"
        title="Task scope"
        summary="Choose the exact screenplay material used by this saved task"
      >
        <p>Scope is saved against this task's base screenplay. Reading another saved source does not change it.</p>
        <form phx-submit="save_workflow_scope" class="scope-picker named-scope-picker">
          <label class="scope-whole">
            <input
              type="checkbox"
              name="scope[whole_screenplay]"
              value="true"
              checked={scope_whole?(@workflow_selection)}
            /> Whole screenplay
          </label>
          <details open>
            <summary>Scenes ({length(@base_screenplay.ir.scenes)})</summary>
            <div class="scope-target-grid">
              <label :for={{scene, ordinal} <- Enum.with_index(@base_screenplay.ir.scenes, 1)}>
                <input
                  type="checkbox"
                  name="scope[scene_ids][]"
                  value={scene.id}
                  checked={scope_target?(@workflow_selection, "scene", scene.id)}
                />
                <span>{scope_scene_label(@base_screenplay, scene, ordinal)}</span>
              </label>
            </div>
          </details>
          <details>
            <summary>Individual elements ({length(@base_screenplay.ir.elements)})</summary>
            <div class="scope-target-grid scope-elements">
              <label :for={{element, ordinal} <- Enum.with_index(@base_screenplay.ir.elements, 1)}>
                <input
                  type="checkbox"
                  name="scope[element_ids][]"
                  value={element.id}
                  checked={scope_target?(@workflow_selection, "element", element.id)}
                />
                <span>{scope_element_label(element, ordinal)}</span>
              </label>
            </div>
          </details>
          <button type="submit">Save task scope</button>
        </form>
        <div :if={@workflow_selection} class="scope-preview" aria-label="Saved task scope">
          <strong>Saved scope</strong>
          <ul>
            <li :for={target <- @workflow_selection["preview"] || []}>{target["label"]}</li>
          </ul>
        </div>
      </FountWeb.CoreComponents.disclosure>

      <div class="reader-layout">
        <aside class="reader-outline" aria-label="Scene outline">
          <div class="reader-outline__title"><strong>Scenes</strong><span>{length(@index.scenes)}</span></div>
          <ol id="scene-outline">
            <li :for={scene <- @index.scenes}>
              <a
                href={source_path(@project_key, @task_key, @selected) <> "&scene=#{scene.ordinal}"}
                data-scene-link={scene.id}
                data-scene-ref={scene.ordinal}
              ><span>{scene.number || scene.ordinal}</span><strong>{scene.heading || "Untitled scene"}</strong></a>
            </li>
          </ol>
        </aside>
        <section class="reader-paper" aria-label="Saved task screenplay source">
          <div class="reader-paper__label"><span>Responsive task source</span><a href="/help#sources">Source labels</a></div>
          <FountWeb.Components.ScreenplayRenderer.screenplay screenplay={@workspace.screenplay} selected_scene_id={@selected_scene_id} />
        </section>
      </div>

      <details class="technical-details">
        <summary>Technical details</summary>
        <dl>
          <div><dt>Run identity</dt><dd><code>{@run["id"]}</code></dd></div>
          <div><dt>Revision identity</dt><dd><code>{@workspace.screenplay.revision.id}</code></dd></div>
          <div><dt>Internal source token</dt><dd><code>{@selected.token}</code></dd></div>
        </dl>
      </details>
    </main>
    """
  end
end
