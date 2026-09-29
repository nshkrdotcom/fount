defmodule FountWeb.RunLive do
  use FountWeb, :live_view

  @refresh_ms 1_000

  @impl true
  def mount(%{"id" => run_id}, _session, socket) do
    owner = socket.assigns.current_owner

    case FountWeb.Store.run_access(Fount.Repo, owner, run_id) do
      {:ok, access} ->
        {:ok, context} = FountWeb.Actors.owner_context(owner, access["screenplay_id"])

        if connected?(socket) do
          Phoenix.PubSub.subscribe(FountWeb.PubSub, FountWeb.RunEvents.topic(run_id))
          Process.send_after(self(), :refresh, @refresh_ms)
        end

        {:ok,
         socket
         |> assign(:run_id, run_id)
         |> assign(:access, access)
         |> assign(:context, context)
         |> assign(:error, nil)
         |> assign(:notice, nil)
         |> refresh()}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Run not found for this owner.") |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, refresh(socket)}
  end

  def handle_info({:run_changed, run_id}, %{assigns: %{run_id: run_id}} = socket), do: {:noreply, refresh(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("launch", _params, socket) do
    with {:ok, _} <- FountWeb.Store.mark_launched(Fount.Repo, socket.assigns.current_owner, socket.assigns.run_id),
         {:ok, access} <- FountWeb.Store.run_access(Fount.Repo, socket.assigns.current_owner, socket.assigns.run_id),
         {:ok, _pid} <- normalize_started(FountWeb.WorkerSupervisor.start_run(access)) do
      FountWeb.RunEvents.notify(socket.assigns.run_id)
      {:noreply, socket |> assign(:notice, "Durable worker launched.") |> assign(:error, nil) |> refresh()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  def handle_event(action, _params, socket) when action in ["pause", "resume", "stop"] do
    fun = %{"pause" => :pause_run, "resume" => :resume_run, "stop" => :stop_run}[action]
    result = apply(FountRun, fun, [Fount.Repo, socket.assigns.run_id, socket.assigns.context])
    command_result(socket, result, String.capitalize(action) <> " recorded")
  end

  def handle_event("submit_decision", %{"decision" => params}, socket) do
    response =
      %{
        "choice" => params["choice"],
        "context_fingerprint" => params["context_fingerprint"],
        "plan_version" => integer(params["plan_version"]),
        "policy_version" => integer(params["policy_version"])
      }
      |> maybe_put("replacement_fountain", params["replacement_fountain"])

    case FountRun.submit_decision(Fount.Repo, params["id"], response, socket.assigns.context) do
      {:ok, value} ->
        FountWeb.RunEvents.notify(socket.assigns.run_id)
        {:noreply, socket |> assign(:notice, "Decision recorded#{if value["replay"], do: " (idempotent replay)", else: ""}.") |> assign(:error, nil) |> refresh()}

      {:error, reason} when reason in [:stale_decision, :stale_decision_context, :decision_conflict] ->
        {:noreply, socket |> assign(:error, "Decision conflict/stale form: #{inspect(reason)}. Durable state reloaded; review the current decision before resubmitting.") |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  def handle_event("save_policy", %{"policy" => params}, socket) do
    run = socket.assigns.run
    current = get_in(run, ["policy", "policy"]) || %{}
    gates = Map.put(current["gates"] || %{}, "strategy_choice", params["strategy_choice"])
    completion = params["completion"]

    policy =
      current
      |> Map.put("gates", gates)
      |> Map.put("completion", completion)
      |> then(fn policy ->
        if completion == "candidate" do
          policy |> Map.put("approver", nil) |> Map.put("fallback_approver", nil)
        else
          if is_map(policy["approver"]), do: policy, else: Map.put(policy, "approver", %{"type" => "human", "id" => socket.assigns.current_owner})
        end
      end)

    opts = [expected_version: run["current_policy_version"], command_id: "web-policy:" <> Fount.ID.v4()]
    command_result(socket, FountRun.update_policy(Fount.Repo, socket.assigns.run_id, policy, socket.assigns.context, opts), "Policy snapshot updated; affected decisions/work were fenced and refreshed.")
  end

  def handle_event("deliver", %{"export" => params}, socket) do
    opts = [
      artifact_root: Application.fetch_env!(:fount_web, :artifact_root),
      pdf: truthy?(params["pdf"]),
      table_read: truthy?(params["table_read"])
    ]

    destination = Path.join("runs", socket.assigns.run_id)

    case FountRun.deliver(Fount.Repo, socket.assigns.run_id, destination, socket.assigns.context, opts) do
      {:ok, _payload} -> {:noreply, socket |> assign(:notice, "Delivery bundle published.") |> assign(:error, nil) |> refresh()}
      {:partial, reason, _payload} -> {:noreply, socket |> assign(:notice, "Delivery is partial: #{inspect(reason)}. Failed formats remain visible and retryable.") |> assign(:error, nil) |> refresh()}
      {:error, reason} -> {:noreply, assign(socket, :error, "Export failed: #{inspect(reason)}")}
    end
  end

  defp command_result(socket, {:ok, _}, notice) do
    FountWeb.RunEvents.notify(socket.assigns.run_id)
    {:noreply, socket |> assign(:notice, notice) |> assign(:error, nil) |> refresh()}
  end

  defp command_result(socket, {:error, reason}, _notice), do: {:noreply, socket |> assign(:error, inspect(reason)) |> refresh()}

  defp refresh(socket) do
    case FountRun.progress(Fount.Repo, socket.assigns.run_id, socket.assigns.context) do
      {:ok, progress} ->
        run = progress["run"]
        assign(socket, progress: progress, run: run, review: review_data(run, progress))

      {:error, reason} ->
        assign(socket, :error, "Progress unavailable: #{inspect(reason)}")
    end
  end

  defp review_data(run, progress) do
    with {:ok, base} <- Fount.Persistence.load_revision(Fount.Repo, run["screenplay_id"], run["base_revision_id"]),
         candidate_id when is_binary(candidate_id) <- candidate_id(run, progress),
         {:ok, candidate} <- Fount.Persistence.candidate(Fount.Repo, candidate_id) do
      %{
        base: Fount.Screenplay.to_fountain(base, mode: :spec),
        candidate: Fount.Screenplay.to_fountain(candidate["screenplay"], mode: :spec),
        candidate_id: candidate_id,
        diff: inspect(Fount.Screenplay.diff(base, candidate["screenplay"]), pretty: true, limit: :infinity),
        checks: latest_checks(progress),
        provenance: candidate["provenance"] || %{},
        lineage: candidate["lineage"] || [],
        required_checks: candidate["required_checks"] || [],
        check_set_fingerprint: candidate["check_set_fingerprint"],
        result_revision_id: candidate["result_revision_id"]
      }
    else
      _ -> %{base: nil, candidate: nil, candidate_id: nil, diff: nil, checks: [], provenance: %{}, lineage: [], required_checks: [], check_set_fingerprint: nil, result_revision_id: nil}
    end
  end

  defp candidate_id(run, progress) do
    run["selected_candidate_id"] ||
      progress["steps"]
      |> Enum.reverse()
      |> Enum.find_value(fn step -> get_in(step, ["result", "candidate_id"]) end)
  end

  defp latest_checks(progress) do
    progress["steps"]
    |> Enum.reverse()
    |> Enum.find_value([], fn step -> if step["stage"] == "check", do: get_in(step, ["result", "checks"]) || [], else: nil end)
  end

  defp normalize_started({:error, {:already_started, pid}}), do: {:ok, pid}
  defp normalize_started(other), do: other
  defp integer(value) when is_integer(value), do: value
  defp integer(value) when is_binary(value), do: String.to_integer(value)
  defp truthy?(value), do: value in [true, "true", "on", "1"]
  defp maybe_put(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp pending_decisions(progress), do: Enum.filter(progress["decisions"] || [], &(&1["status"] == "pending"))
  defp current_policy(run), do: get_in(run, ["policy", "policy"]) || %{}
  defp current_plan(run), do: run["plan"] || %{}

  defp delivery_identity(delivery) do
    cond do
      is_binary(delivery["accepted_revision_id"]) -> "accepted revision " <> delivery["accepted_revision_id"]
      is_binary(delivery["candidate_id"]) -> "candidate " <> delivery["candidate_id"]
      true -> "recorded run result"
    end
  end

  defp json(value), do: Jason.encode!(value || [], pretty: true)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :pending_decisions, pending_decisions(assigns.progress))
    assigns = assign(assigns, :current_policy, current_policy(assigns.run))
    assigns = assign(assigns, :current_plan, current_plan(assigns.run))

    ~H"""
    <main>
      <nav aria-label="Run">
        <a href={~p"/"}>Projects</a>
        <a href={~p"/runs/#{@run_id}/setup"}>Setup</a>
        <a href={~p"/runs/#{@run_id}/timeline"}>Timeline</a>
        <a href={~p"/runs/#{@run_id}/decisions"}>Decisions <span aria-label="pending decision count">(<%= length(@pending_decisions) %>)</span></a>
        <a href={~p"/runs/#{@run_id}/review"}>Review</a>
        <a href={~p"/runs/#{@run_id}/exports"}>Exports</a>
      </nav>

      <header class="card">
        <h1><%= @access["title"] %></h1>
        <p>Journey <strong><%= @access["journey"] %></strong> · Run <code><%= @run_id %></code></p>
        <p class="status" aria-live="polite">Status: <%= @run["status"] %> · stage: <%= @run["stage"] || "—" %></p>
        <p :if={@notice} role="status"><%= @notice %></p>
        <p :if={@error} role="alert"><%= @error %></p>
      </header>

      <section :if={@live_action == :setup} class="stack">
        <h2>Run setup</h2>
        <p class="warning">Changing gates or completion after work begins appends a new policy snapshot and fences affected work/decisions. Accepted pages can change canon; candidate completion cannot.</p>
        <div class="grid">
          <div class="card"><h3>Goal</h3><p><%= @current_plan["goal"] %></p></div>
          <div class="card"><h3>Scope</h3><pre><%= json(@current_plan["scope"]) %></pre></div>
          <div class="card"><h3>Constraints</h3><pre><%= json(@current_plan["constraints"]) %></pre></div>
          <div class="card"><h3>Protected passages</h3><pre><%= json(@current_plan["protected_material"]) %></pre></div>
        </div>
        <div class="card">
          <h3>Effective limits and estimates</h3>
          <pre><%= json(@current_policy["limits"]) %></pre>
          <p>Estimated cost: unknown unless the configured provider supplies an estimate. Incurred usage is shown on the timeline and is never synthesized as zero.</p>
          <p>Base revision <code><%= @current_plan["base_revision_id"] %></code> · plan v<%= @run["current_plan_version"] %> · policy v<%= @run["current_policy_version"] %>.</p>
        </div>
        <form phx-submit="save_policy" class="card stack">
          <label>Strategy gate
            <select name="policy[strategy_choice]">
              <option value="human" selected={get_in(@current_policy, ["gates", "strategy_choice"]) == "human"}>Human decision</option>
              <option value="automatic" selected={get_in(@current_policy, ["gates", "strategy_choice"]) == "automatic"}>Automatic</option>
            </select>
          </label>
          <label>Completion
            <select name="policy[completion]">
              <option value="candidate" selected={@current_policy["completion"] == "candidate"}>Candidate only — canon unchanged</option>
              <option value="accept" selected={@current_policy["completion"] == "accept"}>Accept — exact approver may change canon</option>
            </select>
          </label>
          <p>Configured approver: <code><%= inspect(@current_policy["approver"]) %></code></p>
          <button type="submit">Save policy snapshot</button>
        </form>
        <div class="card"><button phx-click="launch">Launch / resume durable worker</button></div>
      </section>

      <section :if={@live_action == :timeline} class="stack">
        <h2>Durable timeline and controls</h2>
        <div class="card">
          <button phx-click="pause">Pause</button>
          <button phx-click="resume">Resume</button>
          <button phx-click="stop">Stop</button>
          <button phx-click="launch">Ensure worker is running</button>
        </div>
        <p>Progress is reloaded from PostgreSQL every second and after PubSub wakeups. Socket or worker loss does not own correctness.</p>
        <p>Current scope: <code><%= json(@current_plan["scope"]) %></code></p>
        <p :if={@run["pause_requested_at"]}>Pause requested at <%= @run["pause_requested_at"] %>; any already-dispatched provider call is settling before another dispatch.</p>
        <p :if={@run["stop_requested_at"]}>Stop requested at <%= @run["stop_requested_at"] %>; already-persisted partial results remain available and no new dispatch may start.</p>
        <table>
          <thead><tr><th>Stage</th><th>Status</th><th>Iteration</th><th>Result</th></tr></thead>
          <tbody>
            <tr :for={step <- @progress["steps"] || []}>
              <td><%= step["stage"] %></td><td><%= step["status"] %></td><td><%= step["iteration"] %></td><td><code><%= inspect(step["result"], limit: 8) %></code></td>
            </tr>
          </tbody>
        </table>
        <div class="grid">
          <div class="card"><h3>Usage / incurred cost</h3><pre><%= json(@progress["usage"]) %></pre><p>Missing provider cost remains unknown; it is not displayed as zero.</p></div>
          <div class="card"><h3>Provider requests / partial work</h3><pre><%= json(@progress["provider_requests"]) %></pre></div>
          <div class="card"><h3>Approval attempts / recorded identity</h3><pre><%= json(@progress["approval_attempts"]) %></pre></div>
        </div>
      </section>

      <section :if={@live_action == :decisions} class="stack">
        <h2>Decision inbox</h2>
        <p>Every form submits the exact persisted context fingerprint plus plan/policy versions. Your identity is reconstructed from the signed server session, never from browser fields.</p>
        <p :if={@pending_decisions == []}>No pending decisions.</p>
        <article :for={decision <- @pending_decisions} class="card">
          <h3><%= decision["kind"] %></h3>
          <p>Decision <code><%= decision["id"] %></code></p>
          <p><strong>Question:</strong> <%= decision["prompt"] %></p>
          <p>Fingerprint <code><%= decision["context_fingerprint"] %></code></p>
          <div class="grid">
            <div><h4>Available choices and consequences</h4><pre><%= json(decision["options"]) %></pre></div>
            <div><h4>Exact evidence binding</h4><pre><%= json(Map.take(decision, ["candidate_id", "base_revision_id", "content_hash", "check_set_fingerprint", "plan_version", "policy_version"])) %></pre></div>
          </div>
          <p>Safe default: leave this checkpoint pending when the evidence is insufficient; the host never chooses on behalf of a human checkpoint.</p>
          <form :for={option <- decision["options"] || []} phx-submit="submit_decision">
            <input type="hidden" name="decision[id]" value={decision["id"]} />
            <input type="hidden" name="decision[context_fingerprint]" value={decision["context_fingerprint"]} />
            <input type="hidden" name="decision[plan_version]" value={decision["plan_version"]} />
            <input type="hidden" name="decision[policy_version]" value={decision["policy_version"]} />
            <input type="hidden" name="decision[choice]" value={option["id"] || option["value"] || option["choice"]} />
            <label :if={(option["id"] || option["value"]) == "replace"}>Replacement Fountain
              <textarea name="decision[replacement_fountain]" placeholder="Paste the complete replacement Fountain source for a new checked candidate"></textarea>
            </label>
            <button type="submit"><%= option["title"] || option["label"] || option["id"] || option["value"] %></button>
          </form>
        </article>
      </section>

      <section :if={@live_action == :review} class="stack">
        <h2>Side-by-side candidate review</h2>
        <p :if={is_nil(@review.candidate)}>No candidate has been persisted yet. Generated pages cannot appear before the configured strategy gate is resolved.</p>
        <div :if={@review.candidate} class="grid">
          <div><h3>Canonical base</h3><pre class="script"><%= @review.base %></pre></div>
          <div><h3>Candidate <code><%= @review.candidate_id %></code></h3><pre class="script"><%= @review.candidate %></pre></div>
        </div>
        <div :if={@review.candidate} class="card"><h3>Actual structural diff</h3><pre><%= @review.diff %></pre></div>
        <div :if={@review.candidate} class="grid">
          <div class="card"><h3>Provenance and lineage</h3><pre><%= json(%{"provenance" => @review.provenance, "lineage" => @review.lineage, "result_revision_id" => @review.result_revision_id}) %></pre></div>
          <div class="card"><h3>Required check identity</h3><pre><%= json(%{"required_checks" => @review.required_checks, "check_set_fingerprint" => @review.check_set_fingerprint}) %></pre></div>
        </div>
        <div class="card"><h3>Checks and override evidence</h3><pre><%= json(@review.checks) %></pre><p>Unknown, failed and uninspected checks remain visible; absence is not converted into a pass. Any permitted override remains part of the persisted decision/approval record rather than being hidden here.</p></div>
        <p :if={@review.candidate}>Candidate selection and acceptance are explicit persisted decisions. <a href={~p"/runs/#{@run_id}/decisions"}>Open the current decision inbox</a>; this review page never accepts pages implicitly.</p>
      </section>

      <section :if={@live_action == :exports} class="stack">
        <h2>Exports</h2>
        <form phx-submit="deliver" class="card stack">
          <label><input type="checkbox" name="export[pdf]" value="true" /> Include PDF (requires configured renderer and Poppler checks)</label>
          <label><input type="checkbox" name="export[table_read]" value="true" /> Include table-read bundle</label>
          <button type="submit">Publish / retry bundle</button>
        </form>
        <table>
          <thead><tr><th>Format</th><th>Content identity</th><th>State</th><th>Checksum / error</th><th>Download</th></tr></thead>
          <tbody>
            <tr :for={delivery <- @progress["deliveries"] || []}>
              <td><%= delivery["format"] %></td>
              <td><%= delivery_identity(delivery) %></td>
              <td><%= delivery["state"] %></td>
              <td><code><%= delivery["output_checksum"] || delivery["error"] || "unknown" %></code></td>
              <td><a :if={delivery["state"] == "ready"} href={~p"/artifacts/#{@run_id}/#{delivery["id"]}"}>Download</a></td>
            </tr>
          </tbody>
        </table>
      </section>
    </main>
    """
  end
end
