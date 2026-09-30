defmodule FountWeb.RunLive do
  use FountWeb, :live_view

  alias Fount.Writing.Principal

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
         |> assign(:live_connected, connected?(socket))
         |> assign(:run_id, run_id)
         |> assign(:access, access)
         |> assign(:context, context)
         |> assign(:error, nil)
         |> assign(:notice, nil)
         |> assign(:notification_read_ids, MapSet.new())
         |> assign(:notifications, [])
         |> assign(:unread_notifications, [])
         |> assign(:launch_preview, nil)
         |> assign(:launch_results, nil)
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

  def handle_info({:run_changed, run_id}, %{assigns: %{run_id: run_id}} = socket),
    do: {:noreply, refresh(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("launch", _params, socket) do
    with {:ok, _} <-
           FountWeb.Store.mark_launched(
             Fount.Repo,
             socket.assigns.current_owner,
             socket.assigns.run_id
           ),
         {:ok, access} <-
           FountWeb.Store.run_access(
             Fount.Repo,
             socket.assigns.current_owner,
             socket.assigns.run_id
           ),
         {:ok, _pid} <- normalize_started(FountWeb.WorkerSupervisor.start_run(access)) do
      FountWeb.RunEvents.notify(socket.assigns.run_id)

      {:noreply,
       socket |> assign(:notice, "Durable worker launched.") |> assign(:error, nil) |> refresh()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  def handle_event(action, _params, socket) when action in ["pause", "resume"] do
    fun = %{"pause" => :pause_run, "resume" => :resume_run}[action]
    result = apply(FountRun, fun, [Fount.Repo, socket.assigns.run_id, socket.assigns.context])
    command_result(socket, result, String.capitalize(action) <> " recorded")
  end

  def handle_event("stop", %{"control" => %{"confirm_stop" => value}}, socket)
      when value in ["true", "on", "1"] do
    command_result(
      socket,
      FountRun.stop_run(Fount.Repo, socket.assigns.run_id, socket.assigns.context),
      "Stop requested. No new work or decisions will start."
    )
  end

  def handle_event("stop", _params, socket),
    do: {:noreply, assign(socket, :error, "Confirm that you want to stop this Run.")}

  def handle_event("submit_decision", %{"decision" => %{"choice" => "stop"} = params}, socket)
      when not is_map_key(params, "confirm_stop"),
      do: {:noreply, assign(socket, :error, "Confirm that you want to stop this Run.")}

  def handle_event(
        "submit_decision",
        %{"decision" => %{"choice" => "stop", "confirm_stop" => value}},
        socket
      )
      when value not in ["true", "on", "1"],
      do: {:noreply, assign(socket, :error, "Confirm that you want to stop this Run.")}

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

        {:noreply,
         socket
         |> assign(
           :notice,
           "Decision recorded#{if value["replay"], do: " (idempotent replay)", else: ""}."
         )
         |> assign(:error, nil)
         |> refresh()}

      {:error, reason}
      when reason in [:stale_decision, :stale_decision_context, :decision_conflict] ->
        {:noreply,
         socket
         |> assign(
           :error,
           "Decision conflict/stale form: #{inspect(reason)}. Durable state reloaded; review the current decision before resubmitting."
         )
         |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  def handle_event("save_policy", %{"policy" => params}, socket) do
    case FountWeb.WorkflowManagement.policy_from_form(
           params,
           socket.assigns.context,
           socket.assigns.current_owner
         ) do
      {:ok, policy, _fingerprint} ->
        opts = [
          expected_version: socket.assigns.run["current_policy_version"],
          command_id: "web-policy:" <> Fount.ID.v4()
        ]

        command_result(
          socket,
          FountRun.update_policy(
            Fount.Repo,
            socket.assigns.run_id,
            policy,
            socket.assigns.context,
            opts
          ),
          "Run settings saved; prior-version work and decisions were fenced and refreshed."
        )

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Policy rejected by the server: #{inspect(reason)}")
         |> refresh()}
    end
  end

  def handle_event("save_current_preset", %{"preset" => %{"name" => name}}, socket) do
    case FountWeb.WorkflowManagement.save_preset(
           Fount.Repo,
           socket.assigns.current_owner,
           name,
           current_policy(socket.assigns.run),
           socket.assigns.context
         ) do
      {:ok, row} ->
        {:noreply,
         socket
         |> assign(:notice, "Saved preset #{row["name"]} v#{row["version"]}.")
         |> assign(:error, nil)
         |> refresh()}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, "Preset not saved: #{inspect(reason)}") |> refresh()}
    end
  end

  def handle_event("apply_preset", %{"reference" => reference}, socket) do
    case FountWeb.WorkflowManagement.find_preset(
           Fount.Repo,
           socket.assigns.current_owner,
           reference,
           socket.assigns.context
         ) do
      {:ok, preset} ->
        opts = [
          expected_version: socket.assigns.run["current_policy_version"],
          command_id: "web-preset:" <> Fount.ID.v4()
        ]

        command_result(
          socket,
          FountRun.update_policy(
            Fount.Repo,
            socket.assigns.run_id,
            preset["policy"],
            socket.assigns.context,
            opts
          ),
          "Preset #{preset["name"]} v#{preset["version"]} loaded as a new policy snapshot."
        )

      {:error, reason} ->
        {:noreply, socket |> assign(:error, "Preset rejected: #{inspect(reason)}") |> refresh()}
    end
  end

  def handle_event("update_plan", %{"plan" => %{"goal" => goal}}, socket) do
    case FountWeb.WorkflowManagement.plan_update(current_plan(socket.assigns.run), goal) do
      {:ok, plan} ->
        opts = [
          expected_version: socket.assigns.run["current_plan_version"],
          command_id: "web-plan:" <> Fount.ID.v4(),
          reason: "owner_goal_update"
        ]

        command_result(
          socket,
          FountRun.update_plan(
            Fount.Repo,
            socket.assigns.run_id,
            plan,
            socket.assigns.context,
            opts
          ),
          "Plan snapshot updated on the same base and scope; prior-version work was fenced."
        )

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Plan update rejected: #{inspect(reason)}")}
    end
  end

  def handle_event("preview_workflow_launch", %{"workflow" => params}, socket) do
    with %{} = selection_row <- socket.assigns.workflow_selection,
         {:ok, model} <-
           Fount.Persistence.load_revision(
             Fount.Repo,
             socket.assigns.run["screenplay_id"],
             get_in(socket.assigns.run, ["plan", "base_revision_id"])
           ),
         {:ok, preview} <-
           FountWeb.WorkflowManagement.launch_preview(
             model,
             params["action"],
             params["instruction"],
             selection_row["selection"],
             current_policy(socket.assigns.run),
             truthy?(params["multi_launch"])
           ) do
      {:noreply,
       socket
       |> assign(:launch_preview, preview)
       |> assign(:launch_results, nil)
       |> assign(
         :notice,
         "Launch preview validated. Confirm to create the listed independent Runs."
       )
       |> assign(:error, nil)}
    else
      nil ->
        {:noreply,
         assign(socket, :error, "Select and save a valid workflow scope in the Viewer first.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Launch preview rejected: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "confirm_workflow_launch",
        _params,
        %{assigns: %{launch_preview: preview}} = socket
      )
      when is_map(preview) do
    results =
      FountWeb.WorkflowManagement.execute_launch_preview(
        socket.assigns.current_owner,
        socket.assigns.access["project_id"],
        preview
      )

    summary = FountWeb.WorkflowManagement.launch_summary(results)

    message =
      "Created/replayed #{length(summary["created"])} Run(s); #{length(summary["failed"])} failed. Retry uses the same per-scope idempotency keys."

    {:noreply,
     socket
     |> assign(:launch_results, summary)
     |> assign(:notice, message)
     |> assign(
       :error,
       if(summary["failed"] == [],
         do: nil,
         else: "Some launches failed; successful Run IDs are preserved and retry-safe."
       )
     )}
  end

  def handle_event("confirm_workflow_launch", _params, socket),
    do: {:noreply, assign(socket, :error, "No validated launch preview is active.")}

  def handle_event("mark_notifications_read", _params, socket) do
    ids = MapSet.new(Enum.map(socket.assigns.notifications, & &1["id"]))

    {:noreply,
     socket
     |> assign(:notification_read_ids, MapSet.union(socket.assigns.notification_read_ids, ids))
     |> assign(:unread_notifications, [])}
  end

  def handle_event("deliver", params, socket) do
    selected = Map.get(params, "export", %{})

    opts = [
      artifact_root: Application.fetch_env!(:fount_web, :artifact_root),
      pdf: truthy?(selected["pdf"]),
      table_read: truthy?(selected["table_read"])
    ]

    destination = Path.join("runs", socket.assigns.run_id)

    case FountRun.deliver(
           Fount.Repo,
           socket.assigns.run_id,
           destination,
           socket.assigns.context,
           opts
         ) do
      {:ok, _payload} ->
        {:noreply,
         socket
         |> assign(:notice, "Delivery bundle published.")
         |> assign(:error, nil)
         |> refresh()}

      {:partial, reason, _payload} ->
        {:noreply,
         socket
         |> assign(
           :notice,
           "Delivery is partial: #{inspect(reason)}. Failed formats remain visible and retryable."
         )
         |> assign(:error, nil)
         |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Export failed: #{inspect(reason)}")}
    end
  end

  defp command_result(socket, {:ok, _}, notice) do
    FountWeb.RunEvents.notify(socket.assigns.run_id)
    {:noreply, socket |> assign(:notice, notice) |> assign(:error, nil) |> refresh()}
  end

  defp command_result(socket, {:error, reason}, _notice),
    do: {:noreply, socket |> assign(:error, inspect(reason)) |> refresh()}

  defp refresh(socket) do
    case {FountRun.progress(Fount.Repo, socket.assigns.run_id, socket.assigns.context),
          FountRun.get_run(Fount.Repo, socket.assigns.run_id, socket.assigns.context)} do
      {{:ok, progress}, {:ok, run}} ->
        workflow_selection =
          case FountWeb.WorkflowManagement.load_selection(
                 Fount.Repo,
                 socket.assigns.current_owner,
                 run,
                 socket.assigns.context
               ) do
            {:ok, row} -> row
            {:error, _} -> nil
          end

        notifications = FountWeb.WorkflowManagement.notifications(run, progress)
        read_ids = socket.assigns.notification_read_ids
        unread_notifications = Enum.reject(notifications, &MapSet.member?(read_ids, &1["id"]))

        export_preview =
          case FountWeb.WorkflowManagement.export_preview(
                 Fount.Repo,
                 run,
                 progress,
                 socket.assigns.context
               ) do
            {:ok, preview} -> preview
            {:error, reason} -> %{"available" => false, "reason" => inspect(reason)}
          end

        assign(socket,
          progress: progress,
          run: run,
          review: review_data(run, progress),
          analysis_service: FountWeb.Services.analysis_service_summary(),
          workflow_selection: workflow_selection,
          policy_presets:
            FountWeb.WorkflowManagement.presets(
              Fount.Repo,
              socket.assigns.current_owner,
              socket.assigns.context
            ),
          policy_principals: FountWeb.Actors.policy_principals(socket.assigns.current_owner),
          policy_reviewers: FountWeb.Actors.policy_reviewers(socket.assigns.current_owner),
          workflow_actions: FountWeb.WorkflowManagement.action_catalog(),
          enabled_workflow_actions: FountWeb.WorkflowManagement.enabled_actions(),
          lifecycle: FountWeb.WorkflowManagement.lifecycle(run),
          notifications: notifications,
          unread_notifications: unread_notifications,
          export_preview: export_preview
        )

      {{:error, reason}, _} ->
        assign(socket, :error, "Progress unavailable: #{inspect(reason)}")

      {_, {:error, reason}} ->
        assign(socket, :error, "Progress unavailable: #{inspect(reason)}")
    end
  end

  defp review_data(run, progress) do
    analysis = analysis_snapshot(progress)

    with {:ok, base} <-
           Fount.Persistence.load_revision(
             Fount.Repo,
             run["screenplay_id"],
             get_in(run, ["plan", "base_revision_id"])
           ),
         candidate_id when is_binary(candidate_id) <- candidate_id(run, progress),
         {:ok, candidate} <- Fount.Persistence.candidate(Fount.Repo, candidate_id) do
      checks = latest_checks(progress)

      %{
        base: Fount.Screenplay.to_fountain(base, mode: :spec),
        base_model: base,
        candidate: Fount.Screenplay.to_fountain(candidate["screenplay"], mode: :spec),
        candidate_model: candidate["screenplay"],
        candidate_id: candidate_id,
        checks: checks,
        advisory_checks: Enum.filter(checks, &(&1["severity"] == "advisory")),
        required_run_checks: Enum.filter(checks, &(&1["severity"] == "required")),
        other_checks: Enum.reject(checks, &(&1["severity"] in ["advisory", "required"])),
        pre_analysis: analysis.writer,
        revision_analysis: analysis.revision,
        provenance: candidate["provenance"] || %{},
        lineage: candidate["lineage"] || [],
        required_checks: candidate["required_checks"] || [],
        check_set_fingerprint: candidate["check_set_fingerprint"],
        result_revision_id: candidate["result_revision_id"],
        analysis_binding: FountWeb.AnalysisDashboard.review_binding(Fount.Repo, run, progress)
      }
    else
      _ ->
        %{
          base: nil,
          base_model: nil,
          candidate: nil,
          candidate_model: nil,
          candidate_id: nil,
          checks: [],
          advisory_checks: [],
          required_run_checks: [],
          other_checks: [],
          pre_analysis: analysis.writer,
          revision_analysis: analysis.revision,
          provenance: %{},
          lineage: [],
          required_checks: [],
          check_set_fingerprint: nil,
          result_revision_id: nil,
          analysis_binding: FountWeb.AnalysisDashboard.review_binding(Fount.Repo, run, progress)
        }
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
    |> Enum.find_value([], fn step ->
      if step["stage"] == "check", do: get_in(step, ["result", "checks"]) || [], else: nil
    end)
  end

  defp analysis_snapshot(progress) do
    %{
      writer: latest_analysis(progress, "writer", ["investigate", "plan"]),
      revision: latest_analysis(progress, "revision", ["write", "iterate", "check"])
    }
  end

  defp latest_analysis(progress, key, stages) do
    summary =
      progress["analysis"]
      |> List.wrap()
      |> Enum.reverse()
      |> Enum.find_value(fn item -> if is_map(item), do: item[key] end)

    if is_map(summary) do
      summary
    else
      step =
        progress["steps"]
        |> List.wrap()
        |> Enum.reverse()
        |> Enum.find(&(&1["stage"] in stages))

      if is_map(step) and step["status"] in ["failed", "error"] do
        %{
          "status" => "failed",
          "reason" => step["error_category"] || "stage_failed_before_analysis_summary"
        }
      else
        %{"status" => "not_run", "reason" => "analysis_not_recorded"}
      end
    end
  end

  defp analysis_status(%{"status" => "not_run"}), do: "not-run"
  defp analysis_status(%{"status" => status}) when is_binary(status), do: status
  defp analysis_status(_), do: "not-run"

  defp normalize_started({:error, {:already_started, pid}}), do: {:ok, pid}
  defp normalize_started(other), do: other
  defp integer(value) when is_integer(value), do: value
  defp integer(value) when is_binary(value), do: String.to_integer(value)
  defp truthy?(value), do: value in [true, "true", "on", "1"]
  defp maybe_put(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp pending_decisions(progress),
    do: Enum.filter(progress["decisions"] || [], &(&1["status"] == "pending"))

  defp current_policy(run), do: get_in(run, ["policy", "policy"]) || %{}
  defp current_plan(run), do: run["plan"] || %{}

  defp delivery_identity(delivery) do
    cond do
      is_binary(delivery["accepted_revision_id"]) ->
        "accepted revision " <> delivery["accepted_revision_id"]

      is_binary(delivery["candidate_id"]) ->
        "candidate " <> delivery["candidate_id"]

      true ->
        "recorded run result"
    end
  end

  defp delivery_previewable?(delivery),
    do:
      delivery["state"] == "ready" and
        delivery["format"] in ~w(fountain fdx review_json review_markdown source_diff structural_diff resources_checks provenance table_read_json table_read_html)

  defp policy_principal_key(policy, options) do
    approver = policy["approver"]

    Enum.find_value(options, "owner", fn option ->
      if Principal.to_map(option["principal"]) == approver, do: option["key"]
    end)
  end

  defp policy_route_rule(policy),
    do: get_in(policy, ["route_choice", "rule"]) || "pause_on_material_tradeoff"

  defp policy_reviewer_key(policy, options) do
    reviewer_id = get_in(policy, ["route_choice", "reviewer_id"])

    Enum.find_value(options, "owner", fn option ->
      if option["reviewer_id"] == reviewer_id, do: option["key"]
    end)
  end

  defp limit_value(policy, key, default), do: get_in(policy, ["limits", key]) || default
  defp money_value(policy, key), do: get_in(policy, ["limits", "money", key])

  defp json(value), do: Jason.encode!(value || [], pretty: true)

  @impl true
  def render(assigns) do
    pending = pending_decisions(assigns.progress)

    decision_contexts =
      Map.new(pending, fn decision ->
        {decision["id"],
         FountWeb.WorkflowManagement.decision_context(
           assigns.progress,
           decision,
           assigns.review.analysis_binding
         )}
      end)

    assigns = assign(assigns, :pending_decisions, pending)
    assigns = assign(assigns, :decision_contexts, decision_contexts)
    assigns = assign(assigns, :current_policy, current_policy(assigns.run))
    assigns = assign(assigns, :current_plan, current_plan(assigns.run))

    ~H"""
    <main class="run-shell">
      <p :if={!@live_connected} role="status">Connecting live controls…</p>
      <nav class="context-nav" aria-label="Run">
        <a href={~p"/"}>Projects</a>
        <a href={~p"/runs/#{@run_id}/setup"}>Setup</a>
        <a href={~p"/runs/#{@run_id}/timeline"}>Timeline</a>
        <a href={~p"/runs/#{@run_id}/decisions"}>Decisions
        <span aria-label="pending decision count">({length(@pending_decisions)})</span></a>
        <a href={~p"/runs/#{@run_id}/review"}>Review</a>
        <a href={~p"/runs/#{@run_id}/analysis"}>Intelligence</a>
        <a href={~p"/runs/#{@run_id}/viewer"}>Viewer</a>
        <a href={~p"/runs/#{@run_id}/edit"}>Editor</a>
        <a href={~p"/runs/#{@run_id}/exports"}>Exports</a>
      </nav>

      <header class="card">
        <h1>{@access["title"]}</h1>
        <p>Journey <strong>{@access["journey"]}</strong> · Run <code>{@run_id}</code></p>
        <p class="status" aria-live="polite">
          Status: {@run["status"]} · stage: {@run["stage"] || "—"}
        </p>
        <p :if={@notice} role="status">{@notice}</p>
        <p :if={@error} role="alert">{@error}</p>
      </header>

      <details class="card notification-panel" open={@unread_notifications != []}>
        <summary>Session notifications · {length(@unread_notifications)} unread</summary>
        <p>
          Notices refresh from saved work when you reconnect. Read and unread marks apply to this browser session.
        </p>
        <p :if={@notifications == []}>Nothing needs your attention.</p>
        <ul :if={@notifications != []} class="notification-list">
          <li :for={item <- @notifications}>
            <strong>[{item["kind"]}] {item["title"]}</strong> — {item["detail"]}
            <span :if={Enum.any?(@unread_notifications, &(&1["id"] == item["id"]))}> · unread</span>
          </li>
        </ul>
        <button
          :if={@unread_notifications != []}
          type="button"
          phx-click="mark_notifications_read"
          disabled={!@live_connected}
        >Mark current notices read</button>
      </details>

      <section :if={@live_action == :setup} class="stack">
        <h2>Run setup</h2>
        <p class="warning">
          Proposed pages replace the approved screenplay only after your approval.
          Changing settings creates a saved version and prevents affected work from continuing with old settings.
        </p>

        <div class="grid">
          <div class="card">
            <p class="eyebrow">Plan snapshot</p>
            <h3>Goal</h3><p>{@current_plan["goal"]}</p>
            <p>
              Version <strong>{@run["current_plan_version"]}</strong>
              · version reference
              <code>{get_in(@run, ["plan", "fingerprint"]) || "recorded in Run lineage"}</code>
            </p>
          </div>
          <div class="card">
            <h3>Exact scope</h3><pre><%= json(@current_plan["scope"]) %></pre>
            <p>Base revision <code>{@current_plan["base_revision_id"]}</code></p>
          </div>
          <div class="card">
            <h3>Constraints</h3><pre><%= json(@current_plan["constraints"]) %></pre>
          </div>
          <div class="card">
            <h3>Protected passages</h3><pre><%= json(@current_plan["protected_material"]) %></pre>
          </div>
        </div>

        <form phx-submit="update_plan" class="card stack">
          <h3>Update plan goal</h3>
          <p>
            Update the goal for the selected screenplay and material. To change the selection, start a new Run.
          </p>
          <label>Goal <textarea name="plan[goal]" maxlength="2000"><%= @current_plan["goal"] %></textarea></label>
          <button disabled={!@live_connected || !@lifecycle["update_plan"]} type="submit">Save plan changes</button>
        </form>

        <form phx-submit="save_policy" class="card stack policy-form">
          <div>
            <p class="eyebrow">Run settings</p>
            <h3>Review steps, completion and limits</h3>
            <p>
              Policy v{@run["current_policy_version"]} · version reference
              <code>{get_in(@run, ["policy", "fingerprint"]) || "recorded"}</code>
            </p>
          </div>
          <div class="policy-grid">
            <label :for={
              gate <- ~w(investigation_scope strategy_choice candidate_generation iteration)
            }>
              {String.replace(gate, "_", " ")}
              <select name={"policy[#{gate}]"}>
                <option value="human" selected={get_in(@current_policy, ["gates", gate]) == "human"}>
                  Human checkpoint
                </option>
                <option
                  value="automatic"
                  selected={get_in(@current_policy, ["gates", gate]) == "automatic"}
                >
                  Automatic
                </option>
              </select>
            </label>
            <label>
              Completion
              <select name="policy[completion]">
                <option value="candidate" selected={@current_policy["completion"] == "candidate"}>
                  Proposed changes — approval required
                </option>
                <option value="accept" selected={@current_policy["completion"] == "accept"}>
                  Accept — exact approver required
                </option>
              </select>
            </label>
            <label>
              Trusted approver
              <select name="policy[approver]">
                <option
                  :for={option <- @policy_principals}
                  value={option["key"]}
                  selected={
                    policy_principal_key(@current_policy, @policy_principals) == option["key"]
                  }
                >
                  {option["label"]}
                </option>
              </select>
            </label>
            <label class="inline-check"><input
              type="checkbox"
              name="policy[owner_fallback_enabled]"
              value="true"
              checked={not is_nil(@current_policy["fallback_approver"])}
            /> Use authenticated owner as fallback approver</label>
            <label>
              Route
              <select name="policy[route_choice]">
                <option
                  value="pause_on_material_tradeoff"
                  selected={policy_route_rule(@current_policy) == "pause_on_material_tradeoff"}
                >
                  Pause on material tradeoff
                </option>
                <option
                  value="registered_reviewer"
                  selected={policy_route_rule(@current_policy) == "registered_reviewer"}
                >
                  Route to registered human reviewer
                </option>
              </select>
            </label>
            <label>
              Registered route reviewer
              <select name="policy[route_reviewer_key]">
                <option
                  :for={option <- @policy_reviewers}
                  value={option["key"]}
                  selected={policy_reviewer_key(@current_policy, @policy_reviewers) == option["key"]}
                >
                  {option["label"]}
                </option>
              </select>
            </label>
          </div>
          <fieldset>
            <legend>Resource ceilings</legend>
            <div class="policy-grid">
              <label>Iterations
              <input
                type="number"
                min="0"
                name="policy[max_iterations]"
                value={limit_value(@current_policy, "max_iterations", 3)}
              /></label>
              <label>Malformed repairs/call
              <input
                type="number"
                min="0"
                name="policy[max_malformed_repairs_per_call]"
                value={limit_value(@current_policy, "max_malformed_repairs_per_call", 1)}
              /></label>
              <label>Transient retries
              <input
                type="number"
                min="0"
                name="policy[max_transient_retries]"
                value={limit_value(@current_policy, "max_transient_retries", 2)}
              /></label>
              <label>Inference calls
              <input
                type="number"
                min="0"
                name="policy[max_inference_calls]"
                value={limit_value(@current_policy, "max_inference_calls", 12)}
              /></label>
              <label>Measurement states
              <input
                type="number"
                min="0"
                name="policy[max_measurement_states]"
                value={limit_value(@current_policy, "max_measurement_states", 500)}
              /></label>
            </div>
            <label class="inline-check"><input
              type="checkbox"
              name="policy[money_enabled]"
              value="true"
              checked={not is_nil(get_in(@current_policy, ["limits", "money"]))}
            /> Enable money ceiling</label>
            <div class="policy-grid">
              <label>Currency
              <input
                name="policy[currency]"
                maxlength="3"
                value={money_value(@current_policy, "currency") || "USD"}
              /></label>
              <label>Max microunits
              <input
                type="number"
                min="0"
                name="policy[max_microunits]"
                value={money_value(@current_policy, "max_microunits") || 0}
              /></label>
            </div>
            <p>
              <strong>Effective limits and estimates.</strong>
              Enter a spending limit in millionths of a dollar. Estimated cost is shown only when available. Estimates are separate from actual charges.
            </p>
          </fieldset>
          <button disabled={!@live_connected || !@lifecycle["update_policy"]} type="submit">Save Run settings</button>
        </form>

        <div class="card stack">
          <h3>Saved settings</h3>
          <p>
            Use a built-in preset or save your own settings. Each update saves a new version. Incompatible settings are flagged.
          </p>
          <form phx-submit="save_current_preset" class="inline-form">
            <label>Preset name <input name="preset[name]" maxlength="80" required /></label>
            <button disabled={!@live_connected} type="submit">Save current policy</button>
          </form>
          <div class="preset-grid">
            <article :for={preset <- @policy_presets} class="preset-card">
              <p><strong>{preset["name"]}</strong> · {preset["source"]} v{preset["version"]}</p>
              <p>Status: {if(preset["compatible"], do: "compatible", else: "incompatible")}</p>
              <p>Version reference <code>{preset["fingerprint"]}</code></p>
              <pre><%= json(preset["policy"]) %></pre>
              <p :if={!preset["compatible"]} role="status">Cannot apply: {preset["error"]}</p>
              <button
                :if={preset["compatible"]}
                phx-click="apply_preset"
                phx-value-reference={preset["reference"]}
                name="preset[reference]"
                value={preset["reference"]}
                disabled={!@live_connected}
              >Apply settings</button>
            </article>
          </div>
        </div>

        <div class="card stack">
          <h3>Selected screenplay material</h3>
          <p :if={is_nil(@workflow_selection)}>
            No material is selected. Open the Viewer to choose scenes from this screenplay version.
          </p>
          <div :if={@workflow_selection}>
            <p>
              Base <code>{@workflow_selection["base_revision_id"]}</code>
              · selection <code>{@workflow_selection["selection_fingerprint"]}</code>
            </p>
            <pre><%= json(@workflow_selection["preview"]) %></pre>
          </div>
          <a href={~p"/runs/#{@run_id}/viewer"}>Select scenes in Viewer</a>
        </div>

        <div class="card stack">
          <h3>Available actions</h3>
          <p>
            Only available actions can be started. Review their settings before continuing.
          </p>
          <div class="action-catalog">
            <article
              :for={action <- @workflow_actions}
              class={
                if(action["enabled"], do: "action-card enabled", else: "action-card unavailable")
              }
            >
              <h4>{action["label"]}</h4>
              <p>
                Status:
                <strong>{if(action["enabled"], do: "enabled", else: "unavailable through Run")}</strong>
              </p>
              <p>Mode: {action["mode"]}</p>
              <p>{action["request"]}</p>
              <p>{action["handler"]}</p>
              <p>{action["preconditions"]}</p>
            </article>
          </div>
        </div>

        <form phx-submit="preview_workflow_launch" class="card stack">
          <h3>Start work</h3>
          <label>
            Action
            <select name="workflow[action]">
              <option :for={action <- @enabled_workflow_actions} value={action["id"]}>
                {action["label"]}
              </option>
            </select>
          </label>
          <label>Instruction <textarea name="workflow[instruction]" maxlength="4096" required></textarea></label>
          <label class="inline-check"><input
            type="checkbox"
            name="workflow[multi_launch]"
            value="true"
          />
          Launch one independent Run per selected target (maximum {FountWeb.WorkflowManagement.max_multi_launch()})</label>
          <p>
            Each Run keeps its own full policy budget; there is no shared batch budget or second scheduler.
          </p>
          <button disabled={!@live_connected || is_nil(@workflow_selection)} type="submit">Validate launch preview</button>
        </form>

        <div :if={@launch_preview} class="card stack launch-preview">
          <h3>Review before starting</h3>
          <p>
            Command <code>{@launch_preview["command_id"]}</code>
            · base <code>{@launch_preview["base_revision_id"]}</code>
          </p>
          <article
            :for={{entry, index} <- Enum.with_index(@launch_preview["entries"])}
            class="launch-entry"
          >
            <strong>Run {index + 1}</strong> · selection <code>{entry["selection_fingerprint"]}</code>
            <pre><%= json(%{"preview" => entry["preview"], "budget" => entry["budget"], "request_fingerprint" => entry["request_fingerprint"]}) %></pre>
          </article>
          <button phx-click="confirm_workflow_launch" disabled={!@live_connected}>Create these independent Runs</button>
        </div>

        <div :if={@launch_results} class="card">
          <h3>Launch results</h3>
          <p>
            {length(@launch_results["created"])} created/replayed · {length(@launch_results["failed"])} failed · partial: {to_string(
              @launch_results["partial"]
            )}
          </p>
          <ul>
            <li :for={row <- @launch_results["created"]}>
              Ready: <a href={~p"/runs/#{row["run_id"]}/setup"}><code>{row["run_id"]}</code></a>
            </li>
            <li :for={row <- @launch_results["failed"]}>
              Failed for <code>{row["selection_fingerprint"]}</code>: {row["error"]}
            </li>
          </ul>
        </div>

        <div class="card">
          <button disabled={!@live_connected} phx-click="launch">Launch / resume Run</button>
          <p>Resuming continues this Run without starting a duplicate.</p>
        </div>
      </section>

      <section :if={@live_action == :timeline} class="stack">
        <h2>Progress and controls</h2>
        <p>
          Completion policy: <strong>{@current_policy["completion"]}</strong>. Saving proposed pages leaves the approved screenplay unchanged. Approval is a separate action.
        </p>
        <div class="card">
          <button disabled={!@live_connected || !@lifecycle["pause"]} phx-click="pause">Pause</button>
          <button disabled={!@live_connected || !@lifecycle["resume"]} phx-click="resume">Resume</button>
          <form phx-submit="stop" class="inline-form stop-confirmation">
            <label class="inline-check"><input
              type="checkbox"
              name="control[confirm_stop]"
              value="true"
              required
              disabled={!@live_connected || !@lifecycle["stop"]}
            /> Confirm permanent stop</label>
            <button disabled={!@live_connected || !@lifecycle["stop"]} type="submit">Stop</button>
          </form>
          <button
            disabled={
              !@live_connected ||
                @run["status"] in ~w(completed_candidate completed_accepted stopped failed)
            }
            phx-click="launch"
          >Ensure worker is running</button>
          <p><strong>Permitted-state summary:</strong> {@lifecycle["reason"]}</p>
          <p>
            Plan v{@run["current_plan_version"]} · policy v{@run["current_policy_version"]} · lock/fencing version {@run[
              "lock_version"
            ] || "—"}. Repeated commands remain subject to backend idempotency and conflict checks.
          </p>
        </div>
        <p>
          Progress updates from saved work. Reconnect to recover the latest state.
        </p>
        <p>Current scope: <code>{json(@current_plan["scope"])}</code></p>
        <p>
          Analysis service: <strong>{@analysis_service["label"]}</strong>
          (<code>{@analysis_service["mode"]}</code>). Compatibility mode records semantic analysis as not-run; it is never treated as success.
        </p>
        <div class="grid">
          <div class="card">
            <h3>Analysis before writing</h3>
            <p>Status: <strong>{analysis_status(@review.pre_analysis)}</strong></p>
            <pre><%= json(@review.pre_analysis) %></pre>
          </div>
          <div class="card">
            <h3>Analysis of changes</h3>
            <p>Status: <strong>{analysis_status(@review.revision_analysis)}</strong></p>
            <pre><%= json(@review.revision_analysis) %></pre>
          </div>
        </div>
        <p :if={@run["pause_requested_at"]}>
          Pause requested at {@run["pause_requested_at"]}; any already-dispatched provider call is settling before another dispatch.
        </p>
        <p :if={@run["stop_requested_at"]}>
          Stop requested at {@run["stop_requested_at"]}; saved partial results remain available. No new work will start.
        </p>
        <table>
          <thead>
            <tr>
              <th>Stage</th><th>Status</th><th>Iteration</th><th>Result</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={step <- @progress["steps"] || []}>
              <td>{step["stage"]}</td><td>{step["status"]}</td><td>{step["iteration"]}</td><td>
                <code>{inspect(step["result"], limit: 8)}</code>
              </td>
            </tr>
          </tbody>
        </table>
        <div class="grid">
          <div class="card">
            <h3>Usage / incurred cost</h3><pre><%= json(@progress["usage"]) %></pre><p>
              Missing provider cost remains unknown; it is not displayed as zero.
            </p>
          </div>
          <div class="card">
            <h3>Provider requests / partial work</h3><pre><%= json(@progress["provider_requests"]) %></pre>
          </div>
          <div class="card">
            <h3>Approval attempts / recorded identity</h3><pre><%= json(@progress["approval_attempts"]) %></pre>
          </div>
        </div>
      </section>

      <section :if={@live_action == :decisions} class="stack">
        <h2>Decision inbox</h2>
        <p>
          Decisions apply to the saved version shown here. If it changes, reload and review before submitting.
        </p>
        <p :if={@pending_decisions == []}>No pending decisions.</p>
        <article :for={decision <- @pending_decisions} class="card">
          <h3>{decision["kind"]}</h3>
          <p>Decision <code>{decision["id"]}</code></p>
          <p><strong>Question:</strong> {decision["prompt"]}</p>
          <p>Version reference <code>{decision["context_fingerprint"]}</code></p>
          <p :if={is_nil(@decision_contexts[decision["id"]]["analysis_lineage"])} role="status">
            Intelligence lineage: not recorded for this decision.
          </p>
          <div
            :if={!is_nil(@decision_contexts[decision["id"]]["analysis_lineage"])}
            class="decision-lineage"
          >
            <strong>Recorded Intelligence lineage</strong>
            <pre><%= json(@decision_contexts[decision["id"]]["analysis_lineage"]) %></pre>
          </div>
          <div class="grid">
            <div>
              <h4>Available choices and consequences</h4><pre><%= json(decision["options"]) %></pre>
            </div>
            <div>
              <h4>Version details for this decision</h4><pre><%= json(Map.merge(Map.take(decision, ["candidate_id", "base_revision_id", "content_hash", "check_set_fingerprint", "plan_version", "policy_version"]), @decision_contexts[decision["id"]])) %></pre>
            </div>
          </div>
          <p>
            Safe default: leave this checkpoint pending when the evidence is insufficient; the host never chooses on behalf of a human checkpoint.
          </p>
          <form :for={option <- decision["options"] || []} phx-submit="submit_decision">
            <input type="hidden" name="decision[id]" value={decision["id"]} />
            <input
              type="hidden"
              name="decision[context_fingerprint]"
              value={decision["context_fingerprint"]}
            />
            <input type="hidden" name="decision[plan_version]" value={decision["plan_version"]} />
            <input type="hidden" name="decision[policy_version]" value={decision["policy_version"]} />
            <input
              type="hidden"
              name="decision[choice]"
              value={option["id"] || option["value"] || option["choice"]}
            />
            <label
              :if={(option["id"] || option["value"] || option["choice"]) == "stop"}
              class="inline-check"
            >
              <input
                type="checkbox"
                name="decision[confirm_stop]"
                value="true"
                required
                disabled={!@live_connected}
              /> Confirm permanent stop
            </label>
            <label :if={(option["id"] || option["value"]) == "replace"}>
              Replacement Fountain <textarea
                name="decision[replacement_fountain]"
                placeholder="Paste the complete replacement Fountain source for a new checked candidate"
              ></textarea>
            </label>
            <button disabled={!@live_connected} type="submit">{option["title"] || option["label"] ||
              option["id"] ||
              option["value"]}</button>
          </form>
        </article>
      </section>

      <section :if={@live_action == :review} class="stack">
        <h2>Side-by-side candidate review</h2>
        <div class="grid">
          <div class="card">
            <h3>Analysis before writing</h3>
            <p>Status: <strong>{analysis_status(@review.pre_analysis)}</strong></p>
            <pre><%= json(@review.pre_analysis) %></pre>
          </div>
          <div class="card">
            <h3>Analysis of changes</h3>
            <p>Status: <strong>{analysis_status(@review.revision_analysis)}</strong></p>
            <pre><%= json(@review.revision_analysis) %></pre>
          </div>
        </div>
        <p :if={is_nil(@review.candidate)}>
          No proposed pages have been saved yet. Complete the required review before generation can continue.
        </p>
        <div :if={@review.candidate} class="grid">
          <div>
            <h3>Approved original</h3><pre class="script"><%= @review.base %></pre>
          </div>
          <div>
            <h3>Candidate <code>{@review.candidate_id}</code></h3><pre class="script"><%= @review.candidate %></pre>
          </div>
        </div>
        <div :if={@review.candidate} class="card intelligence-binding-card">
          <div>
            <p class="eyebrow">Analysis for this revision</p>
            <h3>Analysis of proposed changes</h3>
          </div>
          <dl class="binding-ledger">
            <div>
              <dt>Base revision</dt><dd>
                <code>{@review.analysis_binding["base_revision_id"] || "—"}</code>
              </dd>
            </div>
            <div>
              <dt>Candidate</dt><dd>
                <code>{@review.analysis_binding["candidate_id"] || "—"}</code>
              </dd>
            </div>
            <div>
              <dt>Candidate revision</dt><dd>
                <code>{@review.analysis_binding["candidate_revision_id"] || "—"}</code>
              </dd>
            </div>
            <div>
              <dt>Packet</dt><dd>
                <code>{@review.analysis_binding["packet_id"] || "missing"}</code>
              </dd>
            </div>
            <div>
              <dt>Analysis run</dt><dd>
                <code>{@review.analysis_binding["analysis_run_id"] || "missing"}</code>
              </dd>
            </div>
            <div>
              <dt>Freshness</dt><dd>{@review.analysis_binding["freshness"]}</dd>
            </div>
            <div>
              <dt>Check reference</dt><dd>
                <code>{@review.analysis_binding["check_set_fingerprint"] || "—"}</code>
              </dd>
            </div>
          </dl>
          <p>
            Story observations do not replace required checks or your approval. Missing or outdated analysis is not a pass.
          </p>
          <a class="inline-action" href={~p"/runs/#{@run_id}/analysis"}>Open saved analysis</a>
        </div>

        <div :if={@review.candidate} class="card">
          <h3>Compare screenplay changes</h3>
          <FountWeb.Components.DiffViewer.diff
            before={@review.base_model}
            after={@review.candidate_model}
            before_label="Approved original"
            after_label="Candidate"
            before_status="base"
            after_status="candidate"
            mode="side-by-side"
          />
        </div>
        <div :if={@review.candidate} class="grid">
          <div class="card">
            <h3>Revision history</h3><pre><%= json(%{"provenance" => @review.provenance, "lineage" => @review.lineage, "result_revision_id" => @review.result_revision_id}) %></pre>
          </div>
          <div class="card">
            <h3>Check details</h3><pre><%= json(%{"required_checks" => @review.required_checks, "check_set_fingerprint" => @review.check_set_fingerprint}) %></pre>
          </div>
        </div>
        <div class="grid">
          <div class="card">
            <h3>Story observations</h3><pre><%= json(@review.advisory_checks) %></pre><p>
              These are advisory semantic findings. Partial or failed semantic analysis is never displayed as an advisory pass.
            </p>
          </div>
          <div class="card">
            <h3>Required checks</h3><pre><%= json(@review.required_run_checks) %></pre><p>
              Required checks must be resolved before approval. Story observations are advice, not approval.
            </p>
          </div>
        </div>
        <div :if={@review.other_checks != []} class="card">
          <h3>Other recorded checks</h3><pre><%= json(@review.other_checks) %></pre>
        </div>
        <p>
          Missing checks do not count as passes. Any permitted exception is recorded with your decision.
        </p>
        <p :if={@review.candidate}>
          Choosing a proposed revision and approving it are separate saved decisions. <a href={
            ~p"/runs/#{@run_id}/decisions"
          }>Open the current decision inbox</a>; this review page never accepts pages implicitly.
        </p>
      </section>

      <section :if={@live_action == :exports} class="stack">
        <h2>Exports</h2>
        <div class="card">
          <h3>Export identity and fidelity preview</h3>
          <p :if={@export_preview["available"] == false}>
            No exportable candidate yet: {@export_preview["reason"]}
          </p>
          <dl :if={@export_preview["available"] != false} class="binding-ledger">
            <div>
              <dt>Content identity</dt><dd>{@export_preview["completion"]}</dd>
            </div>
            <div>
              <dt>Candidate</dt><dd><code>{@export_preview["candidate_id"]}</code></dd>
            </div>
            <div>
              <dt>Result revision</dt><dd>
                <code>{@export_preview["result_revision_id"] || "not accepted"}</code>
              </dd>
            </div>
            <div>
              <dt>Fountain bytes</dt><dd>{@export_preview["fountain_bytes"]}</dd>
            </div>
            <div>
              <dt>FDX fidelity/loss report</dt><dd>
                <pre><%= json(@export_preview["fdx_losses"]) %></pre>
              </dd>
            </div>
            <div>
              <dt>Recorded delivery rows</dt><dd>{@export_preview["delivery_count"]}</dd>
            </div>
          </dl>
          <p>
            Standard bundle formats are Fountain, FDX, review JSON/Markdown, source/structural diffs, resources/checks and provenance. Optional formats are only PDF and table-read. Unsupported options are not exposed.
          </p>
        </div>
        <form phx-submit="deliver" class="card stack">
          <label><input type="checkbox" name="export[pdf]" value="true" />
          Include PDF (explicitly fails/partials when the configured renderer or PDF checks are unavailable)</label>
          <label><input type="checkbox" name="export[table_read]" value="true" />
          Include table-read JSON/HTML bundle</label>
          <button disabled={!@live_connected} type="submit">Publish / retry bundle</button>
        </form>
        <table>
          <thead>
            <tr>
              <th>Format</th><th>Content identity</th><th>State</th><th>Checksum / explicit error</th><th>
                Access
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={delivery <- @progress["deliveries"] || []}>
              <td>{delivery["format"]}</td>
              <td>{delivery_identity(delivery)}</td>
              <td>{delivery["state"]}</td>
              <td><code>{delivery["output_checksum"] || delivery["error"] || "unknown"}</code></td>
              <td>
                <a
                  :if={delivery_previewable?(delivery)}
                  href={~p"/artifacts/#{@run_id}/#{delivery["id"]}/preview"}
                >Preview</a>
                <span :if={delivery_previewable?(delivery)}> · </span>
                <a
                  :if={delivery["state"] == "ready"}
                  href={~p"/artifacts/#{@run_id}/#{delivery["id"]}"}
                >Download</a>
                <span :if={delivery["state"] == "failed"}>Explicit failure; no artifact is served.</span>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </main>
    """
  end
end
