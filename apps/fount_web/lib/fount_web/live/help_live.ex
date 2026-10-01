defmodule FountWeb.HelpLive do
  use FountWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    project_key = Map.get(params, "project")
    project = load_project(socket.assigns.current_owner, project_key)

    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:topics, FountWeb.Help.all())
     |> assign(:project, project)
     |> assign(
       :preferences,
       FountWeb.Store.owner_preferences(Fount.Repo, socket.assigns.current_owner)
     )}
  end

  @impl true
  def handle_event("search", %{"help" => %{"query" => query}}, socket) do
    {:noreply, socket |> assign(:query, query) |> assign(:topics, FountWeb.Help.search(query))}
  end

  def handle_event("show_hints_again", _params, socket) do
    case FountWeb.Store.put_owner_preferences(Fount.Repo, socket.assigns.current_owner, %{
           "dismissed_hints" => []
         }) do
      {:ok, prefs} ->
        {:noreply,
         socket
         |> assign(:preferences, prefs)
         |> put_flash(:info, "Contextual hints will appear again where they apply.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Hint preferences could not be changed.")}
    end
  end

  defp load_project(_owner, nil), do: nil

  defp load_project(owner, key) do
    case FountWeb.Store.project_by_key(Fount.Repo, owner, key) do
      {:ok, project} -> project
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="help-shell">
      <header class="desk-header">
        <div>
          <a class="desk-wordmark" href="/">Fount</a>
          <span>Help</span>
        </div>
        <nav aria-label="Help navigation">
          <a :if={@project} href={"/p/#{@project["key"]}"}>Back to {@project["title"]}</a>
          <a :if={!@project} href="/">Back to projects</a>
        </nav>
      </header>

      <section class="help-intro">
        <p class="eyebrow">At the moment of work</p>
        <h1>Fount help</h1>
        <p>
          Short explanations of what an action changes, what it saves and when an external service is actually needed.
        </p>
        <form phx-change="search" class="help-search">
          <label for="help-query">Search help</label>
          <input
            id="help-query"
            name="help[query]"
            value={@query}
            type="search"
            placeholder="import, working draft, page references…"
          />
        </form>
        <button type="button" phx-click="show_hints_again">Show dismissed hints again</button>
      </section>

      <section class="help-topics" aria-label="Help topics">
        <article :for={topic <- @topics} id={topic.slug} class="help-topic">
          <h2>{topic.title}</h2>
          <p class="help-topic__summary">{topic.summary}</p>
          <p>{topic.body}</p>
          <a :if={@project && topic.slug == "reading"} href={"/p/#{@project["key"]}"}>Open Reading</a>
          <a :if={@project && topic.slug == "writing"} href={"/p/#{@project["key"]}/write"}>Open Writing</a>
          <a :if={@project && topic.slug == "work-on-it"} href={"/p/#{@project["key"]}/work"}>Open Work on it</a>
          <div
            :if={@project && @project["project_kind"] == "example" && topic.slug == "example"}
            class="example-checklist"
          >
            <h3>Optional example checklist</h3>
            <ol>
              <li :for={step <- FountWeb.ExampleProject.checklist()}>
                <strong>{step.title}</strong>
                <span>{step.detail}</span>
              </li>
            </ol>
            <a href={"/p/#{@project["key"]}?scene=1#passage-1"}>Continue example at Scene 1</a>
          </div>
        </article>
        <p :if={@topics == []} class="ui-state ui-state--empty">No help topics match that search.</p>
      </section>
    </main>
    """
  end
end
