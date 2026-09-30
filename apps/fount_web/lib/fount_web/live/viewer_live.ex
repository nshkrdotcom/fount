defmodule FountWeb.ViewerLive do
  use FountWeb, :live_view

  alias FountWeb.{ScreenplayIndex, ScreenplayViews}

  @impl true
  def mount(%{"id" => run_id} = params, _session, socket) do
    owner = socket.assigns.current_owner

    case FountWeb.Store.run_access(Fount.Repo, owner, run_id) do
      {:ok, access} ->
        with {:ok, context} <- FountWeb.Actors.owner_context(owner, access["screenplay_id"]),
             {:ok, run} <- FountRun.get_run(Fount.Repo, run_id, context),
             {:ok, progress} <- FountRun.progress(Fount.Repo, run_id, context) do
          {:ok,
           load_workspace(socket, run_id, access, run, progress, params)
           |> assign(:identity_dialog_open, false)}
        else
          {:error, reason} ->
            {:ok,
             socket
             |> assign(:run_id, run_id)
             |> assign(:access, access)
             |> assign(:run, %{})
             |> assign(:progress, %{})
             |> assign(:workspace, nil)
             |> assign(:index, empty_index())
             |> assign(:character_filter, "")
             |> assign(:selected_scene_id, nil)
             |> assign(:base_screenplay, nil)
             |> assign(:identity_dialog_open, false)
             |> assign(:error, "Run state unavailable: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Run not found for this owner.") |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("open_identity_dialog", _params, socket),
    do: {:noreply, assign(socket, :identity_dialog_open, true)}

  def handle_event("close_identity_dialog", _params, socket),
    do: {:noreply, assign(socket, :identity_dialog_open, false)}

  defp load_workspace(socket, run_id, access, run, progress, params) do
    filter = params |> Map.get("character", "") |> bounded_filter()
    token = Map.get(params, "view")

    {workspace, error} =
      case ScreenplayViews.load(Fount.Repo, access, run, progress, token) do
        {:ok, workspace} ->
          {workspace, nil}

        {:error, reason} ->
          case ScreenplayViews.load(Fount.Repo, access, run, progress, nil) do
            {:ok, fallback} ->
              {fallback, human_view_error(reason) <> " Showing the bound Run base instead."}

            {:error, fallback_reason} ->
              {nil, human_view_error(fallback_reason)}
          end
      end

    index =
      if workspace,
        do: ScreenplayIndex.build(workspace.screenplay, character_filter: filter),
        else: empty_index()

    requested_scene = Map.get(params, "scene")
    selected_scene_id = valid_scene_id(index.scenes, requested_scene)

    scene_error =
      if is_binary(requested_scene) and is_nil(selected_scene_id),
        do: "The requested scene is not present in this selected revision.",
        else: nil

    base_screenplay = load_base_screenplay(run, access)

    socket
    |> assign(:run_id, run_id)
    |> assign(:access, access)
    |> assign(:run, run)
    |> assign(:progress, progress)
    |> assign(:workspace, workspace)
    |> assign(:index, index)
    |> assign(:character_filter, filter)
    |> assign(:selected_scene_id, selected_scene_id)
    |> assign(:base_screenplay, base_screenplay)
    |> assign(:error, Enum.find([error, scene_error], &is_binary/1))
  end

  defp load_base_screenplay(run, access) do
    revision_id = get_in(run, ["plan", "base_revision_id"])

    case Fount.Persistence.load_revision(Fount.Repo, access["screenplay_id"], revision_id) do
      {:ok, screenplay} -> screenplay
      _ -> nil
    end
  end

  defp valid_scene_id(_scenes, nil), do: nil

  defp valid_scene_id(scenes, scene_id) do
    if Enum.any?(scenes, &(&1.id == scene_id)), do: scene_id, else: nil
  end

  defp bounded_filter(filter) when is_binary(filter),
    do: filter |> String.slice(0, 80) |> String.trim()

  defp bounded_filter(_), do: ""

  defp empty_index, do: %{scenes: [], characters: [], dialogue: [], locations: []}

  defp human_view_error(:stale_or_unbound_revision),
    do: "That revision reference is stale or is not bound to this Run."

  defp human_view_error(:revision_not_found), do: "The bound revision no longer exists."
  defp human_view_error(:candidate_not_found), do: "The bound candidate no longer exists."

  defp human_view_error(:candidate_identity_mismatch),
    do: "Candidate identity does not match this Run screenplay."

  defp human_view_error(:run_screenplay_mismatch),
    do: "Run and project screenplay identities do not match."

  defp human_view_error(:no_bound_revision),
    do: "This Run has no bound screenplay revision to display."

  defp view_path(run_id, token, scene_id, filter) do
    query =
      %{"view" => token}
      |> maybe_put("scene", scene_id)
      |> maybe_put("character", filter)
      |> URI.encode_query()

    "/runs/#{run_id}/viewer?#{query}"
  end

  defp maybe_put(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp revision_kind(%{kind: :base}), do: "Run base"

  defp revision_kind(%{kind: :candidate}),
    do: "Candidate — canon unchanged unless separately accepted"

  defp revision_kind(%{kind: :accepted}), do: "Accepted canonical revision"

  @impl true
  def render(assigns) do
    ~H"""
    <main id={"viewer-#{@run_id}"} class="workspace-shell" phx-hook="SceneNavigator">
      <nav aria-label="Run">
        <a href={~p"/"}>Projects</a>
        <a href={~p"/runs/#{@run_id}/setup"}>Setup</a>
        <a href={~p"/runs/#{@run_id}/timeline"}>Timeline</a>
        <a href={~p"/runs/#{@run_id}/decisions"}>Decisions</a>
        <a href={~p"/runs/#{@run_id}/review"}>Review</a>
        <a href={~p"/runs/#{@run_id}/viewer"} aria-current="page">Viewer</a>
        <a href={~p"/runs/#{@run_id}/edit"}>Editor</a>
        <a href={~p"/runs/#{@run_id}/exports"}>Exports</a>
      </nav>

      <header class="workspace-header">
        <div>
          <p class="eyebrow">Read-only screenplay workspace</p>
          <h1>{@access["title"]}</h1>
          <p>Run <code>{@run_id}</code> · screenplay <code>{@access["screenplay_id"]}</code></p>
        </div>
        <FountWeb.CoreComponents.status_badge status={@run["status"] || "unknown"} />
      </header>

      <FountWeb.CoreComponents.alert :if={@error} kind="warning" title="Viewer notice">
        {@error}
      </FountWeb.CoreComponents.alert>

      <FountWeb.CoreComponents.error_state
        :if={is_nil(@workspace)}
        title="No screenplay revision available"
        detail={@error || "No bound revision could be loaded."}
      />

      <%= if @workspace do %>
        <section class="workspace-controls" aria-label="Viewer controls">
          <form action={~p"/runs/#{@run_id}/viewer"} method="get" class="workspace-control-form">
            <FountWeb.CoreComponents.select
              id="viewer-revision"
              name="view"
              label="Displayed revision"
              value={@workspace.selection.token}
              options={Enum.map(@workspace.options, &{&1.label <> " · " <> &1.revision_id, &1.token})}
            />
            <FountWeb.CoreComponents.input
              id="character-filter"
              name="character"
              label="Filter character index"
              value={@character_filter}
              placeholder="Literal cue name"
            />
            <FountWeb.CoreComponents.button type="submit" variant="secondary">Apply view</FountWeb.CoreComponents.button>
          </form>

          <FountWeb.CoreComponents.card>
            <p><strong>{revision_kind(@workspace.selection)}</strong></p>
            <p>Revision <code>{@workspace.selection.revision_id}</code></p>
            <p :if={@workspace.selection[:candidate_id]}>
              Candidate <code>{@workspace.selection.candidate_id}</code>
            </p>
            <p>Page estimate: <strong>{@index.estimates.pages.label}</strong>.</p>
            <p>Duration estimate: <strong>{@index.estimates.duration.label}</strong>.</p>
          </FountWeb.CoreComponents.card>
          <p :if={!Enum.any?(@workspace.options, &(&1.kind == :candidate))} class="scope-note">
            No Run-bound candidate is currently available; the viewer remains on persisted base/accepted identities only.
          </p>
          <FountWeb.CoreComponents.button
            id="revision-identity-help"
            type="button"
            variant="secondary"
            phx-click="open_identity_dialog"
          >Revision identity details</FountWeb.CoreComponents.button>

          <FountWeb.CoreComponents.dialog
            id="revision-identity-dialog"
            title="Revision identity"
            open={@identity_dialog_open}
            return_focus="revision-identity-help"
            cancel_event="close_identity_dialog"
          >
            <p>
              The viewer loads only revisions bound to this owner-authorized Run. Selecting a candidate never accepts it.
            </p>
            <:actions>
              <FountWeb.CoreComponents.button type="button" phx-click="close_identity_dialog">Close</FountWeb.CoreComponents.button>
            </:actions>
          </FountWeb.CoreComponents.dialog>
        </section>

        <div class="workspace-grid">
          <aside class="workspace-sidebar" aria-label="Screenplay navigation">
            <details id="scene-outline" class="workspace-panel" open>
              <summary>Scenes ({length(@index.scenes)})</summary>
              <ol class="scene-outline">
                <li :for={scene <- @index.scenes} data-scene-outline-item={scene.id}>
                  <a
                    href={"#scene-#{scene.id}"}
                    data-scene-link={scene.id}
                    aria-current={if scene.id == @selected_scene_id, do: "location", else: nil}
                  >
                    <span>{scene.number || scene.ordinal}</span>
                    <span>{scene.heading || "Untitled scene"}</span>
                  </a>
                  <small>{scene.location || "Location unknown"}</small>
                </li>
              </ol>
              <p :if={@index.scenes == []}>No scenes in this revision.</p>
            </details>

            <details class="workspace-panel" open>
              <summary>Characters ({length(@index.characters)})</summary>
              <p class="scope-note">
                Literal cue summaries only; repeated cue spelling is not cast-entity proof.
              </p>
              <ul class="index-list">
                <li :for={character <- @index.characters}>
                  <strong>{character.name}</strong>
                  <span>{character.cue_count} cues · {character.dialogue_block_count} turns</span>
                  <a
                    :if={character.scene_ids != []}
                    href={"#scene-#{hd(character.scene_ids)}"}
                    data-scene-link={hd(character.scene_ids)}
                  >First scene</a>
                </li>
              </ul>
              <p :if={@index.characters == []}>No matching character cues.</p>
            </details>

            <details class="workspace-panel">
              <summary>Locations ({length(@index.locations)})</summary>
              <ul class="index-list">
                <li :for={location <- @index.locations}>
                  <strong>{location.location}</strong>
                  <span>{location.scene_count} scenes</span>
                  <a
                    :if={location.scene_ids != []}
                    href={"#scene-#{hd(location.scene_ids)}"}
                    data-scene-link={hd(location.scene_ids)}
                  >First scene</a>
                </li>
              </ul>
            </details>

            <details class="workspace-panel">
              <summary>Dialogue ({length(@index.dialogue)})</summary>
              <ul class="index-list">
                <li :for={turn <- @index.dialogue}>
                  <strong>{turn.character || "Unknown cue"}</strong>
                  <span>{turn.words} words{if turn.dual?, do: " · dual", else: ""}</span>
                  <a
                    :if={turn.scene_id}
                    href={"#scene-#{turn.scene_id}"}
                    data-scene-link={turn.scene_id}
                  >Scene</a>
                </li>
              </ul>
            </details>
          </aside>

          <section class="workspace-reader" aria-label="Screenplay revision">
            <FountWeb.Components.ScreenplayRenderer.screenplay
              screenplay={@workspace.screenplay}
              selected_scene_id={@selected_scene_id}
            />
          </section>
        </div>

        <section :if={@base_screenplay && @workspace.selection.kind != :base} class="workspace-diff">
          <h2>Compared with Run base</h2>
          <nav aria-label="Diff display">
            <a href={view_path(@run_id, @workspace.selection.token, @selected_scene_id, @character_filter) <> "#diff"}>Unified structural view</a>
          </nav>
          <div id="diff">
            <FountWeb.Components.DiffViewer.diff
              before={@base_screenplay}
              after={@workspace.screenplay}
              before_label="Run base"
              after_label={@workspace.selection.label}
              before_status="base"
              after_status={@workspace.selection.status}
              mode="unified"
            />
          </div>
        </section>
      <% end %>
    </main>
    """
  end
end
