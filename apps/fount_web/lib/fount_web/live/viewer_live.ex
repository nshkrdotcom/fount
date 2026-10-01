defmodule FountWeb.ViewerLive do
  use FountWeb, :live_view

  alias FountWeb.{ProductionStore, ProductionTools, ProjectContext, ReadingArtifacts}

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
         |> assign(:search_result, nil)
         |> assign(:search_facets, search_facets(context.selected.screenplay))
         |> assign(:current_pdf, current_pdf(owner, context))
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
      source =
        ProjectContext.source_token(
          Map.get(params, "source", socket.assigns.selected_source.token)
        )

      case ProjectContext.load(socket.assigns.current_owner, socket.assigns.project["key"],
             source: source
           ) do
        {:ok, context} ->
          {:noreply,
           socket
           |> assign(:context, context)
           |> assign(:selected_source, context.selected)
           |> assign(:sources, context.sources)
           |> assign(:index, context.index)
           |> assign(:facts, context.facts)
           |> assign(:selected_scene_id, selected_scene_id(context.index.scenes, params["scene"]))
           |> assign(:search_result, nil)
           |> assign(:search_facets, search_facets(context.selected.screenplay))
           |> assign(:current_pdf, current_pdf(socket.assigns.current_owner, context))
           |> assign(:error, nil)}

        {:error, _} ->
          current_source = ProjectContext.source_token("current")

          case ProjectContext.load(
                 socket.assigns.current_owner,
                 socket.assigns.project["key"],
                 source: current_source
               ) do
            {:ok, context} ->
              {:noreply,
               socket
               |> assign(:context, context)
               |> assign(:selected_source, context.selected)
               |> assign(:sources, context.sources)
               |> assign(:index, context.index)
               |> assign(:facts, context.facts)
               |> assign(:selected_scene_id, selected_scene_id(context.index.scenes, params["scene"]))
               |> assign(:search_result, nil)
               |> assign(:search_facets, search_facets(context.selected.screenplay))
               |> assign(:current_pdf, current_pdf(socket.assigns.current_owner, context))
               |> assign(
                 :error,
                 "That saved source is no longer available. Showing the current screenplay."
               )}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, "That screenplay is not available in your workspace.")
               |> redirect(to: "/")}
          end
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("search_script", %{"search" => params}, socket) do
    query = Map.get(params, "query", "")

    case ProductionTools.search(socket.assigns.selected_source.screenplay, query, params) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:search_result, result)
         |> assign(:error, nil)}

      {:error, :empty_query} ->
        {:noreply, assign(socket, :search_result, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, search_error(reason))}
    end
  end

  def handle_event("clear_script_search", _params, socket),
    do: {:noreply, assign(socket, :search_result, nil)}

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

  defp current_pdf(owner, context) do
    project_id = context.project["id"]
    revision_id = context.current.revision.id

    with {:ok, artifact} <-
           ProductionStore.latest_ready_project_artifact(
             Fount.Repo,
             owner,
             project_id,
             revision_id,
             "pdf"
           ),
         rows when is_list(rows) <-
           ProductionStore.project_artifacts(Fount.Repo, owner, project_id, limit: 100),
         ref when is_binary(ref) <- ReadingArtifacts.artifact_ref(rows, artifact) do
      %{artifact: artifact, ref: ref}
    else
      _ -> nil
    end
  end

  defp search_facets(screenplay) do
    %{
      scenes: FountWeb.ScreenplayIndex.scene_index(screenplay),
      characters: ProductionTools.character_profiles(screenplay),
      locations: ProductionTools.location_profiles(screenplay),
      types: ProductionTools.search_types()
    }
  end

  defp search_error(:unknown_scene), do: "That scene is no longer in the selected source. Search was cleared."
  defp search_error(:unknown_character), do: "That character is no longer in the selected source. Search was cleared."
  defp search_error(:unknown_location), do: "That location is no longer in the selected source. Search was cleared."
  defp search_error(:invalid_element_types), do: "Choose a supported screenplay element type."
  defp search_error(:invalid_limit), do: "Search result limit must be between 1 and 200."
  defp search_error(reason), do: "Literal screenplay search failed: #{inspect(reason)}"

  defp result_path(project, source, hit) do
    scene = if hit.scene_ordinal, do: "&scene=#{hit.scene_ordinal}", else: ""
    "/p/#{project["key"]}?source=#{source.token}#{scene}#node-#{hit.element_id}"
  end

  defp compare_status(%{kind: :working, valid?: true}), do: "saved working draft · not current"
  defp compare_status(%{kind: :working, valid?: false}), do: "last valid preview of an invalid working draft · not current"
  defp compare_status(%{kind: :proposed}), do: "saved proposal · not current"
  defp compare_status(_), do: "selected source"

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
    if token == "current",
      do: "/p/#{project["key"]}",
      else: "/p/#{project["key"]}?source=#{token}"
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

  defp source_status(%{kind: :working, valid?: false}),
    do: "Working draft has invalid Fountain · last valid preview shown"

  defp source_status(%{kind: :proposed}), do: "Saved proposed change · not current"

  @impl true
  def render(assigns) do
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

      <p :if={@project["synopsis"]} class="reading-synopsis">{@project["synopsis"]}</p>
      <nav class="reading-primary-actions" aria-label="Reading actions">
        <a href={"/p/#{@project["key"]}/notes"}>Notes</a>
        <a :if={@selected_source.kind != :current} href="#source-comparison">Compare</a>
        <a href={"/p/#{@project["key"]}/exports"}>Export</a>
        <a href={"/help?project=#{URI.encode_www_form(@project["key"])}#reading"}>Help</a>
      </nav>

      <FountWeb.Components.SourceComparison.comparison
        :if={@selected_source.kind != :current}
        current={@context.current}
        other={@selected_source.screenplay}
        other_label={@selected_source.label}
        other_status={compare_status(@selected_source)}
      />

      <FountWeb.CoreComponents.disclosure
        id="script-search"
        title="Search this screenplay"
        summary="Exact literal search with source-bound filters"
      >
        <form phx-submit="search_script" class="compact-form script-search-form">
          <label>Literal text <input name="search[query]" maxlength="500" required /></label>
          <div class="compact-form-grid">
            <label>Scene
              <select name="search[scene_id]"><option value="">All scenes</option><option :for={scene <- @search_facets.scenes} value={scene.id}>Scene {scene.ordinal} · {scene.heading || "Untitled"}</option></select>
            </label>
            <label>Character
              <select name="search[character_id]"><option value="">All characters</option><option :for={character <- @search_facets.characters} value={character.id}>{character.display_name}</option></select>
            </label>
            <label>Location
              <select name="search[location]"><option value="">All locations</option><option :for={location <- @search_facets.locations} value={location.location}>{location.location}</option></select>
            </label>
            <label>Element type
              <select name="search[element_type]"><option value="">All types</option><option :for={type <- @search_facets.types} value={type}>{String.replace(type, "_", " ")}</option></select>
            </label>
            <label>Maximum results <input type="number" name="search[limit]" min="1" max="200" value="50" /></label>
          </div>
          <div class="inline-checks">
            <label><input type="checkbox" name="search[include_omitted]" value="true" /> Include omitted scenes</label>
            <label><input type="checkbox" name="search[include_notes]" value="true" /> Include source notes</label>
            <label><input type="checkbox" name="search[include_boneyards]" value="true" /> Include boneyards</label>
          </div>
          <div class="inline-actions"><button type="submit">Search selected source</button><button type="button" phx-click="clear_script_search">Clear</button></div>
          <p class="scope-note">Case-insensitive literal phrase search only. No provider dispatch, semantic index or cross-project search.</p>
        </form>
        <section :if={@search_result} class="script-search-results">
          <h3>{@search_result.returned_hit_count} result(s)<span :if={@search_result.truncated?}> · truncated at the selected limit</span></h3>
          <p>Inspected {@search_result.inspected_element_count} eligible source elements in {@selected_source.label}.</p>
          <ol>
            <li :for={hit <- @search_result.hits}>
              <a href={result_path(@project, @selected_source, hit)}>
                <strong>{if hit.scene_ordinal, do: "Scene #{hit.scene_ordinal} · #{hit.scene_heading || "Untitled"}", else: "Source passage"}</strong>
                <span>{String.replace(to_string(hit.type), "_", " ")} · {hit.excerpt}</span>
              </a>
            </li>
          </ol>
        </section>
      </FountWeb.CoreComponents.disclosure>

      <FountWeb.CoreComponents.disclosure
        id="about-screenplay"
        title="About this screenplay"
        summary="Optional context and script facts"
      >
        <div class="about-grid">
          <section>
            <h2>Supplied context</h2>
            <dl class="about-copy">
              <div>
                <dt>Title</dt><dd>{@project["title"]}</dd>
              </div>
              <div :if={@project["logline"]}>
                <dt>Logline</dt><dd>{@project["logline"]}</dd>
              </div>
              <div :if={@project["synopsis"]}>
                <dt>Synopsis</dt><dd>{@project["synopsis"]}</dd>
              </div>
              <div :if={@project["source_name"]}>
                <dt>Source file</dt><dd>{@project["source_name"]}</dd>
              </div>
            </dl>
            <p :if={!@project["logline"] and !@project["synopsis"]} class="muted">
              No logline or synopsis has been supplied. Pages remain the primary view.
            </p>
          </section>
          <details class="script-facts">
            <summary>Script facts</summary>
            <dl>
              <div>
                <dt>Scenes</dt><dd>{@facts.scene_count}</dd>
              </div>
              <div>
                <dt>Confirmed cast cues</dt><dd>{@facts.confirmed_cast_count}</dd>
              </div>
              <div>
                <dt>Interior headings</dt><dd>{@facts.heading_contexts.interior}</dd>
              </div>
              <div>
                <dt>Exterior headings</dt><dd>{@facts.heading_contexts.exterior}</dd>
              </div>
              <div>
                <dt>Other headings</dt><dd>{@facts.heading_contexts.other}</dd>
              </div>
              <div>
                <dt>Unknown heading context</dt><dd>{@facts.heading_contexts.unknown}</dd>
              </div>
              <div>
                <dt>Unknown time of day</dt><dd>{@facts.time_of_day_unknown_count}</dd>
              </div>
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
                  <strong>{character.name}</strong>
                  · {character.scene_count} speaking scenes · {character.cue_count} cues
                </li>
              </ul>
            </details>
            <p class="scope-note">
              Literal source facts only. No alias inference, coverage score, page/minute guarantee or production estimate.
            </p>
          </details>
        </div>
      </FountWeb.CoreComponents.disclosure>

      <div class="reader-layout">
        <details id="reader-scenes" class="reader-outline" aria-label="Scene outline">
          <summary class="reader-outline__title">
            <strong>Scenes</strong><span>{@facts.scene_count}</span>
          </summary>
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
        </details>

        <section
          id="responsive-reading-paper"
          class="reader-paper"
          aria-label="Responsive screenplay pages"
          phx-hook="PassageNote"
          data-project-key={@project["key"]}
          data-source-revision={@selected_source.screenplay.revision.id}
        >
          <div class="reader-paper__label">
            <span>Responsive reading view</span>
            <span class="reader-layout-choice" aria-label="Page layout">
              <strong>Page layout</strong>
              <span aria-current="page">Responsive</span>
              <a
                :if={@selected_source.kind == :current and @current_pdf}
                href={"/p/#{@project["key"]}/pages/#{@current_pdf.ref}"}
              >Exported pages</a>
              <a
                :if={@selected_source.kind == :current and is_nil(@current_pdf)}
                href={"/p/#{@project["key"]}/exports"}
              >Build exported pages</a>
              <span :if={@selected_source.kind != :current} title="Fixed-layout PDF is only shown for an exact built artifact of the selected saved source.">Exported pages unavailable for this selected source</span>
            </span>
            <button type="button" data-note-selection disabled>Note selected passage</button>
            <a href="/help#reading">How page references work</a>
          </div>
          <p class="selection-note-status" data-note-selection-status aria-live="polite">Select text within one screenplay passage to attach a note, or use the named passage picker in Notes.</p>
          <FountWeb.Components.ScreenplayRenderer.screenplay
            screenplay={@selected_source.screenplay}
            selected_scene_id={@selected_scene_id}
          />
        </section>
      </div>

      <details class="technical-details">
        <summary>Technical details</summary>
        <dl>
          <div>
            <dt>Project identity</dt><dd><code>{@project["id"]}</code></dd>
          </div>
          <div>
            <dt>Screenplay identity</dt><dd><code>{@selected_source.screenplay.id}</code></dd>
          </div>
          <div>
            <dt>Revision identity</dt><dd><code>{@selected_source.screenplay.revision.id}</code></dd>
          </div>
        </dl>
      </details>
    </main>
    """
  end
end
