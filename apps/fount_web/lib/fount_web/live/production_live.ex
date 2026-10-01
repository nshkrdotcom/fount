defmodule FountWeb.ProductionLive do
  use FountWeb, :live_view

  alias FountWeb.{ProductionStore, ProductionTools}

  @sections ~w(search cast locations notes read usefulness)

  @impl true
  def mount(%{"key" => project_key, "task_key" => task_key}, _session, socket) do
    owner = socket.assigns.current_owner

    case FountWeb.Store.run_access_by_task_key(Fount.Repo, owner, project_key, task_key) do
      {:ok, access} ->
        {:ok,
         socket
         |> assign(:run_id, access["run_id"])
         |> assign(:project_key, project_key)
         |> assign(:task_key, task_key)
         |> assign(:task_access, access)
         |> assign(:section, "search")
         |> assign(:view_token, nil)
         |> assign(:workspace, nil)
         |> assign(:search_query, "")
         |> assign(:search_attrs, %{"limit" => "50"})
         |> assign(:search_result, nil)
         |> assign(:search_notice, nil)
         |> assign(:characters, [])
         |> assign(:locations, [])
         |> assign(:notes, [])
         |> assign(:measured_annotations, [])
         |> assign(:note_filter, %{})
         |> assign(:target_options, [])
         |> assign(:tool_candidates, [])
         |> assign(:table_reads, [])
         |> assign(:selected_read, nil)
         |> assign(:usefulness_rows, [])
         |> assign(:usefulness_report, nil)
         |> assign(:tts, ProductionTools.tts_status())
         |> assign(:error, nil)}

      _ ->
        {:ok,
         socket |> put_flash(:error, "That task's tools are not available.") |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    token = Map.get(params, "view")
    section = normalize_section(Map.get(params, "section"))

    case ProductionTools.workspace(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.run_id,
           token
         ) do
      {:ok, workspace} ->
        actual_token = FountWeb.ScreenplayViews.token(workspace.selection)

        previous_revision =
          socket.assigns.workspace && socket.assigns.workspace.screenplay.revision.id

        revision_changed? =
          is_binary(previous_revision) and previous_revision != workspace.screenplay.revision.id

        {:noreply,
         socket
         |> assign(:section, section)
         |> assign(:view_token, actual_token)
         |> assign(:workspace, workspace)
         |> assign(
           :search_result,
           if(revision_changed?, do: nil, else: socket.assigns.search_result)
         )
         |> assign(
           :search_notice,
           if(revision_changed?,
             do: "Search cleared because the exact revision changed.",
             else: nil
           )
         )
         |> assign(:characters, ProductionTools.character_profiles(workspace.screenplay))
         |> assign(:locations, ProductionTools.location_profiles(workspace.screenplay))
         |> assign(
           :measured_annotations,
           ProductionTools.measured_annotations(workspace.screenplay)
         )
         |> assign(:target_options, ProductionTools.target_options(workspace.screenplay))
         |> assign(:error, nil)
         |> reload_human_records()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Project tools unavailable: #{tool_error(reason)}")}
    end
  end

  @impl true
  def handle_event("change_view", %{"revision" => %{"view" => token}}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         "/p/#{socket.assigns.project_key}/tools/#{socket.assigns.task_key}?" <>
           URI.encode_query(%{"view" => token, "section" => socket.assigns.section})
     )}
  end

  def handle_event("change_section", %{"section" => section}, socket) do
    section = normalize_section(section)

    {:noreply,
     push_patch(socket,
       to:
         "/p/#{socket.assigns.project_key}/tools/#{socket.assigns.task_key}?" <>
           URI.encode_query(%{"view" => socket.assigns.view_token, "section" => section})
     )}
  end

  def handle_event("search", %{"search" => attrs}, socket) do
    query = Map.get(attrs, "query", "")

    case ProductionTools.search(socket.assigns.workspace.screenplay, query, attrs) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:search_query, query)
         |> assign(:search_attrs, attrs)
         |> assign(:search_result, result)
         |> assign(:search_notice, nil)
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Search unavailable: #{tool_error(reason)}")}
    end
  end

  def handle_event("filter_notes", %{"notes" => attrs}, socket) do
    notes = ProductionTools.notes(socket.assigns.workspace.screenplay, attrs)
    {:noreply, socket |> assign(:note_filter, attrs) |> assign(:notes, notes)}
  end

  def handle_event("save_note", %{"note" => attrs}, socket) do
    workspace = socket.assigns.workspace

    case ProductionTools.save_note_candidate(
           Fount.Repo,
           socket.assigns.current_owner,
           workspace.project["id"],
           workspace.screenplay.revision.id,
           attrs
         ) do
      {:ok, %{candidate: _candidate}} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Note proposal saved. The current screenplay is unchanged until you approve it separately."
         )
         |> assign(:error, nil)
         |> reload_human_records()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Note candidate not saved: #{tool_error(reason)}")}
    end
  end

  def handle_event("delete_note", %{"id" => note_id}, socket) do
    workspace = socket.assigns.workspace

    case ProductionTools.delete_note_candidate(
           Fount.Repo,
           socket.assigns.current_owner,
           workspace.project["id"],
           workspace.screenplay.revision.id,
           note_id
         ) do
      {:ok, %{candidate: _candidate}} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Note-deletion proposal saved. The current screenplay is unchanged."
         )
         |> assign(:error, nil)
         |> reload_human_records()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Note deletion not saved: #{tool_error(reason)}")}
    end
  end

  def handle_event("rename_character", %{"cast" => attrs}, socket) do
    workspace = socket.assigns.workspace

    case ProductionTools.save_cast_rename_candidate(
           Fount.Repo,
           socket.assigns.current_owner,
           workspace.project["id"],
           workspace.screenplay.revision.id,
           Map.get(attrs, "character_id", ""),
           Map.get(attrs, "name", "")
         ) do
      {:ok, %{candidate: _candidate, plan: plan}} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Rename proposal saved from #{length(plan.cue_operations)} confirmed cue(s); #{length(plan.review)} suggested mention(s) remain unaccepted."
         )
         |> assign(:error, nil)
         |> reload_human_records()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Cast candidate not saved: #{tool_error(reason)}")}
    end
  end

  def handle_event("accept_candidate", %{"candidate" => attrs}, socket) do
    candidate_id = Map.get(attrs, "id", "")
    approval_id = Map.get(attrs, "approval_id", "")

    case ProductionTools.accept_tool_candidate(
           Fount.Repo,
           socket.assigns.current_owner,
           candidate_id,
           approval_id
         ) do
      {:ok, accepted} ->
        accepted_token = "accepted:#{accepted.revision.id}"

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Candidate accepted as revision #{accepted.revision.id}. Reloading exact accepted head."
         )
         |> push_patch(
           to:
             "/p/#{socket.assigns.project_key}/tools/#{socket.assigns.task_key}?" <>
               URI.encode_query(%{"view" => accepted_token, "section" => socket.assigns.section})
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Candidate not accepted: #{tool_error(reason)}")}
    end
  end

  def handle_event("create_table_read", %{"read" => attrs}, socket) do
    selection =
      case Map.get(attrs, "scene_id", "") do
        "" -> %{"whole_screenplay" => true}
        scene_id -> %{"targets" => [%{"kind" => "scene", "id" => scene_id}]}
      end

    case ProductionTools.create_table_read(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.workspace,
           selection
         ) do
      {:ok, row} ->
        {:noreply,
         socket
         |> put_flash(:info, "Human table-read packet saved for the exact selected revision.")
         |> reload_human_records(row["id"])}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Table read not created: #{tool_error(reason)}")}
    end
  end

  def handle_event("select_table_read", %{"id" => id}, socket) do
    with {:ok, row} <- ProductionStore.table_read(Fount.Repo, socket.assigns.current_owner, id),
         true <- row["run_id"] == socket.assigns.run_id do
      {:noreply, assign(socket, :selected_read, row)}
    else
      false ->
        {:noreply, assign(socket, :error, "Table read unavailable: task source mismatch.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Table read unavailable: #{tool_error(reason)}")}
    end
  end

  def handle_event("table_read_state", params, socket) do
    with {:ok, read} <- require_selected_read(socket),
         {:ok, expected_version} <- parse_integer(params["version"]),
         {:ok, bookmark} <- parse_integer(params["bookmark_index"]),
         {:ok, elapsed} <- parse_integer(params["elapsed_ms"]),
         {:ok, saved} <-
           ProductionTools.update_table_read(
             Fount.Repo,
             socket.assigns.current_owner,
             read["id"],
             expected_version,
             %{
               bookmark_index: bookmark,
               elapsed_ms: elapsed,
               scroll_mode: params["scroll_mode"] || "paused"
             }
           ) do
      {:reply, %{status: "saved", version: saved["version"]},
       socket |> assign(:selected_read, saved) |> reload_human_records(saved["id"])}
    else
      {:error, {:stale_table_read, row}} ->
        {:reply, %{status: "stale", version: row["version"]},
         socket
         |> assign(:selected_read, row)
         |> assign(:error, "Table-read state changed in another tab; loaded the saved state.")}

      {:error, reason} ->
        {:reply, %{status: "error"},
         assign(socket, :error, "Table-read state not saved: #{tool_error(reason)}")}
    end
  end

  def handle_event("record_reaction", %{"reaction" => attrs}, socket) do
    with {:ok, read} <- require_selected_read(socket),
         {:ok, saved} <-
           ProductionTools.record_table_reaction(
             Fount.Repo,
             socket.assigns.current_owner,
             read["id"],
             read["version"],
             Map.put(attrs, "observer", "human")
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Human reaction saved with packet and revision identity.")
       |> assign(:selected_read, saved)
       |> reload_human_records(saved["id"])}
    else
      {:error, reason} ->
        {:noreply, assign(socket, :error, "Reaction not saved: #{tool_error(reason)}")}
    end
  end

  def handle_event("save_usefulness", %{"usefulness" => attrs}, socket) do
    case ProductionTools.create_usefulness(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.workspace,
           attrs
         ) do
      {:ok, _row} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Descriptive human usefulness evidence saved; no ranking was calculated."
         )
         |> reload_human_records()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Usefulness evidence not saved: #{tool_error(reason)}")}
    end
  end

  def handle_event("delete_usefulness", %{"id" => id}, socket) do
    case ProductionTools.delete_usefulness(Fount.Repo, socket.assigns.current_owner, id) do
      :ok ->
        {:noreply,
         socket |> put_flash(:info, "Usefulness record deleted.") |> reload_human_records()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Record not deleted: #{tool_error(reason)}")}
    end
  end

  defp reload_human_records(socket, selected_read_id \\ nil) do
    workspace = socket.assigns.workspace

    if workspace do
      owner = socket.assigns.current_owner
      project_id = workspace.project["id"]
      reads = ProductionTools.table_reads(Fount.Repo, owner, project_id)
      reads = Enum.filter(list_or_empty(reads), &(&1["run_id"] == socket.assigns.run_id))
      candidate_rows = ProductionTools.list_tool_candidates(Fount.Repo, owner, project_id)
      candidate_rows = list_or_empty(candidate_rows)
      usefulness_rows = ProductionStore.list_usefulness(Fount.Repo, owner, project_id, limit: 100)
      usefulness_rows = list_or_empty(usefulness_rows)

      selected_read =
        cond do
          is_binary(selected_read_id) ->
            Enum.find(reads, &(&1["id"] == selected_read_id))

          socket.assigns[:selected_read] ->
            Enum.find(reads, &(&1["id"] == socket.assigns.selected_read["id"]))

          true ->
            List.first(reads)
        end

      report =
        case ProductionTools.usefulness_report(Fount.Repo, owner, project_id) do
          {:ok, value} -> value
          _ -> nil
        end

      assign(socket,
        notes: ProductionTools.notes(workspace.screenplay, socket.assigns.note_filter),
        tool_candidates: candidate_rows,
        table_reads: reads,
        selected_read: selected_read,
        usefulness_rows: usefulness_rows,
        usefulness_report: report
      )
    else
      socket
    end
  end

  defp list_or_empty(value) when is_list(value), do: value
  defp list_or_empty(_), do: []

  defp require_selected_read(socket) do
    case socket.assigns.selected_read do
      %{} = read -> {:ok, read}
      _ -> {:error, :table_read_required}
    end
  end

  defp parse_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> {:ok, number}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_integer(_), do: {:error, :invalid_integer}
  defp normalize_section(section) when section in @sections, do: section
  defp normalize_section(_), do: "search"

  defp source_link(project_key, task_key, token, scene_ordinal) do
    params = %{"view" => token} |> maybe_scene(scene_ordinal)
    "/p/#{project_key}/source/#{task_key}?" <> URI.encode_query(params)
  end

  defp maybe_scene(params, value) when is_integer(value),
    do: Map.put(params, "scene", Integer.to_string(value))

  defp maybe_scene(params, _), do: params

  defp tool_error(:not_found), do: "The saved item is no longer available."
  defp tool_error(:conflict), do: "The saved item changed. Reload it before trying again."

  defp tool_error(:stale_revision),
    do: "The screenplay changed; reopen the current source before saving."

  defp tool_error(_), do: "The action could not be completed. No accepted screenplay was changed."

  defp read_ref(reads, selected) do
    case Enum.find_index(reads, &(&1["id"] == selected["id"])) do
      nil -> "read-1"
      index -> "read-#{index + 1}"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="production-shell">
      <fieldset class="production-connection" disabled={not connected?(@socket)}>
        <FountWeb.CoreComponents.project_header
          project={
            %{"key" => @project_key, "title" => @task_access["title"], "project_kind" => "screenplay"}
          }
          section="notes"
          view="reading"
          source_label="Task source"
        />
        <nav class="task-subnav" aria-label="Task">
          <strong>{@task_access["display_label"] || "Saved task"}</strong>
          <a href={"/p/#{@project_key}/activity/#{@task_key}"}>Activity</a>
          <a href={"/p/#{@project_key}/source/#{@task_key}?" <> URI.encode_query(%{"view" => @view_token})}>Sources</a>
          <a href={"/p/#{@project_key}/analysis/#{@task_key}"}>Analysis</a>
          <a href={"/p/#{@project_key}/tools/#{@task_key}"} aria-current="page">Tools</a>
        </nav>

        <p :if={@flash["info"]} class="notice" role="status">{@flash["info"]}</p>
        <p :if={@error} class="warning" role="alert">{@error}</p>

        <%= if @workspace do %>
          <header class="production-mast">
            <div>
              <p class="eyebrow">Screenplay tools</p>
              <h1>{@workspace.project["title"]}</h1>
              <p>
                <strong>{@task_access["display_label"] || "Saved task"}</strong>
                · {@workspace.selection.label}
              </p>
              <details class="technical-details">
                <summary>Technical details</summary>
                <p>
                  Screenplay <code>{@workspace.screenplay.id}</code>
                  · revision <code>{@workspace.screenplay.revision.id}</code>
                </p>
              </details>
              <p :if={!@workspace.editable?} class="warning">
                This selected revision is inspection-only. Note/cast changes require the current accepted head.
              </p>
            </div>
            <form id="production-revision-form" phx-change="change_view" class="compact-form">
              <label>
                Screenplay version
                <select name="revision[view]">
                  <option
                    :for={option <- @workspace.options}
                    value={FountWeb.ScreenplayViews.token(option)}
                    selected={FountWeb.ScreenplayViews.token(option) == @view_token}
                  >
                    {option.label}
                  </option>
                </select>
              </label>
            </form>
          </header>

          <nav class="tool-tabs" aria-label="Production tool sections">
            <button
              :for={tab <- ~w(search cast locations notes read usefulness)}
              type="button"
              phx-click="change_section"
              phx-value-section={tab}
              aria-current={if(@section == tab, do: "page", else: nil)}
            >
              {String.capitalize(tab)}
            </button>
          </nav>

          <section :if={@section == "search"} class="tool-grid" aria-labelledby="search-title">
            <article class="card stack tool-controls">
              <p class="eyebrow">Search</p><h2 id="search-title">
                Search this screenplay version
              </h2>
              <form phx-submit="search" class="stack">
                <label>Literal phrase <input name="search[query]" value={@search_query} required /></label>
                <label>
                  Scene
                  <select name="search[scene_id]">
                    <option value="">All active scenes</option>
                    <option
                      :for={scene <- FountWeb.ScreenplayIndex.scene_index(@workspace.screenplay)}
                      value={scene.id}
                      selected={@search_attrs["scene_id"] == scene.id}
                    >
                      {scene.ordinal} · {scene.heading}
                    </option>
                  </select>
                </label>
                <label>
                  Character
                  <select name="search[character_id]">
                    <option value="">Any character</option>
                    <option
                      :for={character <- @characters}
                      value={character.id}
                      selected={@search_attrs["character_id"] == character.id}
                    >
                      {character.display_name}
                    </option>
                  </select>
                </label>
                <label>
                  Location
                  <select name="search[location]">
                    <option value="">Any resolved location</option>
                    <option
                      :for={location <- @locations}
                      value={location.location}
                      selected={@search_attrs["location"] == location.location}
                    >
                      {location.location}
                    </option>
                  </select>
                </label>
                <label>
                  Element type
                  <select name="search[element_type]">
                    <option value="">All supported types</option>
                    <option
                      :for={type <- FountWeb.ProductionTools.search_types()}
                      value={type}
                      selected={@search_attrs["element_type"] == type}
                    >
                      {type}
                    </option>
                  </select>
                </label>
                <label>Limit
                <input
                  type="number"
                  min="1"
                  max="200"
                  name="search[limit]"
                  value={@search_attrs["limit"] || "50"}
                /></label>
                <div class="check-row">
                  <label><input
                    type="checkbox"
                    name="search[include_omitted]"
                    value="true"
                    checked={@search_attrs["include_omitted"] == "true"}
                  /> omitted</label>
                  <label><input
                    type="checkbox"
                    name="search[include_notes]"
                    value="true"
                    checked={@search_attrs["include_notes"] == "true"}
                  /> Fountain notes</label>
                  <label><input
                    type="checkbox"
                    name="search[include_boneyards]"
                    value="true"
                    checked={@search_attrs["include_boneyards"] == "true"}
                  /> boneyards</label>
                </div>
                <button type="submit">Search selected revision</button>
              </form>
              <p class="muted">
                Matches the words you enter in this screenplay version. Search does not use AI.
              </p>
              <p :if={@search_notice} class="warning" role="status">{@search_notice}</p>
            </article>

            <article class="card stack tool-results" aria-live="polite">
              <%= if @search_result do %>
                <h2>Results</h2>
                <p>
                  Inspected {@search_result.inspected_element_count} eligible elements; returned {@search_result.returned_hit_count}.
                  <strong :if={@search_result.truncated?}>Truncated at the requested limit.</strong>
                </p>
                <p :if={@search_result.hits == []}>
                  No literal matches in this revision/filter scope.
                </p>
                <ol class="search-hits">
                  <li :for={hit <- @search_result.hits}>
                    <div>
                      <code>{hit.type}</code>
                      · scene {hit.scene_ordinal || "—"} {hit.scene_heading || ""}
                    </div>
                    <p>{hit.excerpt}</p>
                    <a href={source_link(@project_key, @task_key, @view_token, hit.scene_ordinal)}>Open source scene</a>
                  </li>
                </ol>
              <% else %>
                <p>
                  Search results will report exact revision identity, inspected count, returned count and truncation.
                </p>
              <% end %>
            </article>
          </section>

          <section :if={@section == "cast"} class="stack" aria-labelledby="cast-title">
            <div class="section-heading">
              <p class="eyebrow">Cast</p><h2 id="cast-title">Character profiles</h2>
            </div>
            <div class="dense-card-grid">
              <article :for={character <- @characters} class="card character-card">
                <h3>{character.display_name}</h3>
                <p>
                  Aliases: {if(character.aliases == [],
                    do: "none recorded",
                    else: Enum.join(character.aliases, ", ")
                  )}
                </p>
                <dl class="fact-grid">
                  <div>
                    <dt>Confirmed mentions</dt><dd>{character.confirmed_mentions}</dd>
                  </div>
                  <div>
                    <dt>Appearances</dt><dd>{character.appearance_count}</dd>
                  </div>
                  <div>
                    <dt>Dialogue blocks</dt><dd>{character.dialogue_block_count}</dd>
                  </div>
                  <div>
                    <dt>Dialogue words</dt><dd>{character.dialogue_word_count}</dd>
                  </div>
                </dl>
                <p>
                  Relationship evidence: {if(character.relationship_evidence == [],
                    do: "none recorded",
                    else: "recorded evidence available"
                  )}
                </p>
                <form :if={@workspace.editable?} phx-submit="rename_character" class="inline-form">
                  <input type="hidden" name="cast[character_id]" value={character.id} />
                  <label>Candidate name <input name="cast[name]" value={character.display_name} /></label>
                  <button type="submit" phx-disable-with="Saving candidate…">Save rename candidate</button>
                </form>
              </article>
            </div>
            <p class="muted">
              Counts are descriptive source facts; they do not infer biography, emotional arc or screenplay quality.
            </p>
          </section>

          <section :if={@section == "locations"} class="stack" aria-labelledby="locations-title">
            <div class="section-heading">
              <p class="eyebrow">Locations</p><h2 id="locations-title">
                Locations and scene order
              </h2>
            </div>
            <article :for={location <- @locations} class="card stack location-card">
              <h3>{location.location}</h3><p>{location.scene_count} associated scene(s)</p>
              <div class="table-scroll">
                <table>
                  <thead>
                    <tr>
                      <th>Order</th><th>Heading</th><th>INT/EXT</th><th>Time</th><th>Source</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={entry <- location.entries}>
                      <td>{entry.ordinal || "—"}</td><td>{entry.heading || entry.raw}</td><td>
                        {entry.parsed_context}
                      </td><td>{entry.parsed_time}</td>
                      <td>
                        <a href={
                          source_link(@project_key, @task_key, @view_token, "scene-#{entry.scene_id}")
                        }>Screenplay version</a>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </article>
            <p>
              Whole-script estimates: {@workspace.screenplay
              |> FountWeb.ScreenplayIndex.estimates()
              |> get_in([:pages, :label])}; {@workspace.screenplay
              |> FountWeb.ScreenplayIndex.estimates()
              |> get_in([:duration, :label])}.
            </p>
            <p class="muted">
              Unknown parse values stay unknown; these are not shooting schedules or production plans.
            </p>
          </section>

          <section :if={@section == "notes"} class="tool-grid" aria-labelledby="notes-title">
            <article class="card stack tool-controls">
              <p class="eyebrow">Writer notes</p><h2 id="notes-title">Writer notes</h2>
              <form id="production-note-filter" phx-change="filter_notes" class="stack">
                <label>Filter <input name="notes[query]" value={@note_filter["query"] || ""} /></label>
                <label>
                  Status
                  <select name="notes[status]">
                    <option value="">All</option>
                    <option
                      :for={status <- ~w(active active_untracked stale_changed unresolved)}
                      value={status}
                      selected={@note_filter["status"] == status}
                    >
                      {String.replace(status, "_", " ")}
                    </option>
                  </select>
                </label>
              </form>
              <form :if={@workspace.editable?} phx-submit="save_note" class="stack">
                <h3>Create note candidate</h3>
                <label>Title <input name="note[title]" /></label>
                <label>
                  Target
                  <select name="note[target]">
                    <option :for={option <- @target_options} value={option.value}>
                      {option.label}
                    </option>
                  </select>
                </label>
                <details class="technical-details">
                  <summary>Technical target override</summary>
                  <label>
                    Exact internal target
                    <input name="note[target_override]" placeholder="element:internal-id" />
                  </label>
                </details>
                <label>Note <textarea name="note[text]" required></textarea></label>
                <button type="submit" phx-disable-with="Saving candidate…">Save note candidate</button>
              </form>
              <p class="muted">
                Target picker includes the screenplay, all scenes/cast entries, and at most the first 250 nonblank elements. Larger scripts require choosing a scene/cast target here or using an exact element already surfaced by the workspace.
              </p>
              <p :if={!@workspace.editable?} class="warning">
                Select the current accepted head to create, edit, remap or delete notes.
              </p>
              <a href={"/p/#{@project_key}/tools/#{@task_key}/notes.json?" <> URI.encode_query(%{"view" => @view_token})}>Export notes JSON for this exact revision</a>
            </article>

            <article class="stack tool-results">
              <article
                :for={note <- @notes}
                class="card note-card"
                data-note-state={note.target_state}
              >
                <header>
                  <h3>{note.title || "Untitled note"}</h3><span class="status-badge status-badge--neutral">{note.target_state
                  |> to_string()
                  |> String.replace("_", " ")}</span>
                </header>
                <p>{note.text}</p>
                <p>Target: {note.target["kind"] |> to_string() |> String.replace("_", " ")}</p>
                <p>
                  Producer: {note.provenance["producer"] || "unknown"} · exact source is recorded.
                </p>
                <details class="technical-details">
                  <summary>Technical source binding</summary><code>{note.bound_revision_id}</code>
                </details>
                <form :if={@workspace.editable?} phx-submit="save_note" class="stack">
                  <input type="hidden" name="note[id]" value={note.id} />
                  <label>Title <input name="note[title]" value={note.title} /></label>
                  <label>
                    Explicit remap target
                    <select name="note[target]">
                      <option :if={note.target_state == "unresolved"} value="" selected disabled>
                        Choose an explicit replacement target
                      </option>
                      <option
                        :for={option <- @target_options}
                        value={option.value}
                        selected={option.value == "#{note.target["kind"]}:#{note.target["id"]}"}
                      >
                        {option.label}
                      </option>
                    </select>
                  </label>
                  <details class="technical-details">
                    <summary>Technical target override</summary>
                    <label>
                      Exact internal target
                      <input name="note[target_override]" placeholder="element:internal-id" />
                    </label>
                  </details>
                  <label>Text <textarea name="note[text]" required><%= note.text %></textarea></label>
                  <button type="submit" phx-disable-with="Saving candidate…">Save edited/remapped candidate</button>
                </form>
                <button
                  :if={@workspace.editable?}
                  type="button"
                  phx-click="delete_note"
                  phx-value-id={note.id}
                >Save deletion candidate</button>
              </article>
              <article class="card stack annotation-provenance">
                <h3>Measured annotations are separate evidence</h3>
                <p class="muted">
                  These recorded annotations are derived evidence with producer provenance. They are not writer-authored notes and are not accepted screenplay text.
                </p>
                <p :if={@measured_annotations == []}>
                  No measured annotations are stored on this revision.
                </p>
                <details :for={annotation <- Enum.take(@measured_annotations, 24)}>
                  <summary>{annotation.namespace} · {annotation.kind}</summary>
                  <p>
                    Saved measured annotation
                    <details class="technical-details">
                      <summary>Technical source binding</summary><code>{annotation.id}</code>
                      · <code>{annotation.source_revision}</code>
                    </details>
                  </p>
                  <p>
                    Producer: {get_in(annotation, [:provenance, "producer"]) ||
                      get_in(annotation, [:provenance, :producer]) || "unknown"}
                  </p>
                </details>
                <p :if={length(@measured_annotations) > 24}>
                  Showing the first 24 stored annotations for this exact revision.
                </p>
              </article>
            </article>
          </section>

          <section
            :if={@section in ["notes", "cast"] and @tool_candidates != []}
            class="card stack candidate-registry"
          >
            <h2>Pending production-tool candidates</h2>
            <p>
              Saving proposed changes leaves the approved screenplay unchanged. Review and approve them separately.
            </p>
            <div class="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Kind</th><th>Change</th><th>Base</th><th>Decision</th><th>Action</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={{candidate, ordinal} <- Enum.with_index(@tool_candidates, 1)}>
                    <td>{candidate["kind"]}</td><td>Proposed change {ordinal}</td><td>
                      <span>Exact base recorded</span>
                    </td><td>{candidate["decision"]}</td>
                    <td>
                      <form :if={candidate["decision"] == "proposed"} phx-submit="accept_candidate">
                        <input type="hidden" name="candidate[id]" value={candidate["candidate_id"]} />
                        <input type="hidden" name="candidate[approval_id]" value={Fount.ID.v4()} />
                        <button type="submit" phx-disable-with="Approving…">Exact approve</button>
                      </form>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section :if={@section == "read"} class="tool-grid" aria-labelledby="read-title">
            <article class="card stack tool-controls">
              <p class="eyebrow">Read together</p><h2 id="read-title">Table read</h2>
              <form phx-submit="create_table_read" class="stack">
                <label>
                  Material
                  <select name="read[scene_id]">
                    <option value="">Whole screenplay</option>
                    <option
                      :for={scene <- FountWeb.ScreenplayIndex.scene_index(@workspace.screenplay)}
                      value={scene.id}
                    >
                      {scene.ordinal} · {scene.heading}
                    </option>
                  </select>
                </label>
                <button type="submit" phx-disable-with="Saving packet…">Save read packet</button>
              </form>
              <p>{@tts.label}</p>
              <p class="muted">
                Automatic scrolling is finite, pauseable and disabled when the browser requests reduced motion. No microphone capture and no automatic performance or quality scoring.
              </p>
              <h3>Saved reads</h3>
              <button
                :for={{read, ordinal} <- Enum.with_index(@table_reads, 1)}
                type="button"
                phx-click="select_table_read"
                phx-value-id={read["id"]}
              >
                Saved table read {ordinal}
              </button>
            </article>

            <article
              :if={@selected_read}
              class="card stack table-read-workspace"
              id="table-read-workspace"
              phx-hook="TableReadWorkspace"
              data-read-id={@selected_read["id"]}
              data-version={@selected_read["version"]}
              data-bookmark={@selected_read["bookmark_index"]}
              data-elapsed-ms={@selected_read["elapsed_ms"]}
            >
              <header>
                <h2>Saved table read</h2>
                <p>
                  Exact source revision recorded
                  · saved state v{@selected_read["version"]}
                </p>
              </header>
              <div class="read-controls" role="group" aria-label="Table read controls">
                <button type="button" data-read-start>Auto-scroll</button>
                <button type="button" data-read-pause>Pause</button>
                <button type="button" data-read-bookmark>Bookmark active turn</button>
                <span>Elapsed <output data-read-elapsed>{@selected_read["elapsed_ms"]}</output> ms</span>
              </div>
              <div class="read-turns" data-read-turns tabindex="0">
                <article
                  :for={{turn, index} <- Enum.with_index(@selected_read["packet"]["turns"] || [])}
                  class="read-turn"
                  data-read-turn
                  data-index={index}
                  tabindex="0"
                >
                  <strong>{turn["cue"] || turn["character"] || turn["character_name"] ||
                    turn["character_id"] || "Reader"}</strong>
                  <p>{turn["dialogue"] || turn["text"]}</p>
                </article>
              </div>
              <form phx-submit="record_reaction" class="stack">
                <label>Reader label <input name="reaction[reader_id]" /></label>
                <label>Human reaction <textarea name="reaction[reaction]" required></textarea></label>
                <label>Reader delivery <input name="reaction[reader_delivery]" /></label>
                <label>Listening conditions <input name="reaction[listening_conditions]" /></label>
                <button type="submit" phx-disable-with="Saving reaction…">Save human reaction</button>
              </form>
              <ul>
                <li :for={reaction <- @selected_read["packet"]["reactions"] || []}>
                  {reaction["reader_id"] || "human"}: {reaction["reaction"]}
                </li>
              </ul>
              <a href={"/p/#{@project_key}/tools/#{@task_key}/table-reads/#{read_ref(@table_reads, @selected_read)}/export.json"}>Export saved read JSON</a>
              <details class="technical-details">
                <summary>Technical details</summary><code>{@selected_read["id"]}</code>
                · packet <code>{@selected_read["packet_id"]}</code>
              </details>
            </article>
          </section>

          <section :if={@section == "usefulness"} class="tool-grid" aria-labelledby="usefulness-title">
            <article class="card stack tool-controls">
              <p class="eyebrow">Your feedback</p><h2 id="usefulness-title">
                Usefulness records
              </h2>
              <form phx-submit="save_usefulness" class="stack">
                <label>Task ID <input name="usefulness[task_id]" required /></label>
                <label>
                  Condition
                  <select name="usefulness[condition]">
                    <option
                      :for={condition <- FountWorkshop.Usefulness.conditions()}
                      value={condition}
                    >
                      {condition}
                    </option>
                  </select>
                </label>
                <label>
                  Outcome
                  <select name="usefulness[outcome]"><option value="positive">positive</option><option value="neutral">
                    neutral
                  </option><option value="negative">negative</option></select>
                </label>
                <label><input type="checkbox" name="usefulness[kept_original]" value="true" />
                Kept original</label>
                <label>Preference (optional) <input name="usefulness[preference]" /></label>
                <fieldset class="stack">
                  <legend>Optional human-response dimensions (kept separate; not aggregated)</legend>
                  <label>Task completion <input name="usefulness[dimensions][task_completion]" /></label>
                  <label>Next decision <input name="usefulness[dimensions][next_decision]" /></label>
                  <label>Agency <input name="usefulness[dimensions][agency]" /></label>
                  <label>Voice retention <input name="usefulness[dimensions][voice_retention]" /></label>
                  <label>Alternative diversity
                  <input name="usefulness[dimensions][alternative_diversity]" /></label>
                  <label>Consequence usefulness
                  <input name="usefulness[dimensions][consequence_usefulness]" /></label>
                  <label>Rejection time (ms)
                  <input type="number" min="0" name="usefulness[dimensions][rejection_time_ms]" /></label>
                </fieldset>
                <label>Output refs, one per line <textarea name="usefulness[output_refs]"></textarea></label>
                <label>Friction, one item per line <textarea name="usefulness[friction]"></textarea></label>
                <label>Notes, one item per line <textarea name="usefulness[notes]"></textarea></label>
                <button type="submit" phx-disable-with="Saving evidence…">Save descriptive record</button>
              </form>
              <a href={"/p/#{@project_key}/tools/#{@task_key}/usefulness.json"}>Export owner-scoped evidence JSON</a>
            </article>
            <article class="card stack tool-results">
              <%= if @usefulness_report do %>
                <h2>Evidence report</h2>
                <p>{@usefulness_report["sample_label"]}</p>
                <p>{@usefulness_report["missing_data_label"]}</p>
                <p>Conditions present: {Enum.join(@usefulness_report["conditions_present"], ", ")}</p>
                <p>
                  No aggregate screenplay score, winner, expert endorsement or representative-sample claim is made.
                </p>
              <% end %>
              <article :for={row <- @usefulness_rows} class="evidence-row">
                <strong>{row["task_id"]}</strong>
                · {row["condition"]} · {get_in(row, ["record", "human_response", "outcome"])}
                <span :if={get_in(row, ["record", "human_response", "kept_original"])}> · kept original</span>
                <button type="button" phx-click="delete_usefulness" phx-value-id={row["id"]}>Delete</button>
              </article>
            </article>
          </section>
        <% end %>
      </fieldset>
    </main>
    """
  end
end
