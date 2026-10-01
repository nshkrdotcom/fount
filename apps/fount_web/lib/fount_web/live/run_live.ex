defmodule FountWeb.RunLive do
  use FountWeb, :live_view

  alias Fount.Writing.Principal

  @refresh_ms 1_000

  @impl true
  def mount(%{"key" => project_key, "task_key" => task_key}, _session, socket) do
    owner = socket.assigns.current_owner

    case FountWeb.Store.run_access_by_task_key(Fount.Repo, owner, project_key, task_key) do
      {:ok, access} ->
        run_id = access["run_id"]
        {:ok, context} = FountWeb.Actors.owner_context(owner, access["screenplay_id"])

        if connected?(socket) do
          Phoenix.PubSub.subscribe(FountWeb.PubSub, FountWeb.RunEvents.topic(run_id))
          Process.send_after(self(), :refresh, @refresh_ms)
        end

        {:ok,
         socket
         |> assign(:live_connected, connected?(socket))
         |> assign(:run_id, run_id)
         |> assign(:project_key, project_key)
         |> assign(:task_key, task_key)
         |> assign(:access, access)
         |> assign(:context, context)
         |> assign(:error, nil)
         |> assign(:notice, nil)
         |> assign(:notification_read_ids, MapSet.new())
         |> assign(:notifications, [])
         |> assign(:unread_notifications, [])
         |> assign(:launch_preview, nil)
         |> assign(:launch_results, nil)
         |> assign(:audition, nil)
         |> assign(:candidate_selections, %{})
         |> assign(:combine_selections, %{})
         |> refresh()}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "That task is not available for this project.")
         |> redirect(to: "/")}
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

      {:noreply, socket |> assign(:notice, "Task started.") |> assign(:error, nil) |> refresh()}
    else
      {:error, reason} -> {:noreply, assign(socket, :error, friendly_error(reason))}
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
    do: {:noreply, assign(socket, :error, "Confirm that you want to stop this task.")}

  def handle_event("submit_decision", %{"decision" => %{"choice" => "stop"} = params}, socket)
      when not is_map_key(params, "confirm_stop"),
      do: {:noreply, assign(socket, :error, "Confirm that you want to stop this task.")}

  def handle_event(
        "submit_decision",
        %{"decision" => %{"choice" => "stop", "confirm_stop" => value}},
        socket
      )
      when value not in ["true", "on", "1"],
      do: {:noreply, assign(socket, :error, "Confirm that you want to stop this task.")}

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

        decision_recorded(socket, value)

      {:error, reason}
      when reason in [:stale_decision, :stale_decision_context, :decision_conflict] ->
        {:noreply,
         socket
         |> assign(
           :error,
           "This decision changed. The latest saved state has loaded; review it before submitting again."
         )
         |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, friendly_error(reason))}
    end
  end

  def handle_event("audition_candidate", %{"candidate_id" => candidate_id}, socket) do
    case FountWeb.CandidateWorkspace.audition(
           Fount.Repo,
           socket.assigns.run,
           socket.assigns.progress,
           candidate_id
         ) do
      {:ok, audition} ->
        {:noreply,
         socket
         |> assign(:audition, audition)
         |> assign(
           :notice,
           "Audition prepared from the exact saved task scope. Nothing was accepted."
         )
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, candidate_work_error(reason))}
    end
  end

  def handle_event("candidate_selection_changed", %{"candidate" => params}, socket) do
    selections =
      Map.put(socket.assigns.candidate_selections, params["id"], List.wrap(params["groups"]))

    {:noreply, assign(socket, :candidate_selections, selections)}
  end

  def handle_event("combine_selection_changed", %{"combine" => params}, socket) do
    {:noreply, assign(socket, :combine_selections, params["groups"] || %{})}
  end

  def handle_event("combine_selection_changed", _params, socket),
    do: {:noreply, assign(socket, :combine_selections, %{})}

  def handle_event("select_candidate_groups", %{"candidate" => params}, socket) do
    candidate_id = params["id"]
    group_ids = List.wrap(params["groups"])

    case FountWeb.CandidateWorkspace.select_groups(
           Fount.Repo,
           socket.assigns.progress,
           candidate_id,
           group_ids
         ) do
      {:ok, candidate} ->
        {:noreply,
         socket
         |> assign(
           :notice,
           "Selected changes saved as related proposed writing. The current screenplay is unchanged."
         )
         |> assign(:error, nil)
         |> assign(:audition, nil)
         |> refresh()
         |> put_related_candidate_notice(candidate)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, candidate_work_error(reason))}
    end
  end

  def handle_event("combine_candidates", %{"combine" => params}, socket) do
    picks =
      params
      |> Map.get("groups", %{})
      |> Enum.map(fn {candidate_id, group_ids} ->
        %{"candidate_id" => candidate_id, "group_ids" => List.wrap(group_ids)}
      end)

    case FountWeb.CandidateWorkspace.combine(Fount.Repo, socket.assigns.progress, picks) do
      {:ok, candidate} ->
        {:noreply,
         socket
         |> assign(
           :notice,
           "Combined changes saved as related proposed writing. The current screenplay is unchanged."
         )
         |> assign(:error, nil)
         |> assign(:audition, nil)
         |> refresh()
         |> put_related_candidate_notice(candidate)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, candidate_work_error(reason))}
    end
  end

  def handle_event("use_related_candidate", %{"candidate_id" => candidate_id}, socket) do
    related = FountWeb.CandidateWorkspace.related(Fount.Repo, socket.assigns.progress)
    candidate = Enum.find(related, &(&1["id"] == candidate_id))

    decision =
      Enum.find(pending_decisions(socket.assigns.progress), &(&1["kind"] == "final_approval"))

    cond do
      is_nil(candidate) ->
        {:noreply,
         assign(socket, :error, "That related proposal no longer belongs to this task.")}

      is_nil(decision) ->
        {:noreply,
         assign(
           socket,
           :error,
           "This task is not at its final proposal checkpoint yet. Keep the related work saved and return after required checks finish."
         )}

      true ->
        response = %{
          "choice" => "replace",
          "context_fingerprint" => decision["context_fingerprint"],
          "plan_version" => decision["plan_version"],
          "policy_version" => decision["policy_version"],
          "replacement_fountain" => candidate["fountain"]
        }

        case FountRun.submit_decision(
               Fount.Repo,
               decision["id"],
               response,
               socket.assigns.context
             ) do
          {:ok, _value} ->
            FountWeb.RunEvents.notify(socket.assigns.run_id)

            {:noreply,
             socket
             |> assign(
               :notice,
               "Related writing is now the task's proposed replacement and has been sent back through required checks. It is not current screenplay."
             )
             |> assign(:error, nil)
             |> assign(:audition, nil)
             |> refresh()}

          {:error, reason}
          when reason in [:stale_decision, :stale_decision_context, :decision_conflict] ->
            {:noreply,
             socket
             |> assign(
               :error,
               "The proposal checkpoint changed. The latest saved task state has loaded; review it before trying again."
             )
             |> refresh()}

          {:error, reason} ->
            {:noreply, assign(socket, :error, friendly_error(reason))}
        end
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
          "Task settings saved; prior-version work and decisions were fenced and refreshed."
        )

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Task settings were not saved: #{friendly_error(reason)}")
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
        {:noreply,
         socket |> assign(:error, "Preset not saved: #{friendly_error(reason)}") |> refresh()}
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
        {:noreply,
         socket
         |> assign(:error, "Preset could not be applied: #{friendly_error(reason)}")
         |> refresh()}
    end
  end

  def handle_event("export_preset", %{"reference" => reference}, socket) do
    case FountWeb.WorkflowManagement.find_preset(
           Fount.Repo,
           socket.assigns.current_owner,
           reference,
           socket.assigns.context
         ) do
      {:ok, preset} ->
        payload = %{
          "name" => preset["name"],
          "version" => preset["version"],
          "policy" => preset["policy"]
        }

        {:noreply,
         socket
         |> push_event("download-json", %{
           filename: preset_filename(preset),
           content: Jason.encode!(payload, pretty: true)
         })
         |> assign(:notice, "Prepared #{preset["name"]} v#{preset["version"]} for export.")
         |> assign(:error, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Preset could not be exported: #{friendly_error(reason)}")
         |> refresh()}
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
        {:noreply, assign(socket, :error, "Task plan was not updated: #{friendly_error(reason)}")}
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
         "Launch preview validated. Confirm to create the listed independent tasks."
       )
       |> assign(:error, nil)}
    else
      nil ->
        {:noreply, assign(socket, :error, "Choose and save task scope from Sources first.")}

      {:error, reason} ->
        {:noreply,
         assign(socket, :error, "Task preview could not be prepared: #{friendly_error(reason)}")}
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
      "Created/replayed #{length(summary["created"])} task(s); #{length(summary["failed"])} failed. Retry uses the same saved scope."

    {:noreply,
     socket
     |> assign(:launch_results, summary)
     |> assign(:notice, message)
     |> assign(
       :error,
       if(summary["failed"] == [],
         do: nil,
         else: "Some launches failed; successful tasks are preserved and retry-safe."
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

      {:partial, _reason, _payload} ->
        {:noreply,
         socket
         |> assign(
           :notice,
           "Delivery is partial. Failed formats remain visible and retryable."
         )
         |> assign(:error, nil)
         |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Export failed: #{friendly_error(reason)}")}
    end
  end

  defp decision_recorded(socket, %{"outcome" => "rebased", "run_id" => run_id}) do
    access = socket.assigns.access

    with {:ok, _} <-
           FountWeb.Store.register_run(Fount.Repo, %{
             run_id: run_id,
             project_id: access["project_id"],
             owner_id: socket.assigns.current_owner,
             preset: access["preset"],
             journey: access["journey"]
           }),
         {:ok, _} <-
           FountWeb.Store.mark_launched(Fount.Repo, socket.assigns.current_owner, run_id),
         {:ok, successor} <-
           FountWeb.Store.run_access(Fount.Repo, socket.assigns.current_owner, run_id),
         {:ok, _} <- normalize_started(FountWeb.WorkerSupervisor.start_run(successor)) do
      {:noreply,
       push_navigate(socket,
         to: "/p/#{socket.assigns.project_key}/activity/#{successor["display_key"]}/decisions"
       )}
    else
      {:error, reason} ->
        {:noreply, socket |> assign(:error, friendly_error(reason)) |> refresh()}
    end
  end

  defp decision_recorded(socket, value) do
    {:noreply,
     socket
     |> assign(
       :notice,
       "Decision recorded#{if value["replay"], do: " (idempotent replay)", else: ""}."
     )
     |> assign(:error, nil)
     |> refresh()}
  end

  defp command_result(socket, {:ok, _}, notice) do
    FountWeb.RunEvents.notify(socket.assigns.run_id)
    {:noreply, socket |> assign(:notice, notice) |> assign(:error, nil) |> refresh()}
  end

  defp command_result(socket, {:error, reason}, _notice),
    do: {:noreply, socket |> assign(:error, friendly_error(reason)) |> refresh()}

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
            {:error, reason} -> %{"available" => false, "reason" => friendly_error(reason)}
          end

        assign(socket,
          progress: progress,
          run: run,
          review: review_data(run, progress),
          related_candidates: FountWeb.CandidateWorkspace.related(Fount.Repo, progress),
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
        assign(socket, :error, "Task progress is unavailable: #{friendly_error(reason)}")

      {_, {:error, reason}} ->
        assign(socket, :error, "Task progress is unavailable: #{friendly_error(reason)}")
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

  defp put_related_candidate_notice(socket, candidate) do
    assign(socket, :related_candidate_id, candidate["id"])
  end

  defp candidate_work_error({:overlapping_selections, _}),
    do: "Those choices edit the same passage. Narrow the checked change groups and combine again."

  defp candidate_work_error(:change_group_required), do: "Choose at least one saved change."

  defp candidate_work_error(:combination_requires_two_sources),
    do: "Choose change groups from at least two saved proposals to recombine them."

  defp candidate_work_error(:candidate_not_in_task),
    do: "That proposal is not related to this owner-bound task."

  defp candidate_work_error(:task_scope_unavailable), do: "The saved task scope is unavailable."
  defp candidate_work_error(reason), do: friendly_error(reason)

  defp pending_decisions(progress),
    do: Enum.filter(progress["decisions"] || [], &(&1["status"] == "pending"))

  defp current_policy(run), do: get_in(run, ["policy", "policy"]) || %{}
  defp current_plan(run), do: run["plan"] || %{}

  defp delivery_identity(delivery) do
    cond do
      is_binary(delivery["accepted_revision_id"]) -> "Current screenplay"
      is_binary(delivery["candidate_id"]) -> "Proposed writing"
      true -> "Saved screenplay output"
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
  defp review_step_label("investigation_scope"), do: "Investigation scope"
  defp review_step_label("strategy_choice"), do: "Approach choice"
  defp review_step_label("candidate_generation"), do: "Proposed-writing generation"
  defp review_step_label("iteration"), do: "Further iteration"
  defp review_step_label(gate), do: gate |> String.replace("_", " ") |> String.capitalize()
  defp decision_kind_label("strategy"), do: "Choose an approach"
  defp decision_kind_label("routing"), do: "Choose where the work runs"
  defp decision_kind_label("investigation_scope"), do: "Confirm what to investigate"
  defp decision_kind_label("iteration"), do: "Continue or keep this version"
  defp decision_kind_label("final_approval"), do: "Make the reviewed work current"
  defp decision_kind_label("rebase"), do: "Screenplay changed — rebase first"
  defp decision_kind_label(nil), do: "Checkpoint"
  defp decision_kind_label(kind), do: kind |> String.replace("_", " ") |> String.capitalize()

  defp decision_option_label(option) do
    value = option["id"] || option["value"] || option["choice"]

    if value in ~w(approve reject replace rebase stop),
      do: decision_value_label(value),
      else: option["title"] || option["label"] || decision_value_label(value)
  end

  defp decision_value_label("approve"), do: "Make this exact checked proposal current"
  defp decision_value_label("reject"), do: "Keep as proposed writing"
  defp decision_value_label("replace"), do: "Save manual adjustment and re-check"
  defp decision_value_label("rebase"), do: "Rebase onto the current screenplay"
  defp decision_value_label("stop"), do: "Stop this task"

  defp decision_value_label(value) when is_binary(value),
    do: value |> String.replace("_", " ") |> String.capitalize()

  defp decision_value_label(_), do: "Choose"

  defp money_value(policy, key), do: get_in(policy, ["limits", "money", key])

  defp policy_effect_summary(policy) do
    human_gates =
      policy
      |> Map.get("gates", %{})
      |> Enum.count(fn {_gate, mode} -> mode == "human" end)

    completion =
      if policy["completion"] == "accept",
        do: "authorized acceptance after checks",
        else: "proposed writing for separate review"

    inference_calls = get_in(policy, ["limits", "max_inference_calls"]) || 0

    money =
      case get_in(policy, ["limits", "money"]) do
        %{"currency" => currency, "max_microunits" => max_microunits}
        when is_integer(max_microunits) ->
          "#{currency} #{FountWeb.WorkflowManagement.money_units(max_microunits)} spend ceiling"

        _ ->
          "no spending ceiling"
      end

    "#{human_gates} human review stop#{if human_gates == 1, do: "", else: "s"}; #{completion}; #{inference_calls} inference-call ceiling; #{money}."
  end

  defp preset_effect_summary(current, proposed) when current == proposed,
    do: "Same as the current settings."

  defp preset_effect_summary(current, proposed) do
    current_human =
      current |> Map.get("gates", %{}) |> Enum.count(fn {_key, value} -> value == "human" end)

    proposed_human =
      proposed |> Map.get("gates", %{}) |> Enum.count(fn {_key, value} -> value == "human" end)

    current_calls = get_in(current, ["limits", "max_inference_calls"])
    proposed_calls = get_in(proposed, ["limits", "max_inference_calls"])

    changes =
      []
      |> maybe_effect(
        current_human != proposed_human,
        "human review stops #{current_human} → #{proposed_human}"
      )
      |> maybe_effect(
        current["completion"] != proposed["completion"],
        "result #{completion_label(current["completion"])} → #{completion_label(proposed["completion"])}"
      )
      |> maybe_effect(
        current_calls != proposed_calls,
        "inference-call ceiling #{current_calls || 0} → #{proposed_calls || 0}"
      )
      |> maybe_effect(
        get_in(current, ["limits", "money"]) != get_in(proposed, ["limits", "money"]),
        "spending ceiling changes"
      )
      |> maybe_effect(
        current["route_choice"] != proposed["route_choice"],
        "tradeoff routing changes"
      )

    case changes do
      [] ->
        "Other validated settings change; open Technical details for the exact policy snapshot."

      values ->
        "Would change: " <> Enum.join(values, "; ") <> "."
    end
  end

  defp completion_label("accept"), do: "authorized acceptance"
  defp completion_label(_), do: "proposed writing"

  defp preset_filename(preset) do
    stem =
      preset["name"]
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9._-]+/u, "-")
      |> String.trim("-")

    "#{if(stem == "", do: "fount-policy", else: stem)}-v#{preset["version"]}.json"
  end

  defp maybe_effect(values, true, text), do: values ++ [text]
  defp maybe_effect(values, false, _text), do: values

  defp friendly_error(:not_found), do: "The saved task state is no longer available."

  defp friendly_error(:conflict),
    do: "The task changed. Reload the saved state before trying again."

  defp friendly_error(:stale_decision), do: "The decision changed before it was saved."

  defp friendly_error(:stale_decision_context),
    do: "The decision context changed before it was saved."

  defp friendly_error(:decision_conflict), do: "A different decision was already saved."
  defp friendly_error(:unauthorized), do: "This task is not available to the current owner."

  defp friendly_error(_),
    do: "The action could not be completed; saved screenplay material is unchanged."

  defp step_result_label(nil), do: "No saved result"

  defp step_result_label(%{"candidate_id" => value}) when is_binary(value),
    do: "Proposed writing saved"

  defp step_result_label(%{"status" => status}) when is_binary(status),
    do: String.replace(status, "_", " ")

  defp step_result_label(_), do: "Saved result"

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
      <FountWeb.CoreComponents.project_header
        project={
          %{"key" => @project_key, "title" => @access["title"], "project_kind" => "screenplay"}
        }
        section={if @live_action == :review, do: "changes", else: "work"}
        view="reading"
        source_label="Current draft"
      />

      <nav class="task-subnav" aria-label="Task">
        <strong>{@access["display_label"] || "Saved task"}</strong>
        <a
          href={"/p/#{@project_key}/activity/#{@task_key}/setup"}
          aria-current={if @live_action == :setup, do: "page"}
        >Controls</a>
        <a
          href={"/p/#{@project_key}/activity/#{@task_key}"}
          aria-current={if @live_action == :timeline, do: "page"}
        >Activity</a>
        <a
          href={"/p/#{@project_key}/activity/#{@task_key}/decisions"}
          aria-current={if @live_action == :decisions, do: "page"}
        >Decisions <span aria-label="pending decision count">({length(@pending_decisions)})</span></a>
        <a
          href={"/p/#{@project_key}/changes/#{@task_key}"}
          aria-current={if @live_action == :review, do: "page"}
        >Review</a>
        <a href={"/p/#{@project_key}/analysis/#{@task_key}"}>Analysis</a>
        <a
          href={"/p/#{@project_key}/exports/#{@task_key}"}
          aria-current={if @live_action == :exports, do: "page"}
        >Exports</a>
      </nav>

      <header class="card task-header">
        <h1>{@access["title"]}</h1>
        <p>
          <strong>{@access["display_label"] || "Saved task"}</strong>
          · {String.replace(@access["journey"] || "task", "_", " ")}
        </p>
        <p class="status" aria-live="polite">
          Status: {String.replace(@run["status"] || "unknown", "_", " ")} · stage: {String.replace(
            @run["stage"] || "—",
            "_",
            " "
          )}
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
        <h2>Task controls</h2>
        <button
          type="button"
          phx-click="launch"
          disabled={
            !@live_connected ||
              @run["status"] in ~w(completed_candidate completed_accepted stopped failed)
          }
        >Start / resume task</button>
        <p class="warning">
          Proposed pages replace the approved screenplay only after your approval.
          Changing settings creates a saved version and prevents affected work from continuing with old settings.
        </p>

        <div class="grid">
          <div class="card">
            <p class="eyebrow">Plan snapshot</p>
            <h3>Goal</h3><p>{@current_plan["goal"]}</p>
            <p>Version <strong>{@run["current_plan_version"]}</strong></p>
            <details class="technical-details">
              <summary>Technical details</summary><code>{get_in(@run, ["plan", "fingerprint"]) ||
                "recorded in task lineage"}</code>
            </details>
          </div>
          <div class="card">
            <h3>Exact scope</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@current_plan["scope"]) %></pre>
            </details>
            <details class="technical-details">
              <summary>Technical details</summary><p>
                Base revision <code>{@current_plan["base_revision_id"]}</code>
              </p>
            </details>
          </div>
          <div class="card">
            <h3>Constraints</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@current_plan["constraints"]) %></pre>
            </details>
          </div>
          <div class="card">
            <h3>Protected passages</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@current_plan["protected_material"]) %></pre>
            </details>
          </div>
        </div>

        <form phx-submit="update_plan" class="card stack">
          <h3>Update plan goal</h3>
          <p>
            Update the goal for the selected screenplay and material. To change the selection, start a new task.
          </p>
          <label>Goal <textarea name="plan[goal]" maxlength="2000"><%= @current_plan["goal"] %></textarea></label>
          <button disabled={!@live_connected || !@lifecycle["update_plan"]} type="submit">Save plan changes</button>
        </form>

        <form phx-submit="save_policy" class="card stack policy-form">
          <div>
            <p class="eyebrow">Purposeful controls</p>
            <h3>Task settings</h3>
            <p>
              Settings version {@run["current_policy_version"]}. Changes are saved as a new version and fence affected old work.
            </p>
          </div>

          <fieldset>
            <legend>Review steps</legend>
            <p class="scope-note">
              Choose where the task must stop for a person. Candidate completion keeps proposed writing separate from the current screenplay.
            </p>
            <p class="scope-note">
              <strong>Effective now:</strong> {policy_effect_summary(@current_policy)}
            </p>
            <div class="policy-grid">
              <label :for={
                gate <- ~w(investigation_scope strategy_choice candidate_generation iteration)
              }>
                {review_step_label(gate)}
                <select name={"policy[#{gate}]"}>
                  <option value="human" selected={get_in(@current_policy, ["gates", gate]) == "human"}>
                    Ask me
                  </option>
                  <option
                    value="automatic"
                    selected={get_in(@current_policy, ["gates", gate]) == "automatic"}
                  >
                    Continue automatically
                  </option>
                </select>
              </label>
              <label>
                Completion
                <select name="policy[completion]">
                  <option value="candidate" selected={@current_policy["completion"] == "candidate"}>
                    Save proposed writing — review required
                  </option>
                  <option value="accept" selected={@current_policy["completion"] == "accept"}>
                    Accept only with the exact authorized approver
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
              /> Allow the authenticated owner as fallback approver</label>
              <label>
                When a material tradeoff appears
                <select name="policy[route_choice]">
                  <option
                    value="pause_on_material_tradeoff"
                    selected={policy_route_rule(@current_policy) == "pause_on_material_tradeoff"}
                  >
                    Pause for review
                  </option>
                  <option
                    value="registered_reviewer"
                    selected={policy_route_rule(@current_policy) == "registered_reviewer"}
                  >
                    Route to a registered human reviewer
                  </option>
                </select>
              </label>
              <label>
                Registered reviewer
                <select name="policy[route_reviewer_key]">
                  <option
                    :for={option <- @policy_reviewers}
                    value={option["key"]}
                    selected={
                      policy_reviewer_key(@current_policy, @policy_reviewers) == option["key"]
                    }
                  >
                    {option["label"]}
                  </option>
                </select>
              </label>
            </div>
          </fieldset>

          <fieldset>
            <legend>Time and spending limits</legend>
            <p class="eyebrow">Effective limits and estimates</p>
            <p class="scope-note">
              These are hard task ceilings. Estimated cost is shown only when available; missing cost estimates remain unknown rather than being invented.
            </p>
            <div class="policy-grid">
              <label>Writing iterations
              <input
                type="number"
                min="0"
                name="policy[max_iterations]"
                value={limit_value(@current_policy, "max_iterations", 3)}
              /></label>
              <label>Malformed-response repairs per call
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
            /> Set a spending ceiling</label>
            <div class="policy-grid">
              <label>Currency
              <input
                name="policy[currency]"
                maxlength="3"
                value={money_value(@current_policy, "currency") || "USD"}
              /></label>
              <label>Maximum spend
              <input
                inputmode="decimal"
                name="policy[max_currency_units]"
                value={
                  FountWeb.WorkflowManagement.money_units(
                    money_value(@current_policy, "max_microunits") || 0
                  )
                }
              /></label>
            </div>
            <p>
              Enter ordinary currency units, for example <code>12.50</code>. Fount converts that value exactly to the existing microunit contract before validation.
            </p>
          </fieldset>

          <details class="technical-details">
            <summary>Technical details</summary>
            <p>
              Policy fingerprint <code>{get_in(@run, ["policy", "fingerprint"]) || "recorded"}</code>
            </p>
            <pre><%= json(@current_policy) %></pre>
          </details>
          <button disabled={!@live_connected || !@lifecycle["update_policy"]} type="submit">Save task settings</button>
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
              <p :if={preset["compatible"]} class="scope-note">
                {preset_effect_summary(@current_policy, preset["policy"])}
              </p>
              <details class="technical-details">
                <summary>Technical details</summary><code>{preset["fingerprint"]}</code>
              </details>
              <details class="technical-details">
                <summary>Technical details</summary><pre><%= json(preset["policy"]) %></pre>
              </details>
              <p :if={!preset["compatible"]} role="status">Cannot apply: {preset["error"]}</p>
              <button
                :if={preset["compatible"]}
                phx-click="apply_preset"
                phx-value-reference={preset["reference"]}
                name="preset[reference]"
                value={preset["reference"]}
                disabled={!@live_connected}
              >Apply settings</button>
              <button
                :if={preset["compatible"]}
                type="button"
                phx-click="export_preset"
                phx-value-reference={preset["reference"]}
                disabled={!@live_connected}
              >Export JSON</button>
            </article>
          </div>
        </div>

        <div class="card stack">
          <h3>Selected screenplay material</h3>
          <p :if={is_nil(@workflow_selection)}>
            No material is selected. Open Sources to choose material from this task's exact base screenplay.
          </p>
          <div :if={@workflow_selection}>
            <p>
              Saved against the exact task base and selection
            </p>
            <details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@workflow_selection["preview"]) %></pre>
            </details>
          </div>
          <a href={"/p/#{@project_key}/source/#{@task_key}#task-scope"}>Choose task scope in Sources</a>
        </div>

        <div class="card stack">
          <h3>Related creative work</h3>
          <p>
            The complete creative catalog, exact screenplay selection, protections, approaches and recovery inputs live beside the pages rather than inside this task-policy screen.
          </p>
          <a class="button-link" href={"/p/#{@project_key}/work"}>Open Work on it</a>
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
            Plan v{@run["current_plan_version"]} · policy v{@run["current_policy_version"]} · control version {@run[
              "lock_version"
            ] || "—"}. Repeated commands remain subject to backend idempotency and conflict checks.
          </p>
        </div>
        <p>
          Progress updates from saved work. Reconnect to recover the latest state.
        </p>
        <p>
          Current scope is saved with this task.
          <details class="technical-details">
            <summary>Technical scope</summary><code>{json(@current_plan["scope"])}</code>
          </details>
        </p>
        <p>
          Analysis service: <strong>{@analysis_service["label"]}</strong>
          (<code>{@analysis_service["mode"]}</code>). If semantic analysis is unavailable, it is recorded as not-run; it is never treated as success.
        </p>
        <div class="grid">
          <div class="card">
            <h3>Analysis before writing</h3>
            <p>Status: <strong>{analysis_status(@review.pre_analysis)}</strong></p>
            <details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@review.pre_analysis) %></pre>
            </details>
          </div>
          <div class="card">
            <h3>Analysis of changes</h3>
            <p>Status: <strong>{analysis_status(@review.revision_analysis)}</strong></p>
            <details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@review.revision_analysis) %></pre>
            </details>
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
                {step_result_label(step["result"])}
                <details :if={step["result"]} class="technical-details">
                  <summary>Technical details</summary><pre><%= json(step["result"]) %></pre>
                </details>
              </td>
            </tr>
          </tbody>
        </table>
        <div class="grid">
          <div class="card">
            <h3>Usage / incurred cost</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@progress["usage"]) %></pre>
            </details><p>
              Missing provider cost remains unknown; it is not displayed as zero.
            </p>
          </div>
          <div class="card">
            <h3>Provider requests / partial work</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@progress["provider_requests"]) %></pre>
            </details>
          </div>
          <div class="card">
            <h3>Approval attempts / recorded identity</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@progress["approval_attempts"]) %></pre>
            </details>
          </div>
        </div>
      </section>

      <section :if={@live_action == :decisions} class="stack">
        <h2>Decision inbox</h2>
        <p>
          Decisions apply to the saved version shown here. If it changes, reload and review before submitting.
        </p>
        <p :if={@pending_decisions == []}>No pending decisions.</p>
        <article :for={{decision, ordinal} <- Enum.with_index(@pending_decisions, 1)} class="card">
          <h3>Decision {ordinal} · {decision_kind_label(decision["kind"])}</h3>
          <p><strong>Question:</strong> {decision["prompt"]}</p>
          <details class="technical-details">
            <summary>Technical decision binding</summary><dl>
              <div>
                <dt>Decision identity</dt><dd><code>{decision["id"]}</code></dd>
              </div>
              <div>
                <dt>Version reference</dt><dd><code>{decision["context_fingerprint"]}</code></dd>
              </div>
            </dl>
          </details>
          <p :if={is_nil(@decision_contexts[decision["id"]]["analysis_lineage"])} role="status">
            Intelligence lineage: not recorded for this decision.
          </p>
          <div
            :if={!is_nil(@decision_contexts[decision["id"]]["analysis_lineage"])}
            class="decision-lineage"
          >
            <strong>Recorded Intelligence lineage</strong>
            <details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@decision_contexts[decision["id"]]["analysis_lineage"]) %></pre>
            </details>
          </div>
          <div class="grid">
            <div>
              <h4>Available choices and consequences</h4><details class="technical-details">
                <summary>Technical details</summary><pre><%= json(decision["options"]) %></pre>
              </details>
            </div>
            <div>
              <h4>Version details for this decision</h4><details class="technical-details">
                <summary>Technical details</summary><pre><%= json(Map.merge(Map.take(decision, ["candidate_id", "base_revision_id", "content_hash", "check_set_fingerprint", "plan_version", "policy_version"]), @decision_contexts[decision["id"]])) %></pre>
              </details>
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
            <button disabled={!@live_connected} type="submit">{decision_option_label(option)}</button>
          </form>
        </article>
      </section>

      <section :if={@live_action == :review} class="stack">
        <h2>Side-by-side candidate review</h2>
        <div class="grid">
          <div class="card">
            <h3>Analysis before writing</h3>
            <p>Status: <strong>{analysis_status(@review.pre_analysis)}</strong></p>
            <details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@review.pre_analysis) %></pre>
            </details>
          </div>
          <div class="card">
            <h3>Analysis of changes</h3>
            <p>Status: <strong>{analysis_status(@review.revision_analysis)}</strong></p>
            <details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@review.revision_analysis) %></pre>
            </details>
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
            <h3>Proposed change</h3><pre class="script"><%= @review.candidate %></pre>
          </div>
        </div>
        <div :if={@review.candidate} class="card intelligence-binding-card">
          <div>
            <p class="eyebrow">Analysis for this revision</p>
            <h3>Analysis of proposed changes</h3>
          </div>
          <details class="technical-details">
            <summary>Technical source binding</summary>
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
          </details>
          <p>
            Story observations do not replace required checks or your approval. Missing or outdated analysis is not a pass.
          </p>
          <a class="inline-action" href={"/p/#{@project_key}/analysis/#{@task_key}"}>Open saved analysis</a>
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
        <section
          :if={@review.candidate && @related_candidates != []}
          class="card stack candidate-workshop"
        >
          <div>
            <p class="eyebrow">Related work</p>
            <h3>Audition, select or recombine proposed writing</h3>
            <p>
              These operations save new Workshop candidates inside this task. They never make pages current.
              To use one as the task proposal, send it through the existing replacement checkpoint so required checks run again.
            </p>
          </div>

          <article :for={candidate <- @related_candidates} class="related-candidate">
            <div class="related-candidate__head">
              <div>
                <strong>{candidate["label"]}</strong>
                <span :if={candidate["id"] == @review.candidate_id} class="status-chip">Current task proposal</span>
              </div>
              <button
                type="button"
                phx-click="audition_candidate"
                phx-value-candidate_id={candidate["id"]}
                disabled={!@live_connected}
              >Audition in context</button>
            </div>

            <form
              :if={candidate["groups"] != []}
              phx-submit="select_candidate_groups"
              phx-change="candidate_selection_changed"
              class="stack"
            >
              <input type="hidden" name="candidate[id]" value={candidate["id"]} />
              <fieldset>
                <legend>Select saved changes</legend>
                <label :for={group <- candidate["groups"]} class="candidate-group">
                  <input
                    type="checkbox"
                    name="candidate[groups][]"
                    value={group["id"]}
                    checked={group["id"] in Map.get(@candidate_selections, candidate["id"], [])}
                  />
                  <span><strong>{group["title"]}</strong> — {group["reason"]}</span>
                </label>
              </fieldset>
              <button type="submit" disabled={!@live_connected}>Save selected changes as related proposal</button>
            </form>

            <button
              type="button"
              phx-click="use_related_candidate"
              phx-value-candidate_id={candidate["id"]}
              disabled={!@live_connected}
            >Use this as the task proposal and re-check</button>
          </article>

          <form
            :if={length(@related_candidates) >= 2}
            phx-submit="combine_candidates"
            phx-change="combine_selection_changed"
            class="stack combine-candidates"
          >
            <fieldset>
              <legend>Recombine selected change groups</legend>
              <p class="scope-note">
                Choose groups from at least two proposals. Conflicting edits are rejected rather than guessed.
              </p>
              <div :for={candidate <- @related_candidates} class="candidate-combine-source">
                <strong>{candidate["label"]}</strong>
                <label :for={group <- candidate["groups"]} class="candidate-group">
                  <input
                    type="checkbox"
                    name={"combine[groups][#{candidate["id"]}][]"}
                    value={group["id"]}
                    checked={group["id"] in List.wrap(Map.get(@combine_selections, candidate["id"]))}
                  />
                  <span>{group["title"]}</span>
                </label>
              </div>
            </fieldset>
            <button type="submit" disabled={!@live_connected}>Save recombined proposal</button>
          </form>

          <div :if={@audition} class="audition-panel" role="region" aria-label="Candidate audition">
            <div>
              <strong>Auditioned in saved task context</strong>
              <p>Neighboring scenes are included for continuity. No acceptance occurred.</p>
            </div>
            <pre class="script"><%= @audition["fountain"] %></pre>
          </div>
        </section>

        <div :if={@review.candidate} class="grid">
          <div class="card">
            <h3>Revision history</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(%{"provenance" => @review.provenance, "lineage" => @review.lineage, "result_revision_id" => @review.result_revision_id}) %></pre>
            </details>
          </div>
          <div class="card">
            <h3>Check details</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(%{"required_checks" => @review.required_checks, "check_set_fingerprint" => @review.check_set_fingerprint}) %></pre>
            </details>
          </div>
        </div>
        <div class="grid">
          <div class="card">
            <h3>Story observations</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@review.advisory_checks) %></pre>
            </details><p>
              These are advisory semantic findings. Partial or failed semantic analysis is never displayed as an advisory pass.
            </p>
          </div>
          <div class="card">
            <h3>Required checks</h3><details class="technical-details">
              <summary>Technical details</summary><pre><%= json(@review.required_run_checks) %></pre>
            </details><p>
              Required checks must be resolved before approval. Story observations are advice, not approval.
            </p>
          </div>
        </div>
        <div :if={@review.other_checks != []} class="card">
          <h3>Other recorded checks</h3><details class="technical-details">
            <summary>Technical details</summary><pre><%= json(@review.other_checks) %></pre>
          </details>
        </div>
        <p>
          Missing checks do not count as passes. Any permitted exception is recorded with your decision.
        </p>
        <p :if={@review.candidate}>
          Choosing a proposed revision and approving it are separate saved decisions. <a href={
            "/p/#{@project_key}/activity/#{@task_key}/decisions"
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
              <dt>Source</dt><dd>
                {if @export_preview["result_revision_id"],
                  do: "Current screenplay",
                  else: "Proposed writing"}
              </dd>
            </div>
            <div>
              <dt>Technical identity</dt><dd>
                <details class="technical-details">
                  <summary>Show identities</summary><dl>
                    <div>
                      <dt>Candidate identity</dt><dd>
                        <code>{@export_preview["candidate_id"]}</code>
                      </dd>
                    </div>
                    <div>
                      <dt>Result revision</dt><dd>
                        <code>{@export_preview["result_revision_id"] || "not accepted"}</code>
                      </dd>
                    </div>
                  </dl>
                </details>
              </dd>
            </div>
            <div>
              <dt>Fountain bytes</dt><dd>{@export_preview["fountain_bytes"]}</dd>
            </div>
            <div>
              <dt>FDX fidelity/loss report</dt><dd>
                <details class="technical-details">
                  <summary>Technical details</summary><pre><%= json(@export_preview["fdx_losses"]) %></pre>
                </details>
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
              <th>Format</th><th>Content</th><th>State</th><th>Details</th><th>
                Access
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{delivery, ordinal} <- Enum.with_index(@progress["deliveries"] || [], 1)}>
              <td>{delivery["format"]}</td>
              <td>{delivery_identity(delivery)}</td>
              <td>{delivery["state"]}</td>
              <td>
                <span :if={delivery["state"] == "failed"}>{delivery["error"] || "Delivery failed"}</span>
                <span :if={delivery["state"] != "failed"}>Saved output</span>
                <details :if={delivery["output_checksum"]} class="technical-details">
                  <summary>Technical details</summary><code>{delivery["output_checksum"]}</code>
                </details>
              </td>
              <td>
                <a
                  :if={delivery_previewable?(delivery)}
                  href={"/p/#{@project_key}/exports/#{@task_key}/delivery-#{ordinal}/preview"}
                >Preview</a>
                <span :if={delivery_previewable?(delivery)}> · </span>
                <a
                  :if={delivery["state"] == "ready"}
                  href={"/p/#{@project_key}/exports/#{@task_key}/delivery-#{ordinal}/download"}
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
