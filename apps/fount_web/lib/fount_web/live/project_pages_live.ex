defmodule FountWeb.ProjectPagesLive do
  use FountWeb, :live_view

  alias FountWeb.{ProductionStore, Store}

  @impl true
  def mount(%{"key" => key, "artifact_ref" => artifact_ref} = params, _session, socket) do
    owner = socket.assigns.current_owner

    with {:ok, project} <- Store.project_by_key(Fount.Repo, owner, key),
         {:ok, artifact} <-
           ProductionStore.project_artifact_by_ref(
             Fount.Repo,
             owner,
             project["id"],
             artifact_ref
           ),
         true <- artifact["state"] == "ready" and artifact["kind"] == "pdf" do
      page_count = page_count(artifact)
      page = clamp_page(params["page"], page_count)

      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:artifact, artifact)
       |> assign(:artifact_ref, artifact_ref)
       |> assign(:page_count, page_count)
       |> assign(:page, page)}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "That exported PDF is not available for this project.")
         |> redirect(to: "/p/#{key}/exports")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns[:artifact] do
      {:noreply, assign(socket, :page, clamp_page(params["page"], socket.assigns.page_count))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="project-workspace exported-pages-workspace">
      <FountWeb.CoreComponents.project_header
        project={@project}
        section="script"
        view="reading"
        source_label={@artifact["source_label"]}
        example={@project["project_kind"] == "example"}
      />

      <section class="exported-pages-heading compact-page-heading">
        <div>
          <p class="eyebrow">Fixed-layout artifact</p>
          <h1>Exported pages</h1>
          <p>{@artifact["source_label"]} · {@artifact["filename"]}</p>
        </div>
        <nav class="inline-actions">
          <a href={"/p/#{@project["key"]}"}>Back to responsive reading</a>
          <a href={"/p/#{@project["key"]}#script-search"}>Confirm a passage by named script search</a>
          <a href={"/p/#{@project["key"]}/exports"}>Exports</a>
        </nav>
      </section>

      <div class="exported-page-controls">
        <a
          href={page_href(@project, @artifact_ref, max(@page - 1, 1))}
          aria-disabled={@page <= 1}
        >Previous page</a>
        <form method="get" action={"/p/#{@project["key"]}/pages/#{@artifact_ref}"}>
          <label>Page
            <input type="number" name="page" min="1" max={@page_count || 1} value={@page} />
          </label>
          <button type="submit">Go</button>
        </form>
        <span :if={@page_count}>Page {@page} of {@page_count}</span>
        <span :if={!@page_count}>Page {@page}; renderer page count unavailable</span>
        <a
          href={page_href(@project, @artifact_ref, next_page(@page, @page_count))}
          aria-disabled={@page_count && @page >= @page_count}
        >Next page</a>
        <a href={"/p/#{@project["key"]}/artifacts/#{@artifact_ref}/download"}>Download PDF</a>
      </div>

      <FountWeb.CoreComponents.alert kind="info" title="Exact artifact, not guessed coordinates">
        This view displays the actual generated PDF. The browser PDF viewer supplies its own zoom and text-selection controls where supported. No responsive-screenplay coordinate is presented as a PDF page mapping. If a passage needs confirmation, use the named screenplay search and page number together.
      </FountWeb.CoreComponents.alert>

      <iframe
        class="exported-pdf-frame"
        title={"#{@project["title"]} exported PDF page #{@page}"}
        src={"/p/#{@project["key"]}/artifacts/#{@artifact_ref}/pdf#page=#{@page}&view=FitH"}
      ></iframe>

      <details class="technical-details">
        <summary>Artifact details</summary>
        <dl>
          <div><dt>Renderer</dt><dd>{get_in(@artifact, ["metadata", "renderer"]) || "not recorded"}</dd></div>
          <div><dt>Verified page map</dt><dd>{get_in(@artifact, ["metadata", "page_map"]) || "unavailable"}</dd></div>
          <div><dt>Built source</dt><dd>{@artifact["source_label"]}</dd></div>
        </dl>
      </details>
    </main>
    """
  end

  defp page_count(artifact) do
    case get_in(artifact, ["metadata", "pages"]) do
      value when is_integer(value) and value > 0 -> value
      _ -> nil
    end
  end

  defp clamp_page(value, page_count) do
    page =
      case value do
        value when is_integer(value) -> value
        value when is_binary(value) ->
          case Integer.parse(value) do
            {number, ""} -> number
            _ -> 1
          end
        _ -> 1
      end

    upper = page_count || max(page, 1)
    page |> max(1) |> min(upper)
  end

  defp next_page(page, nil), do: page + 1
  defp next_page(page, count), do: min(page + 1, count)

  defp page_href(project, artifact_ref, page),
    do: "/p/#{project["key"]}/pages/#{artifact_ref}?page=#{page}"
end
