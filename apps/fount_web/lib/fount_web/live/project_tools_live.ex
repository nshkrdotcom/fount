defmodule FountWeb.ProjectToolsLive do
  use FountWeb, :live_view

  alias FountWeb.{AuthoringStore, ProjectContext, Store}

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    owner = socket.assigns.current_owner

    with {:ok, context} <- ProjectContext.load(owner, key) do
      {:ok,
       socket
       |> assign(:project, context.project)
       |> assign(:context, context)
       |> assign(:runs, runs(owner, context.project["id"]))
       |> assign(:drafts, drafts(owner, context.project["id"]))
       |> assign(:error, nil)
       |> assign(:notice, nil)}
    else
      _ -> {:ok, socket |> put_flash(:error, "That screenplay is not available.") |> redirect(to: "/")}
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
         |> put_flash(:info, "Task created from the current screenplay. Review its existing controls before launch.")
         |> push_navigate(
           to: "/p/#{socket.assigns.project["key"]}/activity/#{result.access["display_key"]}/setup"
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :error, task_error(reason))}
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

  defp validate_project_title(""), do: {:error, "Project title cannot be blank."}
  defp validate_project_title(title) when byte_size(title) > 160, do: {:error, "Keep the project title under 160 bytes."}
  defp validate_project_title(_title), do: :ok

  defp optional_text(value, max_bytes, label) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> {:ok, nil}
      byte_size(value) > max_bytes -> {:error, "#{label} is too long. Keep it under #{max_bytes} bytes."}
      true -> {:ok, value}
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

  defp task_label(run), do: run["display_label"] || "Saved task"
  defp task_key(run), do: run["display_key"]

  defp task_error(:project_screenplay_mismatch), do: "The project source changed and this task could not be created."
  defp task_error(_), do: "The task could not be created. Manual reading and writing remain available."

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

      <FountWeb.CoreComponents.alert :if={@error} kind="warning" title="Project notice">{@error}</FountWeb.CoreComponents.alert>
      <FountWeb.CoreComponents.alert :if={@notice} kind="info" title="Saved">{@notice}</FountWeb.CoreComponents.alert>

      <section :if={@live_action == :work} class="tool-page">
        <header><p class="eyebrow">Creative work</p><h1>Work on it</h1></header>
        <p>Reading and writing do not need a task. Start one only when you want the existing creative workflow to work on the current screenplay.</p>
        <form phx-submit="start_task" class="compact-form task-start-form">
          <label for="task-journey">Existing task</label>
          <select id="task-journey" name="task[journey]">
            <option value="opening">Opening candidate</option>
            <option value="reveal">Reveal change</option>
            <option value="dialogue">Dialogue pass</option>
            <option value="analysis">Analysis-backed candidate</option>
          </select>
          <button type="submit">Create task</button>
        </form>
        <p class="scope-note">These are the existing advanced task controls. No task is created until you press Create task, and manual reading/writing remains available without one.</p>
        <.task_list runs={@runs} project={@project} />
      </section>

      <section :if={@live_action == :changes} class="tool-page">
        <header><p class="eyebrow">Saved work</p><h1>Changes</h1></header>
        <p>Proposed writing is reviewable work, not the current screenplay. Open a task to inspect its actual saved result.</p>
        <.task_list runs={@runs} project={@project} mode="changes" />
      </section>

      <section :if={@live_action == :notes} class="tool-page">
        <header><p class="eyebrow">Source-bound annotations</p><h1>Notes</h1></header>
        <p>Existing notes remain attached to the task that owns them. Open that task to review them; note-to-writing shortcuts are not available yet.</p>
        <.task_list runs={@runs} project={@project} mode="notes" />
      </section>

      <section :if={@live_action == :analysis} class="tool-page">
        <header><p class="eyebrow">Evidence</p><h1>Analysis</h1></header>
        <p>Open saved analysis for a real task. Fount does not run analysis merely to populate this screen.</p>
        <.task_list runs={@runs} project={@project} mode="analysis" />
      </section>

      <section :if={@live_action == :cast} class="tool-page">
        <header><p class="eyebrow">Source facts</p><h1>Cast &amp; locations</h1></header>
        <div class="fact-columns">
          <section>
            <h2>Confirmed character cues</h2>
            <ul><li :for={c <- @context.facts.confirmed_cast}><strong>{c.name}</strong> · {c.scene_count} speaking scenes</li></ul>
          </section>
          <section>
            <h2>Scene-heading locations</h2>
            <ul><li :for={location <- @context.index.locations}><strong>{location.location}</strong> · {location.scene_count} scenes</li></ul>
          </section>
        </div>
        <p class="scope-note">These are literal source projections, not casting recommendations or shooting-location plans.</p>
        <.task_list runs={@runs} project={@project} mode="tools" />
      </section>

      <section :if={@live_action == :read} class="tool-page">
        <header><p class="eyebrow">Performance tools</p><h1>Table read</h1></header>
        <p>The existing table-read controls remain available through the task that owns them. Microphone capture and automatic performance scoring are not part of this program.</p>
        <.task_list runs={@runs} project={@project} mode="tools" />
      </section>

      <section :if={@live_action == :history} class="tool-page">
        <header><p class="eyebrow">Recovery</p><h1>History</h1></header>
        <p>Working-draft history is recovery material and does not replace the current screenplay.</p>
        <ol class="history-list">
          <li :for={draft <- @drafts}>
            <strong>{if draft["status"] == "active", do: "Working draft", else: "Discarded draft"}</strong>
            <span> · version {draft["version"]} · {human_status(draft["status"])}</span>
          </li>
        </ol>
        <p :if={@drafts == []}>No working-draft recovery history yet.</p>
      </section>

      <section :if={@live_action == :exports} class="tool-page">
        <header><p class="eyebrow">Deliverables</p><h1>Exports</h1></header>
        <p>Task-bound delivery artifacts remain available below. Exact fixed-layout screenplay reading is not available yet; these are the existing task delivery artifacts.</p>
        <.task_list runs={@runs} project={@project} mode="exports" />
      </section>

      <section :if={@live_action == :activity} class="tool-page">
        <header><p class="eyebrow">Durable tasks</p><h1>Activity</h1></header>
        <.task_list runs={@runs} project={@project} mode="activity" />
      </section>

      <section :if={@live_action == :settings} class="tool-page settings-page">
        <header><p class="eyebrow">Project</p><h1>Project settings</h1></header>
        <form phx-submit="save_project" class="stack">
          <label>Title <input name="project[title]" value={@project["title"]} maxlength="160" required /></label>
          <label>Logline <textarea name="project[logline]" maxlength="1000">{@project["logline"]}</textarea></label>
          <label>Synopsis <textarea name="project[synopsis]" maxlength="4000">{@project["synopsis"]}</textarea></label>
          <button type="submit">Save project details</button>
        </form>
        <details class="technical-details">
          <summary>Technical details</summary>
          <dl>
            <div><dt>Project identity</dt><dd><code>{@project["id"]}</code></dd></div>
            <div><dt>Screenplay identity</dt><dd><code>{@project["screenplay_id"]}</code></dd></div>
            <div><dt>Internal project key</dt><dd><code>{@project["key"]}</code></dd></div>
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
      <p :if={@runs == []}>No saved tasks yet. The screenplay is still fully available for reading and writing.</p>
      <article :for={run <- @runs} class="task-row">
        <div><strong>{task_label(run)}</strong><span>{human_status(run["status"])}</span></div>
        <nav aria-label={"#{task_label(run)} actions"}>
          <a :if={@mode in ["activity", "changes"]} href={"/p/#{@project["key"]}/activity/#{task_key(run)}"}>Activity</a>
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
