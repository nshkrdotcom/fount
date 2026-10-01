defmodule FountWeb.ProjectLive do
  use FountWeb, :live_view

  @max_upload 1_048_576

  @impl true
  def mount(_params, _session, socket) do
    prefs = FountWeb.Store.owner_preferences(Fount.Repo, socket.assigns.current_owner)

    socket =
      socket
      |> assign(:projects, [])
      |> assign(:project_cards, [])
      |> assign(:pending_import, nil)
      |> assign(:preferences, prefs)
      |> assign(:error, nil)
      |> allow_upload(:screenplay,
        accept: ~w(.fountain .fdx),
        max_entries: 1,
        max_file_size: @max_upload
      )

    {:ok, load_projects(socket)}
  end

  @impl true
  def handle_event("preview_import", _params, socket) do
    case consume_uploaded_entries(socket, :screenplay, fn %{path: path}, entry ->
           {:ok, {File.read!(path), entry.client_name}}
         end) do
      [{source, filename}] ->
        case FountWeb.Launch.preview_import(source, filename) do
          {:ok, screenplay, import} ->
            pending = %{
              source: source,
              filename: filename,
              screenplay: screenplay,
              import: import,
              suggested_title: suggested_title(screenplay, filename)
            }

            {:noreply, socket |> assign(:pending_import, pending) |> assign(:error, nil)}

          {:error, reason} ->
            {:noreply, assign(socket, :error, human_error(reason))}
        end

      [] ->
        {:noreply, assign(socket, :error, upload_error(socket))}
    end
  end

  def handle_event("open_import", %{"project" => params}, socket) do
    case socket.assigns.pending_import do
      nil ->
        {:noreply, assign(socket, :error, "Choose and preview a screenplay first.")}

      pending ->
        supplied_title = params |> Map.get("title", "") |> String.trim()
        title = if supplied_title == "", do: pending.suggested_title, else: supplied_title

        attrs = %{
          "kind" => "import",
          "title" => title,
          "filename" => pending.filename,
          "source" => pending.source
        }

        create_and_open(socket, attrs, :reading, "Screenplay imported. No task or provider was started.")
    end
  end

  def handle_event("start_blank", _params, socket) do
    attrs = %{
      "kind" => "blank",
      "title" => "Untitled screenplay"
    }

    create_and_open(socket, attrs, :writing, "Blank screenplay ready. Your working draft is separate from the current screenplay.")
  end

  def handle_event("try_example", _params, socket) do
    case FountWeb.ExampleProject.create(socket.assigns.current_owner) do
      {:ok, %{project: project}} ->
        remember(socket, project["key"], "reading")

        {:noreply,
         socket
         |> put_flash(:info, "LAST RETURN is a provider-free example. No model credential was used.")
         |> push_navigate(to: "/p/#{project["key"]}")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  def handle_event("dismiss_hint", %{"slug" => slug}, socket) do
    dismissed = dismissed_hints(socket.assigns.preferences) |> MapSet.put(slug) |> MapSet.to_list()

    case FountWeb.Store.put_owner_preferences(Fount.Repo, socket.assigns.current_owner, %{
           "dismissed_hints" => dismissed
         }) do
      {:ok, prefs} -> {:noreply, assign(socket, :preferences, prefs)}
      _ -> {:noreply, socket}
    end
  end

  defp create_and_open(socket, attrs, destination, flash) do
    case FountWeb.Launch.create_project(socket.assigns.current_owner, attrs) do
      {:ok, %{project: project}} ->
        view = if destination == :writing, do: "writing", else: "reading"
        remember(socket, project["key"], view)

        path = if destination == :writing, do: "/p/#{project["key"]}/write", else: "/p/#{project["key"]}"

        {:noreply, socket |> put_flash(:info, flash) |> push_navigate(to: path)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, human_error(reason))}
    end
  end

  defp load_projects(socket) do
    case FountWeb.Store.list_projects(Fount.Repo, socket.assigns.current_owner, limit: 24) do
      projects when is_list(projects) ->
        cards = Enum.map(projects, &FountWeb.ProjectContext.card(socket.assigns.current_owner, &1))
        assign(socket, projects: projects, project_cards: cards)

      _ ->
        assign(socket, :error, "Your projects could not be loaded.")
    end
  end

  defp remember(socket, project_key, view) do
    FountWeb.ProjectContext.remember(socket.assigns.current_owner, project_key, view)
  end

  defp suggested_title(screenplay, filename) do
    from_page =
      case screenplay do
        %{ir: %{title_page: %{entries: entries}}} when is_list(entries) ->
          entries
          |> Enum.find(fn entry -> String.downcase(to_string(entry.key)) == "title" end)
          |> case do
            nil -> nil
            entry -> entry.values |> List.wrap() |> List.first()
          end

        _ ->
          nil
      end

    cond do
      is_binary(from_page) and String.trim(from_page) != "" -> String.trim(from_page)
      true ->
        filename
        |> Path.basename()
        |> Path.rootname()
        |> String.replace(~r/[_-]+/u, " ")
        |> String.trim()
        |> case do
          "" -> "Untitled screenplay"
          value -> value
        end
    end
  end

  defp upload_error(socket) do
    errors =
      socket.assigns.uploads.screenplay.entries
      |> Enum.flat_map(&upload_errors(socket.assigns.uploads.screenplay, &1))

    case errors do
      [:too_large | _] -> "That file is over the 1 MiB import limit."
      [:not_accepted | _] -> "Choose a .fountain or .fdx screenplay."
      [_ | _] -> "The screenplay upload could not be read."
      [] -> "Choose a .fountain or .fdx screenplay first."
    end
  end

  defp dismissed_hints(prefs) do
    prefs
    |> Map.get("dismissed_hints", [])
    |> List.wrap()
    |> MapSet.new()
  end

  defp hint_dismissed?(prefs, slug), do: MapSet.member?(dismissed_hints(prefs), slug)

  defp resume_path(prefs) do
    case {Map.get(prefs, "last_project_key"), Map.get(prefs, "last_view")} do
      {key, "writing"} when is_binary(key) -> "/p/#{key}/write"
      {key, _} when is_binary(key) -> "/p/#{key}"
      _ -> nil
    end
  end

  defp import_note(loss) when is_binary(loss), do: loss
  defp import_note(_), do: "The importer reported a fidelity limitation. See Technical details after import if you need the underlying record."

  defp human_error(:title_required), do: "Give the screenplay a title before opening it."
  defp human_error(:title_too_long), do: "Keep the screenplay title under 160 bytes."
  defp human_error(:source_required), do: "The screenplay file is empty."
  defp human_error(:source_too_large), do: "That file is over the 1 MiB import limit."
  defp human_error(:unsupported_screenplay_format), do: "Choose a Fountain (.fountain) or Final Draft (.fdx) file."
  defp human_error({:invalid_fdx, _}), do: "This Final Draft file could not be parsed. The project was not created."
  defp human_error(:key_taken), do: "That project name collided with an existing screenplay key. Try the action again."
  defp human_error(_), do: "Fount could not create that project. Your source file was not changed."

  @impl true
  def render(assigns) do
    resume = resume_path(assigns.preferences)
    hint_dismissed = hint_dismissed?(assigns.preferences, "first-project")

    assigns =
      assigns
      |> assign(:resume_path, resume)
      |> assign(:first_hint_dismissed, hint_dismissed)

    ~H"""
    <main class="arrival-shell">
      <header class="desk-header">
        <div>
          <a class="desk-wordmark" href="/">Fount</a>
          <span>screenplay desk</span>
        </div>
        <nav aria-label="Desk">
          <a href="/help">Help</a>
          <form action="/logout" method="post">
            <input type="hidden" name="_method" value="delete" />
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <button type="submit">Sign out</button>
          </form>
        </nav>
      </header>

      <FountWeb.CoreComponents.alert :if={@error} kind="warning" title="Could not open screenplay">
        {@error}
      </FountWeb.CoreComponents.alert>

      <section class="arrival-primary" aria-labelledby="arrival-title">
        <div class="arrival-copy">
          <p class="eyebrow">Screenplay workspace</p>
          <h1 id="arrival-title">{if @projects == [], do: "Bring your pages.", else: "What are you working on?"}</h1>
          <p>Import a screenplay, start with a blank page, or read a short example. None of these actions starts AI work.</p>
          <a :if={@resume_path} class="resume-link" href={@resume_path}>Continue where I left off</a>
        </div>

        <div class="arrival-actions">
          <section class="arrival-action" aria-labelledby="import-title">
            <h2 id="import-title">Import screenplay</h2>
            <p>Fountain or Final Draft .fdx, up to 1 MiB.</p>
            <form phx-submit="preview_import" phx-drop-target={@uploads.screenplay.ref} class="import-dropzone">
              <.live_file_input upload={@uploads.screenplay} />
              <button type="submit">Preview import</button>
            </form>
          </section>

          <section class="arrival-action" aria-labelledby="blank-title">
            <h2 id="blank-title">Start blank</h2>
            <form phx-submit="start_blank" class="compact-form">
              <p class="muted">Opens a genuinely empty Fountain source immediately. Name the project later in Project settings.</p>
              <button type="submit">Start writing</button>
            </form>
          </section>

          <section class="arrival-example" aria-labelledby="example-title">
            <h2 id="example-title">Try an example</h2>
            <p><strong>LAST RETURN</strong> is a short provider-free screenplay created through the same project persistence path.</p>
            <button type="button" phx-click="try_example">Open LAST RETURN</button>
          </section>
        </div>
      </section>

      <section :if={@pending_import} class="import-preview" aria-labelledby="import-preview-title">
        <div>
          <p class="eyebrow">Import preview</p>
          <h2 id="import-preview-title">{@pending_import.filename}</h2>
          <dl class="inline-facts">
            <div><dt>Detected format</dt><dd>{String.upcase(@pending_import.import["format"])}</dd></div>
            <div><dt>Import issues</dt><dd>{@pending_import.import["loss_count"] || 0}</dd></div>
            <div><dt>Source size</dt><dd>{@pending_import.import["source_bytes"]} bytes</dd></div>
          </dl>
          <p :if={@pending_import.import["loss_count"] == 0}>No adapter losses were reported by the screenplay importer.</p>
          <details :if={@pending_import.import["loss_count"] > 0}>
            <summary>Import notes</summary>
            <ul><li :for={loss <- @pending_import.import["adapter_losses"]}>{import_note(loss)}</li></ul>
          </details>
        </div>
        <form phx-submit="open_import" class="compact-form">
          <label for="import-project-title">Project title <span class="muted">optional</span></label>
          <input id="import-project-title" name="project[title]" value={@pending_import.suggested_title} maxlength="160" />
          <button type="submit">Open screenplay</button>
        </form>
      </section>

      <FountWeb.CoreComponents.contextual_help
        slug="first-project"
        title="Pages first"
        dismissed={@first_hint_dismissed}
      >
        <p>Reading and writing work without a task or model. Creative tasks start only when you ask Fount to work on the pages.</p>
      </FountWeb.CoreComponents.contextual_help>

      <section :if={@project_cards != []} class="recent-projects" aria-labelledby="recent-projects-title">
        <div class="section-heading">
          <div><p class="eyebrow">Your desk</p><h2 id="recent-projects-title">Recent screenplays</h2></div>
          <span>{length(@project_cards)} shown</span>
        </div>
        <div class="project-list">
          <article :for={card <- @project_cards} class="project-row">
            <div>
              <h3><a href={"/p/#{card.project["key"]}"}>{card.project["title"]}</a></h3>
              <p>
                {card.source_label}
                <span :if={card.project["project_kind"] == "example"}> · Example</span>
                <span :if={card.project["source_name"]}> · {card.project["source_name"]}</span>
              </p>
            </div>
            <dl>
              <div><dt>Scenes</dt><dd>{card.scene_count || "—"}</dd></div>
              <div><dt>Confirmed cast</dt><dd>{card.cast_count || "—"}</dd></div>
            </dl>
            <div class="project-row__actions">
              <a href={"/p/#{card.project["key"]}"}>Read</a>
              <a href={"/p/#{card.project["key"]}/write"}>Write</a>
            </div>
          </article>
        </div>
      </section>
    </main>
    """
  end
end
