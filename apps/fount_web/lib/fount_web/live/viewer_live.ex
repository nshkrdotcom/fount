defmodule FountWeb.ViewerLive do
  use FountWeb, :live_view

  alias FountWeb.ProjectContext

  @impl true
  def mount(%{"key" => project_key} = params, _session, socket) do
    owner = socket.assigns.current_owner
    source = ProjectContext.source_token(Map.get(params, "source", "current"))

    case ProjectContext.load(owner, project_key, source: source) do
      {:ok, context} ->
        _ = ProjectContext.remember(owner, project_key, "reading")
        prefs = FountWeb.Store.owner_preferences(Fount.Repo, owner)

        {:ok,
         socket
         |> assign(:context, context)
         |> assign(:project, context.project)
         |> assign(:selected_source, context.selected)
         |> assign(:sources, context.sources)
         |> assign(:index, context.index)
         |> assign(:facts, context.facts)
         |> assign(:selected_scene_id, selected_scene_id(context.index.scenes, params["scene"]))
         |> assign(:preferences, prefs)
         |> assign(:error, nil)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "That screenplay is not available in your workspace.")
         |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns[:project] do
      source = ProjectContext.source_token(Map.get(params, "source", socket.assigns.selected_source.token))

      case ProjectContext.load(socket.assigns.current_owner, socket.assigns.project["key"], source: source) do
        {:ok, context} ->
          {:noreply,
           socket
           |> assign(:context, context)
           |> assign(:selected_source, context.selected)
           |> assign(:sources, context.sources)
           |> assign(:index, context.index)
           |> assign(:facts, context.facts)
           |> assign(:selected_scene_id, selected_scene_id(context.index.scenes, params["scene"]))
           |> assign(:error, nil)}

        {:error, _} ->
          {:noreply, assign(socket, :error, "That saved source is no longer available. Showing the current screenplay.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
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

  defp selected_scene_id(_scenes, nil), do: nil

  defp selected_scene_id(scenes, ordinal) when is_binary(ordinal) do
    case Integer.parse(ordinal) do
      {number, ""} ->
        case Enum.find(scenes, &(&1.ordinal == number)) do
          nil -> nil
          scene -> scene.id
        end

      _ ->
        nil
    end
  end

  defp source_path(project, token) do
    if token == "current", do: "/p/#{project["key"]}", else: "/p/#{project["key"]}?source=#{token}"
  end

  defp dismissed?(prefs, slug) do
    slug in List.wrap(Map.get(prefs, "dismissed_hints", []))
  end

  defp import_label(project) do
    case project["import_format"] do
      "fountain" -> "Imported Fountain source"
      "fdx" -> "Imported Final Draft source"
      "blank" -> "Started blank"
      _ -> nil
    end
  end

  defp source_status(%{kind: :current}), do: "Accepted screenplay"
  defp source_status(%{kind: :working, valid?: true}), do: "Saved working draft · not current"
  defp source_status(%{kind: :working, valid?: false}), do: "Working draft has invalid Fountain · last valid preview shown"
  defp source_status(%{kind: :proposed}), do: "Saved proposed change · not current"

  @impl true
  def render(assigns) do
    hint_dismissed = dismissed?(assigns.preferences, "reading")
    assigns = assign(assigns, :reading_hint_dismissed, hint_dismissed)

    ~H"""
    <main
      id="project-script"
      class="project-workspace reading-workspace"
      phx-hook="SceneNavigator"
      data-project-key={@project["key"]}
    >
      <FountWeb.CoreComponents.project_header
        project={@project}
        section="script"
        view="reading"
        source_label={@selected_source.label}
        example={@project["project_kind"] == "example"}
      />

      <FountWeb.CoreComponents.alert :if={@error} kind="warning" title="Source changed">
        {@error}
      </FountWeb.CoreComponents.alert>

      <section class="script-context" aria-label="Screenplay source">
        <div>
          <h1>{@project["title"]}</h1>
          <p>
            <strong>{@selected_source.label}</strong> · {source_status(@selected_source)}
            <span :if={import_label(@project)}> · {import_label(@project)}</span>
          </p>
        </div>
        <div class="named-source-picker" aria-label="Choose screenplay source">
          <span>Source</span>
          <a
            :for={source <- @sources}
            href={source_path(@project, source.token)}
            aria-current={if source.token == @selected_source.token, do: "page"}
          >{source.label}</a>
        </div>
      </section>

      <FountWeb.CoreComponents.contextual_help
        slug="reading"
        title="Reading and writing are separate views of the same project"
        dismissed={@reading_hint_dismissed}
        project_key={@project["key"]}
      >
        <p>Use Writing to edit recovery text. Reading another source never changes what is current.</p>
      </FountWeb.CoreComponents.contextual_help>

      <FountWeb.CoreComponents.disclosure id="about-screenplay" title="About this screenplay" summary="Optional context and script facts">
        <div class="about-grid">
          <section>
            <h2>Supplied context</h2>
            <dl class="about-copy">
              <div><dt>Title</dt><dd>{@project["title"]}</dd></div>
              <div :if={@project["logline"]}><dt>Logline</dt><dd>{@project["logline"]}</dd></div>
              <div :if={@project["synopsis"]}><dt>Synopsis</dt><dd>{@project["synopsis"]}</dd></div>
              <div :if={@project["source_name"]}><dt>Source file</dt><dd>{@project["source_name"]}</dd></div>
            </dl>
            <p :if={!@project["logline"] and !@project["synopsis"]} class="muted">No logline or synopsis has been supplied. Pages remain the primary view.</p>
          </section>
          <details class="script-facts">
            <summary>Script facts</summary>
            <dl>
              <div><dt>Scenes</dt><dd>{@facts.scene_count}</dd></div>
              <div><dt>Confirmed cast cues</dt><dd>{@facts.confirmed_cast_count}</dd></div>
              <div><dt>Interior headings</dt><dd>{@facts.heading_contexts.interior}</dd></div>
              <div><dt>Exterior headings</dt><dd>{@facts.heading_contexts.exterior}</dd></div>
              <div><dt>Other headings</dt><dd>{@facts.heading_contexts.other}</dd></div>
              <div><dt>Unknown heading context</dt><dd>{@facts.heading_contexts.unknown}</dd></div>
              <div><dt>Unknown time of day</dt><dd>{@facts.time_of_day_unknown_count}</dd></div>
              <div>
                <dt>Dialogue word share</dt>
                <dd>
                  <%= if @facts.dialogue_word_share do %>
                    {@facts.dialogue_word_share}% ({@facts.dialogue_words} of {@facts.screenplay_element_words} screenplay-element words)
                  <% else %>
                    Not available for an empty screenplay
                  <% end %>
                </dd>
              </div>
            </dl>
            <details>
              <summary>Confirmed character cues</summary>
              <ul>
                <li :for={character <- @facts.confirmed_cast}>
                  <strong>{character.name}</strong> · {character.scene_count} speaking scenes · {character.cue_count} cues
                </li>
              </ul>
            </details>
            <p class="scope-note">Literal source facts only. No alias inference, coverage score, page/minute guarantee or production estimate.</p>
          </details>
        </div>
      </FountWeb.CoreComponents.disclosure>

      <div class="reader-layout">
        <aside class="reader-outline" aria-label="Scene outline">
          <div class="reader-outline__title">
            <strong>Scenes</strong><span>{@facts.scene_count}</span>
          </div>
          <ol id="scene-outline">
            <li :for={scene <- @index.scenes}>
              <a
                href={"?source=#{@selected_source.token}&scene=#{scene.ordinal}"}
                data-scene-link={scene.id}
                data-scene-ref={scene.ordinal}
                aria-current={if scene.id == @selected_scene_id, do: "location"}
              >
                <span>{scene.number || scene.ordinal}</span>
                <strong>{scene.heading || "Untitled scene"}</strong>
              </a>
            </li>
          </ol>
        </aside>

        <section class="reader-paper" aria-label="Responsive screenplay pages">
          <div class="reader-paper__label">
            <span>Responsive reading view</span>
            <a href="/help#reading">How page references work</a>
          </div>
          <FountWeb.Components.ScreenplayRenderer.screenplay
            screenplay={@selected_source.screenplay}
            selected_scene_id={@selected_scene_id}
          />
        </section>
      </div>

      <details class="technical-details">
        <summary>Technical details</summary>
        <dl>
          <div><dt>Project identity</dt><dd><code>{@project["id"]}</code></dd></div>
          <div><dt>Screenplay identity</dt><dd><code>{@selected_source.screenplay.id}</code></dd></div>
          <div><dt>Revision identity</dt><dd><code>{@selected_source.screenplay.revision.id}</code></dd></div>
        </dl>
      </details>
    </main>
    """
  end
end
