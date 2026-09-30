defmodule FountWeb.ProjectLive do
  use FountWeb, :live_view

  @max_upload 1_048_576

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:projects, [])
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

  defp uploaded_source(socket, params) do
    case consume_uploaded_entries(socket, :screenplay, fn %{path: path}, entry ->
           {:ok, {File.read!(path), entry.client_name}}
         end) do
      [{source, filename}] -> {source, filename}
      [] -> {Map.get(params, "source", ""), "project.fountain"}
    end
  end

  defp load_projects(socket) do
    case FountWeb.Store.list_projects(Fount.Repo, socket.assigns.current_owner) do
      projects when is_list(projects) -> assign(socket, :projects, projects)
      {:error, reason} -> assign(socket, :error, "Projects unavailable: #{inspect(reason)}")
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
        <header class="project-mast"><p class="eyebrow">Story workspace registry</p><h1>Fount projects</h1></header>
        <p>
          Authenticated owner: <strong><%= @current_owner %></strong>. Canon changes remain explicit Run decisions.
        </p>
        <p :if={@projects == []}>No projects yet.</p>
        <div class="project-grid">
          <article :for={project <- @projects} class="card project-card">
            <h2>{project["title"]}</h2>
            <p><code>{project["key"]}</code></p>
            <p>Screenplay <code>{project["screenplay_id"]}</code></p>
            <p>
              Starting here reloads the current accepted head; it does not create or accept generated pages.
            </p>
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
      </section>

      <section :if={@live_action == :new} class="project-create">
        <header class="project-mast"><p class="eyebrow">Genesis + durable Run</p><h1>New screenplay Run</h1></header>
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
            Upload Fountain/FDX (max 1 MiB)
            <input type="file" name="screenplay" accept=".fountain,.fdx" />
          </label>
          <label>
            Or Fountain source <textarea name="project[source]"><%= @fixture_source %></textarea>
          </label>
          <button type="submit" phx-disable-with="Creating Run…">Create Run</button>
        </form>
      </section>
    </main>
    """
  end
end
