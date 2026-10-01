defmodule FountWeb.AnalysisLive do
  use FountWeb, :live_view

  @impl true
  def mount(%{"key" => project_key, "task_key" => task_key} = params, _session, socket) do
    owner = socket.assigns.current_owner

    case FountWeb.Store.run_access_by_task_key(Fount.Repo, owner, project_key, task_key) do
      {:ok, access} ->
        run_id = access["run_id"]

        if connected?(socket),
          do: Phoenix.PubSub.subscribe(FountWeb.PubSub, FountWeb.RunEvents.topic(run_id))

        {:ok,
         socket
         |> assign(:run_id, run_id)
         |> assign(:project_key, project_key)
         |> assign(:task_key, task_key)
         |> assign(:task_access, access)
         |> assign(:params, selection_params(params))
         |> assign(:dashboard, nil)
         |> assign(:error, nil)
         |> refresh()}

      _ ->
        {:ok,
         socket |> put_flash(:error, "That analysis task is not available.") |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(:params, selection_params(params)) |> refresh()}
  end

  @impl true
  def handle_info({:run_changed, run_id}, %{assigns: %{run_id: run_id}} = socket),
    do: {:noreply, refresh(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh(socket) do
    case FountWeb.AnalysisDashboard.load(
           Fount.Repo,
           socket.assigns.current_owner,
           socket.assigns.run_id,
           socket.assigns.params
         ) do
      {:ok, dashboard} ->
        assign(socket, dashboard: dashboard, error: nil)

      {:error, :not_found} ->
        socket |> put_flash(:error, "Task not found for this project.") |> redirect(to: "/")

      {:error, reason} ->
        assign(socket, :error, analysis_error(reason))
    end
  end

  defp analysis_error(_),
    do: "Saved analysis could not be loaded. Manual reading and writing are unaffected."

  defp selection_params(params) do
    Map.take(params, ~w(packet left right target))
  end

  defp graph_height(graph) do
    graph.nodes
    |> Enum.map(& &1.y)
    |> Enum.max(fn -> 250 end)
    |> Kernel.+(72)
    |> max(300)
  end

  defp graph_edges(graph) do
    positions = Map.new(graph.nodes, &{&1.id, &1})

    Enum.flat_map(graph.edges, fn edge ->
      with %{x: x1, y: y1} <- positions[edge.from],
           %{x: x2, y: y2} <- positions[edge.to] do
        [Map.merge(edge, %{x1: x1, y1: y1, x2: x2, y2: y2})]
      else
        _ -> []
      end
    end)
  end

  defp packet_label(row) do
    status = row["display_status"] || row["status"] || "not_run"
    playbook = row["playbook"] || "saved analysis"
    "#{status} · #{playbook}"
  end

  defp short(nil), do: "—"

  defp short(value) when is_binary(value) and byte_size(value) > 12,
    do: String.slice(value, 0, 12)

  defp short(value), do: to_string(value)

  defp status_tone(status) when status in ["complete", "current"], do: "complete"
  defp status_tone(status) when status in ["partial", "stale"], do: "partial"
  defp status_tone("failed"), do: "failed"
  defp status_tone(_), do: "not_run"

  defp evidence_id(item), do: item["label"] || item["kind"] || "Saved finding"

  defp evidence_target(item) do
    case item["target"] do
      %{} = target -> "Recorded #{target["kind"] || "source"} target"
      _ -> "target unavailable"
    end
  end

  defp evidence_href(project_key, task_key, selected, item) do
    revision_id = item["revision_id"] || get_in(item, ["target", "revision_id"])
    packet_id = selected.run && selected.run["id"]
    target = item["target"] || %{}

    query =
      URI.encode_query(%{
        "view" => "evidence:#{packet_id}:#{revision_id}",
        "target" => target["id"] || ""
      })

    anchor = if target["kind"] == "scene", do: "scene-", else: "node-"
    "/p/#{project_key}/source/#{task_key}?" <> query <> "#" <> anchor <> (target["id"] || "")
  end

  defp evidence_focus_href(project_key, task_key, selected, item) do
    query =
      %{
        "packet" => selected.run && selected.run["id"],
        "target" => item["evidence_id"] || item["id"] || get_in(item, ["target", "id"])
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    "/p/#{project_key}/analysis/#{task_key}?" <> URI.encode_query(query) <> "#evidence-register"
  end

  defp clear_focus_href(project_key, task_key, selected) do
    query =
      case selected.run && selected.run["id"] do
        nil -> ""
        packet_ref -> "?" <> URI.encode_query(%{"packet" => packet_ref})
      end

    "/p/#{project_key}/analysis/#{task_key}" <> query
  end

  defp cost_label(%{currencies: currencies, unknown_cost_rows: unknown} = item) do
    case currencies do
      [] ->
        "cost unavailable / unitless"

      [currency] when unknown == 0 ->
        "#{currency} #{item.consumed_cost_microunits} µ settled"

      [currency] ->
        "#{currency} #{item.consumed_cost_microunits} µ known settled; cost unknown for #{unknown} row(s)"

      _ ->
        "mixed currencies; no combined cost total"
    end
  end

  defp graph_evidence(node) do
    case List.wrap(node.evidence_ids) do
      [] -> "—"
      ids -> Enum.join(ids, ", ")
    end
  end

  defp lineage_label("analysis_run"), do: "direct analysis packet"
  defp lineage_label("session"), do: "task session"
  defp lineage_label("candidate"), do: "task proposal"
  defp lineage_label("legacy_revision"), do: "legacy task revision"
  defp lineage_label(_), do: "unbound"

  defp value_preview(value) when is_binary(value), do: value
  defp value_preview(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp value_preview(value), do: Jason.encode!(value || %{}, pretty: true)

  @impl true
  def render(assigns) do
    assigns =
      if assigns.dashboard do
        assigns
        |> assign(:graph_height, graph_height(assigns.dashboard.graph))
        |> assign(:graph_edges, graph_edges(assigns.dashboard.graph))
      else
        assigns |> assign(:graph_height, 300) |> assign(:graph_edges, [])
      end

    ~H"""
    <main id="project-analysis" class="analysis-shell project-workspace">
      <FountWeb.CoreComponents.project_header
        project={
          %{"key" => @project_key, "title" => @task_access["title"], "project_kind" => "screenplay"}
        }
        section="work"
        view="reading"
        source_label="Current draft"
      />
      <nav class="task-subnav" aria-label="Task">
        <strong>{@task_access["display_label"] || "Saved task"}</strong>
        <a href={"/p/#{@project_key}/activity/#{@task_key}"}>Activity</a>
        <a href={"/p/#{@project_key}/changes/#{@task_key}"}>Review</a>
        <a href={"/p/#{@project_key}/analysis/#{@task_key}"} aria-current="page">Analysis</a>
        <a href={"/p/#{@project_key}"}>Script</a>
      </nav>

      <FountWeb.CoreComponents.alert :if={@error} kind="error" title="Analysis dashboard">
        {@error}
      </FountWeb.CoreComponents.alert>

      <%= if @dashboard do %>
        <header class="analysis-mast">
          <div class="analysis-mast__title">
            <p class="eyebrow">Script analysis</p>
            <h1>{@dashboard.access["title"]}</h1>
            <p>
              <strong>{@task_access["display_label"] || "Saved task"}</strong>
              · saved evidence for this screenplay
            </p>
          </div>
          <div class="analysis-mast__signals" aria-label="Evidence status">
            <FountWeb.CoreComponents.status_badge
              status={status_tone(@dashboard.selected.state)}
              label={@dashboard.selected.state}
            />
            <span class="signal-chip">{@dashboard.selected.stored_status || "no saved report"}</span>
          </div>
        </header>

        <section class="analysis-strip" aria-label="Analysis state">
          <div>
            <span class="micro-label">saved analysis</span><strong>{@dashboard.selected.stored_status ||
              "not saved"}</strong>
          </div>
          <div>
            <span class="micro-label">playbook</span><strong>{(@dashboard.selected.run &&
                                                                 @dashboard.selected.run["playbook"]) ||
              "—"}</strong>
          </div>
          <details class="technical-details">
            <summary>Technical details</summary>
            <dl>
              <div>
                <dt>Report</dt><dd>
                  <code>{short(@dashboard.selected.packet && @dashboard.selected.packet["id"])}</code>
                </dd>
              </div>
              <div>
                <dt>Analysis run</dt><dd>
                  <code>{short(@dashboard.selected.run && @dashboard.selected.run["id"])}</code>
                </dd>
              </div>
              <div>
                <dt>Revision</dt><dd>
                  <code>{short(@dashboard.selected.run && @dashboard.selected.run["revision_id"])}</code>
                </dd>
              </div>
            </dl>
          </details>
        </section>

        <p class="analysis-state-note">{@dashboard.selected.reason}</p>

        <section
          :if={@dashboard.target.id}
          class={"target-context #{if @dashboard.target.unresolved, do: "target-context--unresolved", else: ""}"}
          aria-live="polite"
        >
          <div>
            <span class="micro-label">finding navigation context</span>
            <strong>{if @dashboard.target.unresolved,
              do: "Recorded target unresolved",
              else: evidence_id(@dashboard.target.evidence)}</strong>
          </div>
          <p :if={@dashboard.target.unresolved}>
            The requested target is not present in this selected saved packet. No evidence was rebound to another revision or element.
          </p>
          <p :if={!@dashboard.target.unresolved}>{evidence_target(@dashboard.target.evidence)}</p>
          <details :if={@dashboard.target.revision_id} class="technical-details">
            <summary>Recorded source identity</summary>
            <p>Revision <code>{@dashboard.target.revision_id}</code></p>
          </details>
          <a href={clear_focus_href(@project_key, @task_key, @dashboard.selected)}>Clear focus</a>
        </section>

        <section class="analysis-layout">
          <aside class="analysis-rail" aria-label="Saved analysis packets">
            <div class="rail-heading">
              <span>Saved analysis</span>
              <strong>{length(@dashboard.history)}</strong>
            </div>
            <form
              action={"/p/#{@project_key}/analysis/#{@task_key}"}
              method="get"
              class="compact-form"
            >
              <label for="analysis-packet">Packet</label>
              <select id="analysis-packet" name="packet">
                <option
                  :for={row <- @dashboard.history}
                  value={row["id"]}
                  selected={@dashboard.selected.run && row["id"] == @dashboard.selected.run["id"]}
                >
                  {packet_label(row)}
                </option>
              </select>
              <button type="submit">Inspect</button>
            </form>

            <details :if={@dashboard.selected.run} class="technical-details">
              <summary>Technical details</summary>
              <dl class="identity-ledger">
                <div>
                  <dt>Revision</dt><dd><code>{@dashboard.selected.run["revision_id"]}</code></dd>
                </div>
                <div>
                  <dt>Candidate</dt><dd>
                    <code>{@dashboard.selected.run["candidate_id"] || "—"}</code>
                  </dd>
                </div>
                <div>
                  <dt>Session</dt><dd><code>{@dashboard.selected.run["session_id"] || "—"}</code></dd>
                </div>
                <div>
                  <dt>Task lineage</dt><dd>
                    {lineage_label(@dashboard.selected.run["lineage_kind"])}
                  </dd>
                </div>
                <div>
                  <dt>Output contract</dt><dd>
                    {@dashboard.selected.run["output_contract_id"] || "legacy / unavailable"}
                  </dd>
                </div>
              </dl>
            </details>

            <div class="rail-note">
              This page shows saved analysis. Browsing or comparing reports does not start AI work or incur new charges.
            </div>
          </aside>

          <div class="analysis-main">
            <section class="analysis-grid analysis-grid--status" aria-label="Check categories">
              <article class="evidence-card evidence-card--required">
                <header>
                  <span class="micro-label">required checks</span><h2>
                    Required checks
                  </h2>
                </header>
                <p :if={@dashboard.checks.required_deterministic == []}>
                  No required task checks are recorded yet.
                </p>
                <ul class="check-list">
                  <li :for={check <- @dashboard.checks.required_deterministic}>
                    <strong>{check["kind"] || check["constraint_id"]}</strong>
                    <span>{check["status"] || "unknown"}</span>
                    <small>{check["message"] || "Saved required check"}</small>
                  </li>
                </ul>
              </article>

              <article class="evidence-card evidence-card--application">
                <header>
                  <span class="micro-label">revision checks</span><h2>
                    Revision checks
                  </h2>
                </header>
                <p :if={@dashboard.checks.workshop_application == []}>
                  No Revision checks are recorded.
                </p>
                <ul class="check-list">
                  <li :for={check <- @dashboard.checks.workshop_application}>
                    <strong>{check["kind"] || check["constraint_id"]}</strong>
                    <span>{check["status"] || "unknown"}</span>
                    <small>{check["message"] || check["evaluation"] ||
                      "deterministic application check"}</small>
                  </li>
                </ul>
              </article>

              <article class="evidence-card evidence-card--advisory">
                <header>
                  <span class="micro-label">story observations</span><h2>Story observations</h2>
                </header>
                <p :if={@dashboard.checks.semantic_advisory == []}>
                  No semantic advisory checks are recorded.
                </p>
                <ul class="check-list">
                  <li :for={check <- @dashboard.checks.semantic_advisory}>
                    <strong>{check["kind"] || check["constraint_id"]}</strong>
                    <span>{check["status"] || "unknown"}</span>
                    <small>Advisory only; never an approval or deterministic pass.</small>
                  </li>
                </ul>
              </article>
            </section>

            <section class="analysis-grid analysis-grid--packet">
              <article class="evidence-card evidence-card--wide">
                <header>
                  <span class="micro-label">writer report</span><h2>Finding & diagnosis</h2>
                </header>
                <p class="lead-finding">
                  {(@dashboard.selected.packet && @dashboard.selected.packet["finding"]) ||
                    "No saved writer finding."}
                </p>
                <div class="diagnosis-stack">
                  <details :for={diagnosis <- @dashboard.selected.diagnoses} class="evidence-detail">
                    <summary>{diagnosis["hypothesis"] || diagnosis["id"] || "Diagnosis"}</summary>
                    <dl>
                      <div>
                        <dt>Concern</dt><dd>{value_preview(diagnosis["concern"])}</dd>
                      </div>
                      <div>
                        <dt>Support</dt><dd>{value_preview(diagnosis["support"] || [])}</dd>
                      </div>
                      <div>
                        <dt>Counterevidence</dt><dd>
                          {value_preview(diagnosis["counterevidence"] || [])}
                        </dd>
                      </div>
                      <div>
                        <dt>Uncertainty</dt><dd>
                          {value_preview(diagnosis["uncertainty"] || "not recorded")}
                        </dd>
                      </div>
                    </dl>
                  </details>
                  <p :if={@dashboard.selected.diagnoses == []}>
                    No diagnosis entries are present in this saved packet.
                  </p>
                </div>
              </article>

              <article class="evidence-card">
                <header>
                  <span class="micro-label">uncertainty</span><h2>What is unknown</h2>
                </header>
                <ul class="plain-list">
                  <li :for={item <- @dashboard.selected.uncertainty}>{value_preview(item)}</li>
                  <li :for={item <- @dashboard.selected.missing_evidence}>
                    Missing: {value_preview(item)}
                  </li>
                </ul>
                <p :if={
                  @dashboard.selected.uncertainty == [] and @dashboard.selected.missing_evidence == []
                }>
                  This report has no recorded uncertainty details.
                </p>
              </article>
            </section>

            <section class="evidence-card" id="evidence-register">
              <header class="section-heading">
                <div>
                  <span class="micro-label">source register</span><h2>Evidence references</h2>
                </div>
                <span>{length(@dashboard.selected.evidence)} references</span>
              </header>
              <p :if={@dashboard.selected.evidence == []}>
                This report has no saved source references.
              </p>
              <div class="evidence-register">
                <article :for={item <- @dashboard.selected.evidence} class="evidence-row">
                  <div>
                    <strong>{evidence_id(item)}</strong>
                    <span>{evidence_target(item)}</span>
                  </div>
                  <blockquote>{item["excerpt"] || "Excerpt not stored in this packet."}</blockquote>
                  <div class="evidence-actions">
                    <a href={evidence_focus_href(@project_key, @task_key, @dashboard.selected, item)}>Focus provenance here</a>
                    <a href={evidence_href(@project_key, @task_key, @dashboard.selected, item)}>Open exact recorded revision target</a>
                  </div>
                </article>
              </div>
            </section>

            <section class="evidence-card graph-card" aria-labelledby="graph-title">
              <header class="section-heading">
                <div>
                  <span class="micro-label">story connections</span><h2 id="graph-title">
                    Evidence graph
                  </h2>
                </div>
                <div class="graph-toolbar" aria-label="Graph zoom controls">
                  <button type="button" data-graph-zoom-out aria-label="Zoom graph out">−</button>
                  <button type="button" data-graph-reset>Reset</button>
                  <button type="button" data-graph-zoom-in aria-label="Zoom graph in">+</button>
                </div>
              </header>
              <p>{@dashboard.graph.explanation}</p>
              <div class="graph-legend" aria-label="Evidence graph legend">
                <span><i class="legend-dot legend-dot--entity"></i>entity / subject</span>
                <span><i class="legend-dot legend-dot--event"></i>event</span>
                <span><i class="legend-dot legend-dot--relation"></i>recorded relation</span>
                <span><i class="legend-line"></i>stored reference</span>
              </div>
              <p :if={@dashboard.graph.truncated} class="warning">
                Showing up to {@dashboard.graph.node_limit} nodes and {@dashboard.graph.edge_limit} links; saved totals are {@dashboard.graph.total_nodes} nodes / {@dashboard.graph.total_edges} links.
              </p>
              <div
                :if={@dashboard.graph.nodes != []}
                class="graph-viewport"
                data-analysis-graph-wrapper
              >
                <svg
                  id="analysis-evidence-graph"
                  phx-hook="AnalysisGraph"
                  tabindex="0"
                  role="img"
                  aria-label="Stored semantic evidence graph. Use plus and minus controls or arrow keys to pan."
                  viewBox={"0 0 840 #{@graph_height}"}
                >
                  <g data-graph-viewport>
                    <line
                      :for={edge <- @graph_edges}
                      x1={edge.x1}
                      y1={edge.y1}
                      x2={edge.x2}
                      y2={edge.y2}
                      class="graph-edge"
                      data-edge-kind={edge.kind}
                    />
                    <g
                      :for={node <- @dashboard.graph.nodes}
                      class={"graph-node graph-node--#{node.kind}"}
                      transform={"translate(#{node.x} #{node.y})"}
                    >
                      <circle r="18" />
                      <text x="28" y="5">{String.slice(node.label || node.id, 0, 44)}</text>
                    </g>
                  </g>
                </svg>
              </div>
              <FountWeb.CoreComponents.empty_state
                :if={@dashboard.graph.nodes == []}
                title="No saved story connections"
                detail="No story connections are saved in this report."
              />

              <details class="evidence-detail technical-details">
                <summary>Accessible graph list</summary>
                <table class="compact-table">
                  <thead>
                    <tr>
                      <th>Type</th><th>Node</th><th>Recorded target</th><th>Revision</th><th>
                        Evidence
                      </th><th>Observation</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={node <- @dashboard.graph.nodes}>
                      <td>{node.kind}</td>
                      <td>{node.label}</td>
                      <td>{value_preview(node.target || %{})}</td>
                      <td><code>{short(node.revision_id)}</code></td>
                      <td>{graph_evidence(node)}</td>
                      <td><code>{short(node.observation_id)}</code></td>
                    </tr>
                  </tbody>
                </table>
                <table class="compact-table" aria-label="Recorded graph links">
                  <thead>
                    <tr>
                      <th>Relation</th><th>From</th><th>To</th><th>Evidence</th><th>Observation</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={edge <- @dashboard.graph.edges}>
                      <td>{edge.label}</td><td>{edge.from}</td><td>{edge.to}</td>
                      <td>{graph_evidence(edge)}</td><td>
                        <code>{short(edge.observation_id)}</code>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </details>

              <div class="event-sequence">
                <h3>Recorded event order</h3>
                <p>Events appear in saved order. This order does not imply cause and effect.</p>
                <ol>
                  <li :for={event <- @dashboard.graph.events}>
                    <span>{event.order}</span>
                    <strong>{event.label}</strong>
                    <small>{if event.evidence_ids == [],
                      do: "no evidence references",
                      else: "#{length(event.evidence_ids)} evidence reference(s)"} · {event.uncertainty ||
                      "uncertainty not recorded"}</small>
                  </li>
                </ol>
                <p :if={@dashboard.graph.events == []}>
                  No events are saved in this report.
                </p>
              </div>
            </section>

            <section class="analysis-grid analysis-grid--resources">
              <article class="evidence-card evidence-card--wide">
                <header>
                  <span class="micro-label">Task accounting</span><h2>Usage & reservations</h2>
                </header>
                <div class="resource-ledger">
                  <div :for={item <- @dashboard.usage.totals} class="resource-row">
                    <strong>{item.resource}</strong>
                    <span>consumed {item.consumed}</span>
                    <span>reserved/open {item.outstanding_reserved}</span>
                    <span>unknown rows {item.unknown_rows}</span>
                    <span>{cost_label(item)}</span>
                  </div>
                </div>
                <p>{@dashboard.usage.note}</p>
              </article>
              <article class="evidence-card">
                <header>
                  <span class="micro-label">recorded usage</span><h2>
                    Backend ceilings
                  </h2>
                </header>
                <dl class="metric-list">
                  <div :for={{resource, value} <- @dashboard.usage.authoritative_resources}>
                    <dt>{resource}</dt>
                    <dd>
                      consumed {value["consumed"]} / limit {value["limit"] || "unlimited / unknown"} · remaining {value[
                        "remaining"
                      ] || "unknown"} · {if value["exhausted"], do: "exhausted", else: "available"}
                    </dd>
                  </div>
                </dl>
                <details :if={map_size(@dashboard.usage.policy_limits) > 0} class="evidence-detail">
                  <summary>Stored policy limits</summary>
                  <dl class="metric-list">
                    <div :for={{key, value} <- @dashboard.usage.policy_limits}>
                      <dt>{key}</dt><dd>{value_preview(value)}</dd>
                    </div>
                  </dl>
                </details>
                <p>Usage indicators are informational. Your configured limits still apply.</p>
              </article>
            </section>

            <section class="evidence-card" id="analysis-comparison">
              <header class="section-heading">
                <div>
                  <span class="micro-label">saved evidence history</span><h2>
                    Comparable analysis delta
                  </h2>
                </div>
                <span>No quality ranking</span>
              </header>
              <form
                action={"/p/#{@project_key}/analysis/#{@task_key}#analysis-comparison"}
                method="get"
                class="comparison-form"
              >
                <input
                  type="hidden"
                  name="packet"
                  value={@dashboard.selected.run && @dashboard.selected.run["id"]}
                />
                <label>
                  Earlier / A
                  <select name="left">
                    <option value="">Choose saved run</option>
                    <option
                      :for={row <- @dashboard.history}
                      value={row["id"]}
                      selected={@params["left"] in [row["id"], row["display_ref"]]}
                    >
                      {packet_label(row)}
                    </option>
                  </select>
                </label>
                <label>
                  Later / B
                  <select name="right">
                    <option value="">Choose saved run</option>
                    <option
                      :for={row <- @dashboard.history}
                      value={row["id"]}
                      selected={@params["right"] in [row["id"], row["display_ref"]]}
                    >
                      {packet_label(row)}
                    </option>
                  </select>
                </label>
                <button type="submit">Compare stored evidence</button>
              </form>

              <div class="comparison-state" data-comparison-state={@dashboard.comparison.state}>
                <strong>{to_string(@dashboard.comparison.state)}</strong>
                <ul :if={@dashboard.comparison.reasons != []}>
                  <li :for={reason <- @dashboard.comparison.reasons}>{reason}</li>
                </ul>
              </div>
              <div :if={@dashboard.comparison.state == :comparable} class="comparison-uncertainty">
                <div>
                  <span class="micro-label">A uncertainty</span><p>
                    {value_preview(@dashboard.comparison.uncertainty.left)}
                  </p>
                </div>
                <div>
                  <span class="micro-label">B uncertainty</span><p>
                    {value_preview(@dashboard.comparison.uncertainty.right)}
                  </p>
                </div>
              </div>
              <table
                :if={
                  @dashboard.comparison.state == :comparable and @dashboard.comparison.deltas != []
                }
                class="compact-table"
              >
                <thead>
                  <tr>
                    <th>Recorded numeric field</th><th>A</th><th>B</th><th>Delta</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={delta <- @dashboard.comparison.deltas}>
                    <td><code>{delta.path}</code></td><td>{delta.before}</td><td>{delta.after}</td><td>
                      {delta.delta}
                    </td>
                  </tr>
                </tbody>
              </table>
              <p :if={
                @dashboard.comparison.state == :comparable and @dashboard.comparison.deltas == []
              }>
                The identities align, but no shared numeric packet fields are available for a factual delta.
              </p>
            </section>

            <section class="evidence-card evidence-card--quiet">
              <header>
                <span class="micro-label">limits & provenance</span><h2>
                  About this analysis
                </h2>
              </header>
              <ul class="plain-list">
                <li>Analysis confidence and advisory findings never grant approval.</li>
                <li>Generation success does not establish analysis completeness.</li>
                <li>
                  Graph links do not invent causality; unresolved targets stay tied to their recorded revision.
                </li>
                <li>Drafts without a saved analysis report have not been analyzed.</li>
              </ul>
            </section>
          </div>
        </section>
      <% end %>
    </main>
    """
  end
end
