defmodule FountWeb.ProjectLive do
  use FountWeb, :live_view

  @max_upload 1_048_576

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:projects, [])
      |> assign(:project_cards, [])
      |> assign(:project_filter, "")
      |> assign(:project_sort, "recent")
      |> assign(:runs, [])
      |> assign(:run_filter, "")
      |> assign(:comparison, nil)
      |> assign(:error, nil)
      |> assign(:fixture_source, FountWeb.Journeys.fixture_fountain())
      |> allow_upload(:screenplay,
        accept: ~w(.fountain .fdx),
        max_entries: 1,
        max_file_size: @max_upload
      )

    {:ok, load_projects(socket)}
  end

  @impl true
  def handle_event("create", %{"project" => params}, socket) do
    {source, filename} = uploaded_source(socket, params)
    attrs = Map.merge(params, %{"source" => source, "filename" => filename})

    case FountWeb.Launch.create(socket.assigns.current_owner, attrs) do
      {:ok, %{run: run}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project and durable Run created. Review setup before launch.")
         |> push_navigate(to: ~p"/runs/#{run["id"]}/setup")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("create_existing", %{"run" => params}, socket) do
    project_id = Map.get(params, "project_id", "")

    case FountWeb.Launch.create_from_project(socket.assigns.current_owner, project_id, params) do
      {:ok, %{run: run}} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Run created from the project's current accepted base. Review setup before launch."
         )
         |> push_navigate(to: ~p"/runs/#{run["id"]}/setup")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("filter_projects", %{"projects" => attrs}, socket) do
    query = Map.get(attrs, "query", "")
    sort = Map.get(attrs, "sort", "recent")
    sort = if sort in ~w(recent title scenes), do: sort, else: "recent"

    {:noreply,
     socket
     |> assign(:project_filter, query)
     |> assign(:project_sort, sort)
     |> load_projects()}
  end

  def handle_event("filter_runs", %{"runs" => %{"status" => status}}, socket) do
    allowed = [
      "",
      "queued",
      "running",
      "paused",
      "waiting_for_decision",
      "waiting_for_approval",
      "partial",
      "completed_candidate",
      "completed_accepted",
      "stopped",
      "failed"
    ]

    status = if status in allowed, do: status, else: ""

    {:noreply,
     socket |> assign(:run_filter, status) |> assign(:comparison, nil) |> load_projects()}
  end

  def handle_event("compare_runs", %{"compare" => %{"left" => left, "right" => right}}, socket) do
    case FountWeb.WorkflowManagement.compare_owner_runs(
           Fount.Repo,
           socket.assigns.current_owner,
           left,
           right
         ) do
      {:ok, comparison} ->
        {:noreply, socket |> assign(:comparison, comparison) |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Run comparison unavailable: #{inspect(reason)}")}
    end
  end

  defp uploaded_source(socket, params) do
    case consume_uploaded_entries(socket, :screenplay, fn %{path: path}, entry ->
           {:ok, {File.read!(path), entry.client_name}}
         end) do
      [{source, filename}] -> {source, filename}
      [] -> {Map.get(params, "source", ""), "project.fountain"}
    end
  end

  defp load_projects(socket) do
    case FountWeb.Store.list_projects(Fount.Repo, socket.assigns.current_owner, limit: 24) do
      projects when is_list(projects) ->
        all_runs =
          FountWeb.WorkflowManagement.list_owner_runs(
            Fount.Repo,
            socket.assigns.current_owner,
            limit: 50
          )

        runs =
          if socket.assigns.run_filter == "" do
            all_runs
          else
            Enum.filter(all_runs, &(&1["status"] == socket.assigns.run_filter))
          end

        cards =
          FountWeb.ProductionTools.project_cards(
            Fount.Repo,
            socket.assigns.current_owner,
            projects,
            all_runs
          )
          |> FountWeb.ProductionTools.filter_cards(
            socket.assigns.project_filter,
            socket.assigns.project_sort
          )

        assign(socket, projects: projects, project_cards: cards, runs: runs)

      {:error, reason} ->
        assign(socket, :error, "Projects unavailable: #{inspect(reason)}")
    end
  end

  defp human_error({tag, reason}), do: "#{tag}: #{inspect(reason)}"
  defp human_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <main class="project-shell">
      <nav class="context-nav project-nav" aria-label="Primary">
        <a href={~p"/"}>Projects</a>
        <a href={~p"/projects/new"}>New project</a>
        <form action={~p"/logout"} method="post">
          <input type="hidden" name="_method" value="delete" />
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button type="submit">Sign out</button>
        </form>
      </nav>

      <section :if={@live_action == :index} class="project-index">
        <header class="project-mast">
          <p class="eyebrow">Story workspace registry</p><h1>Fount projects</h1>
        </header>
        <p>
          Authenticated owner: <strong><%= @current_owner %></strong>. Canon changes remain explicit Run decisions.
        </p>
        <p class="muted">
          Showing at most the 24 most recent owner-visible projects; filter and sort operate inside that bounded set.
        </p>
        <form phx-change="filter_projects" class="project-filter inline-form">
          <label>Filter projects
          <input
            name="projects[query]"
            value={@project_filter}
            placeholder="title, key or supplied synopsis"
          /></label>
          <label>
            Sort
            <select name="projects[sort]">
              <option value="recent" selected={@project_sort == "recent"}>Recent</option>
              <option value="title" selected={@project_sort == "title"}>Title</option>
              <option value="scenes" selected={@project_sort == "scenes"}>Scene count</option>
            </select>
          </label>
        </form>
        <p :if={@projects == []}>No projects yet.</p>
        <p :if={@projects != [] and @project_cards == []}>No projects match this filter.</p>
        <div class="project-grid">
          <article :for={card <- @project_cards} class="card project-card">
            <% project = card.project %>
            <h2>{project["title"]}</h2>
            <p><code>{project["key"]}</code></p>
            <p :if={project["synopsis"]}>{project["synopsis"]}</p>
            <p :if={project["thumbnail_ref"]}>
              Thumbnail reference: <code>{project["thumbnail_ref"]}</code>
            </p>
            <p>
              Screenplay <code>{project["screenplay_id"]}</code>
              · accepted revision <code>{card.revision_id || "unavailable"}</code>
            </p>
            <dl class="project-facts">
              <div>
                <dt>Scenes</dt><dd>{card.scene_count || "—"}</dd>
              </div>
              <div>
                <dt>Cast</dt><dd>{card.cast_count || "—"}</dd>
              </div>
              <div>
                <dt>Notes</dt><dd>{card.note_count || "—"}</dd>
              </div>
            </dl>
            <p>{card.page_estimate || "Page estimate unavailable"}</p>
            <p>
              Import: {project["import_format"] || "legacy / unknown"} · losses {card.import_fidelity[
                "loss_count"
              ] || "unknown"} · source preserved unchanged {to_string(
                card.import_fidelity["original_bytes_preserved_when_unchanged"] || false
              )}
            </p>
            <p>
              Starting here reloads the current accepted head; it does not create or accept generated pages.
            </p>
            <div :if={card.latest_run} class="project-links">
              <a href={~p"/runs/#{card.latest_run["id"]}/viewer"}>Viewer</a>
              <a href={~p"/runs/#{card.latest_run["id"]}/analysis"}>Analysis</a>
              <a href={~p"/runs/#{card.latest_run["id"]}/tools"}>Search & production tools</a>
            </div>
            <details :if={card.recent_activity != []}>
              <summary>Recent persisted activity</summary>
              <ul>
                <li :for={item <- card.recent_activity}>
                  {item["kind"]}: {item["detail"]} · {item["resource_id"]}
                </li>
              </ul>
            </details>
            <form phx-submit="create_existing" class="stack">
              <input type="hidden" name="run[project_id]" value={project["id"]} />
              <input type="hidden" name="run[command_id]" value={Fount.ID.v4()} />
              <label>
                New Run journey
                <select name="run[journey]">
                  <option value="opening">Opening candidate</option>
                  <option value="reveal">Reveal change</option>
                  <option value="dialogue">Dialogue pass</option>
                  <option value="analysis">Observe-backed analysis candidate</option>
                </select>
              </label>
              <button type="submit">Use current accepted base</button>
            </form>
          </article>
        </div>

        <section class="card stack run-registry" aria-labelledby="run-registry-title">
          <div>
            <p class="eyebrow">Authorized bounded registry</p>
            <h2 id="run-registry-title">Runs</h2>
            <p>
              Up to 50 owner-authorized Runs are loaded. Filters are validated by the Run listing contract; comparisons are factual and never rank outcomes.
            </p>
          </div>
          <form phx-change="filter_runs" class="inline-form">
            <label>
              Status
              <select name="runs[status]">
                <option value="" selected={@run_filter == ""}>All statuses</option>
                <option
                  :for={
                    status <-
                      ~w(queued running paused waiting_for_decision waiting_for_approval partial completed_candidate completed_accepted stopped failed)
                  }
                  value={status}
                  selected={@run_filter == status}
                >
                  {String.replace(status, "_", " ")}
                </option>
              </select>
            </label>
          </form>
          <p :if={@runs == []}>No authorized Runs match this filter.</p>
          <div :if={@runs != []} class="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Project</th><th>Status</th><th>Stage</th><th>Plan/policy</th><th>Base</th><th>
                    Open
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={run <- @runs}>
                  <td>{run["project"]["title"]}</td>
                  <td>{run["status"]}</td>
                  <td>{run["stage"] || "—"}</td>
                  <td>v{run["current_plan_version"]} / v{run["current_policy_version"]}</td>
                  <td><code>{run["plan"]["base_revision_id"]}</code></td>
                  <td><a href={~p"/runs/#{run["id"]}/setup"}>Open</a></td>
                </tr>
              </tbody>
            </table>
          </div>
          <form :if={length(@runs) >= 2} phx-submit="compare_runs" class="compare-form">
            <label>
              Left Run
              <select name="compare[left]">
                <option :for={run <- @runs} value={run["id"]}>
                  {run["project"]["title"]} · {run["status"]} · {String.slice(run["id"], 0, 8)}
                </option>
              </select>
            </label>
            <label>
              Right Run
              <select name="compare[right]">
                <option :for={run <- Enum.reverse(@runs)} value={run["id"]}>
                  {run["project"]["title"]} · {run["status"]} · {String.slice(run["id"], 0, 8)}
                </option>
              </select>
            </label>
            <button type="submit">Compare persisted facts</button>
          </form>
          <div :if={@comparison} class="comparison-card">
            <p>
              Same screenplay: {to_string(@comparison["same_screenplay"])} · same base: {to_string(
                @comparison["same_base"]
              )} · same scope: {to_string(@comparison["same_scope"])}
            </p>
            <table>
              <thead>
                <tr>
                  <th>Field</th><th>Left</th><th>Right</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={fact <- @comparison["facts"]}>
                  <td>{fact["field"]}</td><td>{to_string(fact["left"] || "—")}</td><td>
                    {to_string(fact["right"] || "—")}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </section>

      <section :if={@live_action == :new} class="project-create">
        <header class="project-mast">
          <p class="eyebrow">Genesis + durable Run</p><h1>New screenplay Run</h1>
        </header>
        <p>
          The supplied screenplay becomes the explicit genesis revision. Generated pages are candidates until the configured exact approval path accepts them.
        </p>
        <p class="warning">
          Deterministic demo mode uses no secret credential. It exercises persistence, Run decisions, Workshop edits, Observe-backed Intelligence, checks and delivery; it does not certify screenplay quality.
        </p>
        <p :if={@error} role="alert">{@error}</p>
        <p :if={@flash["error"]} role="alert">{@flash["error"]}</p>

        <form
          id="create-project"
          phx-update="ignore"
          action={~p"/projects"}
          method="post"
          enctype="multipart/form-data"
          class="stack"
        >
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <label>Project title <input name="project[title]" value="Phase 06 Demo" required /></label>
          <label>Project key
          <input
            name="project[key]"
            value={"phase06-" <> Integer.to_string(System.unique_integer([:positive]))}
            pattern="[a-z0-9][a-z0-9_\-]{1,63}"
            required
          /></label>
          <label>
            Journey
            <select name="project[journey]">
              <option value="opening">
                Brief → checked opening candidate → export (canon unchanged)
              </option>
              <option value="reveal">
                Reveal move → protected beat repair → human exact approval
              </option>
              <option value="dialogue">Selected-scene dialogue → configured service approval</option>
              <option value="analysis">
                Selected-scene dialogue → Observe-backed candidate (canon unchanged)
              </option>
            </select>
          </label>
          <label>
            Supplied synopsis (optional; never generated from the script) <textarea
              name="project[synopsis]"
              maxlength="4000"
            ></textarea>
          </label>
          <label>
            Supplied thumbnail reference (optional; stored as text, never fetched)
            <input name="project[thumbnail_ref]" maxlength="2048" />
          </label>
          <label>
            Upload Fountain/FDX (max 1 MiB)
            <input type="file" name="screenplay" accept=".fountain,.fdx" />
          </label>
          <label>
            Or Fountain source <textarea name="project[source]"><%= @fixture_source %></textarea>
          </label>
          <p role="status">
            Import is synchronous. The next page appears only after parsing, genesis persistence and durable Run creation succeed.
          </p>
          <button type="submit" phx-disable-with="Importing + creating Run…">Create Run</button>
        </form>
      </section>
    </main>
    """
  end
end
