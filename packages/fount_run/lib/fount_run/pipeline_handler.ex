defmodule FountRun.PipelineHandler do
  @moduledoc "Durable Phase-04 screenplay stages that stop before acceptance or delivery."
  @behaviour FountRun.StageHandler

  alias Ecto.Adapters.SQL
  alias Fount.Persistence, as: CorePersistence
  alias Fount.Writing.{CanonicalJSON, Principal}
  alias FountRun.{DispatchHook, ExecutionStore, Persistence, PipelineRequest, WorkshopIntegration}
  alias FountWorkshop.Candidate
  alias FountWorkshop.{Session, Store}

  @stages ~w(intake investigate plan check iterate)
  @common_workshop_options ~w(protected_strengths intended_effect pending_question voice_exemplars protected_text style_preferences)

  @impl true
  def execute(%{"stage" => stage} = claim, opts) when stage in @stages do
    with {:ok, request} <- PipelineRequest.validate(claim["request"]) do
      case stage do
        "intake" -> intake(claim, request, opts)
        "investigate" -> investigate(claim, request, opts)
        "plan" -> plan(claim, request, opts)
        "check" -> check(claim, request, opts)
        "iterate" -> iterate(claim, request, opts)
      end
    end
  end

  def execute(%{"stage" => stage}, _opts), do: {:error, {:invalid_pipeline_stage, stage}}
  def execute(_, _opts), do: {:error, :invalid_pipeline_claim}

  defp intake(claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    context = Keyword.fetch!(opts, :actor_context)

    with {:ok, run} <- FountRun.get_run(repo, claim["run_id"], context),
         {:ok, model} <- load_base(repo, run),
         :ok <- exact_scope_binding(run, envelope["workshop_request"]),
         {:ok, preflight} <-
           Session.preflight(model, envelope["workshop_request"], max_repair_rounds: 0),
         {:ok, next} <- schedule(repo, claim, "investigate", envelope, context) do
      {:ok,
       %{
         "status" => "preflight_saved",
         "base_revision_id" => run["plan"]["base_revision_id"],
         "preflight" => preflight,
         "inspected_scope" => envelope["workshop_request"]["selection"],
         "omitted_scope" => omitted_scope(model, envelope["workshop_request"]["selection"]),
         "uncertainty" => [],
         "report_ids" => [],
         "scheduled_step_id" => next["id"],
         "changes_canon" => false
       }}
    end
  end

  defp investigate(claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    context = Keyword.fetch!(opts, :actor_context)

    with {:ok, run} <- FountRun.get_run(repo, claim["run_id"], context),
         {:ok, model} <- load_base(repo, run),
         {:ok, inference} <- inference(opts),
         services = WorkshopIntegration.guarded_services(repo, claim, inference, opts),
         investigation_request =
           envelope["investigation_request"] ||
             investigation_request(envelope["workshop_request"], run["plan"]),
         {:ok, stage_opts} <- workshop_opts(repo, claim, %{}, opts),
         {:ok, session} <-
           Session.prepare_only(model, investigation_request, services, stage_opts),
         {:ok, _} <- ExecutionStore.link_session(repo, claim, session["id"]),
         data = get_in(session, ["progress", "preparation", "context", "data"]) || %{},
         report_ids = get_in(session, ["progress", "report_ids"]) || [],
         uncertainty = uncertainty(data),
         {:ok, advanced} <-
           PipelineRequest.advance(envelope, %{
             investigation_request: investigation_request,
             investigation_session_id: session["id"],
             report_ids: Enum.uniq((envelope["report_ids"] || []) ++ report_ids),
             uncertainty: Enum.uniq((envelope["uncertainty"] || []) ++ uncertainty)
           }),
         {:ok, next} <- schedule(repo, claim, "plan", advanced, context) do
      {:ok,
       %{
         "status" => "investigation_saved",
         "session_id" => session["id"],
         "investigation" => Map.get(data, "investigation", data),
         "inspected_scope" => investigation_request["selection"],
         "omitted_scope" => omitted_scope(model, investigation_request["selection"]),
         "uncertainty" => uncertainty,
         "report_ids" => report_ids,
         "scheduled_step_id" => next["id"],
         "changes_canon" => false
       }}
    end
  end

  defp plan(claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    context = Keyword.fetch!(opts, :actor_context)

    with {:ok, run} <- FountRun.get_run(repo, claim["run_id"], context),
         {:ok, model} <- load_base(repo, run),
         {:ok, inference} <- inference(opts),
         services = WorkshopIntegration.guarded_services(repo, claim, inference, opts),
         {:ok, investigation_session} <-
           Store.call(services.store, :session, [envelope["investigation_session_id"]]),
         {:ok, stage_opts} <- workshop_opts(repo, claim, %{}, opts),
         stage_opts =
           Keyword.put(stage_opts, :investigation_seed, investigation_seed(investigation_session)),
         {:ok, session} <-
           Session.plan_only(model, envelope["workshop_request"], services, stage_opts),
         {:ok, _} <- ExecutionStore.link_session(repo, claim, session["id"]),
         [_ | _] = strategies <- session["strategies"],
         :ok <- no_pages_before_strategy(session, services),
         report_ids =
           Enum.uniq(
             (envelope["report_ids"] || []) ++ (get_in(session, ["progress", "report_ids"]) || [])
           ),
         {:ok, advanced} <-
           PipelineRequest.advance(envelope, %{
             strategy_session_id: session["id"],
             report_ids: report_ids
           }) do
      route_or_checkpoint(repo, claim, run, advanced, strategies, report_ids, context)
    else
      [] -> {:error, :no_strategy_routes}
      {:error, _} = error -> error
    end
  end

  defp investigation_seed(session) do
    cached = get_in(session, ["progress", "preparation", "context"]) || %{}
    data = cached["data"] || %{}

    %{
      "strategies" => cached["investigation_strategies"] || [],
      "report_ids" => get_in(session, ["progress", "report_ids"]) || [],
      "evidence" => cached["evidence"] || [],
      "uncertainty" => uncertainty(data),
      "data" => Map.get(data, "investigation", data),
      "writer_intelligence" => data["writer_intelligence"],
      "intelligence_preflight" => data["intelligence_preflight"]
    }
  end

  defp route_or_checkpoint(repo, claim, run, envelope, strategies, report_ids, context) do
    if strategy_decision_required?(run, strategies) do
      with {:ok, authorized} <- route_principal(run, context),
           attrs = %{
             "checkpoint_key" => "strategy:" <> envelope["strategy_session_id"],
             "kind" => "strategy",
             "prompt" => "Choose one saved dramatic route before screenplay page generation.",
             "options" => strategies,
             "step_id" => claim["step_id"],
             "base_revision_id" => run["plan"]["base_revision_id"],
             "authorized_principal" => Principal.to_map(authorized)
           },
           {:ok, decision} <-
             Persistence.put_pending_decision(repo, claim["run_id"], attrs, context) do
        {:ok,
         %{
           "status" => "strategy_checkpoint",
           "session_id" => envelope["strategy_session_id"],
           "strategies" => strategies,
           "decision_id" => decision["id"],
           "decision_context_fingerprint" => decision["context_fingerprint"],
           "report_ids" => report_ids,
           "uncertainty" => envelope["uncertainty"] || [],
           "run_status" => "waiting_for_decision",
           "next_stage" => "write",
           "changes_canon" => false
         }}
      end
    else
      selected = strategies |> Enum.sort_by(& &1["id"]) |> hd() |> Map.fetch!("id")

      with {:ok, write_request} <-
             PipelineRequest.advance(envelope, %{selected_strategy_ids: [selected]}),
           {:ok, next} <- schedule(repo, claim, "write", write_request, context) do
        {:ok,
         %{
           "status" => "strategy_selected_automatically",
           "session_id" => envelope["strategy_session_id"],
           "strategies" => strategies,
           "selected_strategy_ids" => [selected],
           "report_ids" => report_ids,
           "scheduled_step_id" => next["id"],
           "changes_canon" => false
         }}
      end
    end
  end

  defp check(claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    context = Keyword.fetch!(opts, :actor_context)
    candidate_id = List.last(envelope["candidate_ids"] || []) || claim["input_candidate_id"]
    services = %{store: Store.new(repo)}

    with true <- is_binary(candidate_id) or {:error, :candidate_required},
         {:ok, run} <- FountRun.get_run(repo, claim["run_id"], context),
         {:ok, candidate} <- Store.call(services.store, :candidate, [candidate_id]),
         :ok <- canonical_candidate(run, candidate) do
      checks = pipeline_checks(run, envelope, candidate)
      fingerprint = CanonicalJSON.hash(checks)

      reports =
        Enum.uniq(
          (envelope["report_ids"] || []) ++
            (get_in(candidate, ["provenance", "report_ids"]) || []) ++
            (get_in(candidate, ["provenance", "preparation_report_ids"]) || [])
        )

      check_outcome(%{
        repo: repo,
        claim: claim,
        run: run,
        envelope: envelope,
        candidate: candidate,
        checks: checks,
        fingerprint: fingerprint,
        reports: reports,
        failed: required_failures(checks),
        context: context
      })
    else
      false -> {:error, :candidate_required}
      {:error, _} = error -> error
    end
  end

  defp check_outcome(%{failed: []} = state) do
    %{
      repo: repo,
      claim: claim,
      envelope: envelope,
      candidate: candidate,
      checks: checks,
      fingerprint: fingerprint,
      reports: reports,
      context: context
    } = state

    with {:ok, next} <-
           schedule(
             repo,
             claim,
             "decide",
             envelope,
             context,
             candidate["id"],
             claim["iteration"]
           ) do
      {:ok,
       check_result(candidate, envelope, checks, fingerprint, reports)
       |> Map.merge(%{
         "status" => "completion_scheduled",
         "scheduled_step_id" => next["id"],
         "next_stage" => "decide"
       })}
    end
  end

  defp check_outcome(state) do
    %{
      repo: repo,
      claim: claim,
      run: run,
      envelope: envelope,
      candidate: candidate,
      checks: checks,
      fingerprint: fingerprint,
      reports: reports,
      failed: failed,
      context: context
    } = state

    iteration_gate = get_in(run, ["policy", "policy", "gates", "iteration"])
    max_iterations = get_in(run, ["policy", "policy", "limits", "max_iterations"]) || 0
    finding = failed |> hd() |> finding_text()

    cond do
      iteration_gate == "automatic" and claim["iteration"] < max_iterations ->
        with {:ok, next_request} <-
               PipelineRequest.advance(envelope, %{
                 source_candidate_id: candidate["id"],
                 finding: finding,
                 check_set_fingerprint: fingerprint,
                 lineage:
                   (envelope["lineage"] || []) ++
                     [%{"candidate_id" => candidate["id"], "operation" => "check"}]
               }),
             {:ok, next} <-
               schedule(
                 repo,
                 claim,
                 "iterate",
                 next_request,
                 context,
                 candidate["id"],
                 claim["iteration"] + 1
               ) do
          {:ok,
           check_result(candidate, envelope, checks, fingerprint, reports)
           |> Map.merge(%{
             "status" => "repair_scheduled",
             "finding" => finding,
             "scheduled_step_id" => next["id"]
           })}
        end

      iteration_gate == "human" and claim["iteration"] < max_iterations ->
        iteration_checkpoint(state, finding, "waiting_for_decision")

      true ->
        iteration_checkpoint(state, finding, "partial")
    end
  end

  defp iteration_checkpoint(state, finding, status) do
    %{
      repo: repo,
      claim: claim,
      run: run,
      envelope: envelope,
      candidate: candidate,
      checks: checks,
      fingerprint: fingerprint,
      reports: reports,
      context: context
    } = state

    attrs = %{
      "checkpoint_key" => "iteration:" <> candidate["id"] <> ":" <> fingerprint,
      "kind" => "iteration",
      "prompt" =>
        "Required checks remain unresolved; bounded iteration cannot continue automatically.",
      "options" => [%{"id" => "review", "label" => "Review unresolved finding"}],
      "step_id" => claim["step_id"],
      "candidate_id" => candidate["id"],
      "base_revision_id" => run["plan"]["base_revision_id"],
      "content_hash" => candidate["screenplay"].revision.content_hash,
      "check_set_fingerprint" => fingerprint
    }

    with {:ok, decision} <-
           Persistence.put_pending_decision(repo, claim["run_id"], attrs, context) do
      {:ok,
       check_result(candidate, envelope, checks, fingerprint, reports)
       |> Map.merge(%{
         "status" => "iteration_checkpoint",
         "finding" => finding,
         "decision_id" => decision["id"],
         "decision_context_fingerprint" => decision["context_fingerprint"],
         "run_status" => status,
         "next_stage" => "decide"
       })}
    end
  end

  defp iterate(claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    context = Keyword.fetch!(opts, :actor_context)
    source_id = envelope["source_candidate_id"] || claim["input_candidate_id"]
    read_services = %{store: Store.new(repo)}

    with true <- is_binary(source_id) or {:error, :source_candidate_required},
         {:ok, run} <- FountRun.get_run(repo, claim["run_id"], context),
         max_iterations = get_in(run, ["policy", "policy", "limits", "max_iterations"]) || 0,
         :ok <- check_iteration_limit(claim["iteration"], max_iterations),
         {:ok, source} <- Store.call(read_services.store, :candidate, [source_id]),
         :ok <- canonical_candidate(run, source),
         {:ok, model} <- load_base(repo, run),
         {:ok, inference} <- inference(opts),
         services = WorkshopIntegration.guarded_services(repo, claim, inference, opts),
         repair_request = repair_request(envelope["workshop_request"], envelope["finding"]),
         {:ok, stage_opts} <- workshop_opts(repo, claim, %{}, opts),
         source_packet = %{
           "proposal" => Candidate.proposal(source),
           "pages" => Fount.Screenplay.to_fountain(source["screenplay"], mode: :spec)
         },
         {:ok, session} <-
           Session.start(
             model,
             repair_request,
             services,
             stage_opts ++ [source_candidate: source_packet, parent_candidate_id: source["id"]]
           ),
         {:ok, _} <- ExecutionStore.link_session(repo, claim, session["id"]),
         candidates <- load_session_candidates(session, services),
         [candidate | _] <- candidates,
         true <-
           candidate["parent_candidate_id"] == source["id"] or
             {:error, :candidate_lineage_mismatch},
         true <-
           candidate["base_revision_id"] == run["plan"]["base_revision_id"] or
             {:error, :candidate_base_mismatch},
         report_ids <- report_ids(session, candidates),
         candidate_ids <- Enum.map(candidates, & &1["id"]),
         {:ok, advanced} <-
           PipelineRequest.advance(envelope, %{
             candidate_ids: candidate_ids,
             report_ids: Enum.uniq((envelope["report_ids"] || []) ++ report_ids),
             lineage:
               (envelope["lineage"] || []) ++
                 [
                   %{
                     "candidate_id" => candidate["id"],
                     "parent_candidate_id" => source["id"],
                     "operation" => "iterate"
                   }
                 ]
           }),
         {:ok, next} <-
           schedule(repo, claim, "check", advanced, context, candidate["id"], claim["iteration"]) do
      {:ok,
       %{
         "status" => "iteration_saved",
         "session_id" => session["id"],
         "source_candidate_id" => source["id"],
         "candidate_id" => candidate["id"],
         "candidate_ids" => candidate_ids,
         "revision_id" => candidate["result_revision_id"],
         "report_ids" => report_ids,
         "checks" => Enum.flat_map(candidates, &(get_in(&1, ["provenance", "checks"]) || [])),
         "lineage" => advanced["lineage"],
         "scheduled_step_id" => next["id"],
         "changes_canon" => false
       }}
    else
      false -> {:error, :source_candidate_required}
      [] -> {:error, :iteration_produced_no_candidate}
      {:error, reason, _saved} -> {:error, reason}
      {:error, _} = error -> error
    end
  end

  defp schedule(repo, claim, stage, request, context, input_candidate_id \\ nil, iteration \\ nil) do
    Persistence.create_step(
      repo,
      claim["run_id"],
      %{
        "stage" => stage,
        "iteration" => if(is_nil(iteration), do: claim["iteration"], else: iteration),
        "branch_id" => claim["branch_id"] || "main",
        "input_revision_id" => claim["input_revision_id"] || base_revision(repo, claim),
        "input_candidate_id" => input_candidate_id,
        "idempotency_key" => claim["operation_key"] <> ":next:" <> stage,
        "request" => request
      },
      context
    )
  end

  defp exact_scope_binding(run, workshop_request) do
    if CanonicalJSON.hash(run["plan"]["scope"]) ==
         CanonicalJSON.hash(workshop_request["selection"]),
       do: :ok,
       else: {:error, :plan_request_scope_mismatch}
  end

  defp investigation_request(request, plan) do
    common =
      request["options"]
      |> Map.take(@common_workshop_options)
      |> Map.merge(%{"concern" => plan["goal"], "write_fixes" => false})

    %{
      "version" => 1,
      "workflow" => "investigate",
      "mode" => "inspect",
      "base_revision_id" => plan["base_revision_id"],
      "instruction" => request["instruction"],
      "selection" => request["selection"],
      "constraints" => request["constraints"] || [],
      "alternatives" => min(request["alternatives"] || 2, 3),
      "options" => common
    }
  end

  defp repair_request(request, finding) do
    common = Map.take(request["options"] || %{}, @common_workshop_options)

    direction =
      "Repair only the saved required-check finding while preserving successful work: " <>
        to_string(finding || "unresolved required check")

    %{
      "version" => 1,
      "workflow" => "pass",
      "mode" => "revise",
      "base_revision_id" => request["base_revision_id"],
      "instruction" => direction,
      "selection" => request["selection"],
      "constraints" => request["constraints"] || [],
      "alternatives" => 1,
      "options" => Map.merge(common, %{"profile" => "custom", "direction" => direction})
    }
  end

  defp strategy_decision_required?(run, strategies) do
    get_in(run, ["policy", "policy", "gates", "strategy_choice"]) == "human" or
      get_in(run, ["policy", "policy", "route_choice", "rule"]) == "registered_reviewer" or
      length(strategies) > 1
  end

  defp route_principal(run, context) do
    case get_in(run, ["policy", "policy", "route_choice"]) do
      %{"rule" => "registered_reviewer", "reviewer_id" => id} -> Principal.new(:human, id)
      _ -> {:ok, context.owner}
    end
  end

  defp no_pages_before_strategy(session, services) do
    case Store.call(services.store, :candidates_for_session, [session["id"]]) do
      [] -> :ok
      {:error, _} = error -> error
      _ -> {:error, :pages_generated_before_strategy_decision}
    end
  end

  defp check_result(candidate, envelope, checks, fingerprint, reports) do
    %{
      "candidate_id" => candidate["id"],
      "candidate_ids" => Enum.uniq((envelope["candidate_ids"] || []) ++ [candidate["id"]]),
      "revision_id" => candidate["result_revision_id"],
      "checks" => checks,
      "check_set_fingerprint" => fingerprint,
      "report_ids" => reports,
      "uncertainty" => envelope["uncertainty"] || [],
      "lineage" => Enum.uniq((envelope["lineage"] || []) ++ (candidate["lineage"] || [])),
      "changes_canon" => false
    }
  end

  defp pipeline_checks(run, envelope, candidate) do
    inherited = get_in(candidate, ["provenance", "checks"]) || []

    inherited ++
      [scope_check(run, envelope, candidate)] ++
      protected_checks(run["plan"]["protected_material"], candidate)
  end

  defp scope_check(run, envelope, candidate) do
    pass =
      candidate["base_revision_id"] == run["plan"]["base_revision_id"] and
        CanonicalJSON.hash(run["plan"]["scope"]) ==
          CanonicalJSON.hash(envelope["workshop_request"]["selection"])

    %{
      "constraint_id" => "run:scope-binding",
      "kind" => "scope",
      "severity" => "required",
      "status" => if(pass, do: "pass", else: "fail"),
      "source" => "run",
      "message" =>
        if(pass,
          do: "Candidate remains rooted in the authorized canonical base and scope.",
          else: "Candidate base/scope binding changed."
        )
    }
  end

  defp protected_checks([], _candidate) do
    [
      %{
        "constraint_id" => "run:protected-material",
        "kind" => "protected_material",
        "severity" => "required",
        "status" => "pass",
        "source" => "run",
        "message" => "No protected material was declared."
      }
    ]
  end

  defp protected_checks(items, candidate) do
    Enum.with_index(items)
    |> Enum.map(fn {item, index} -> protected_check(item, candidate, index) end)
  end

  defp protected_check(item, candidate, index) do
    status = protected_status(item, candidate)

    %{
      "constraint_id" => "run:protected-material:" <> Integer.to_string(index + 1),
      "kind" => "protected_material",
      "severity" => "required",
      "status" => status,
      "source" => "run",
      "message" => protected_message(status)
    }
  end

  defp protected_status(text, candidate) when is_binary(text) do
    if String.contains?(Fount.Screenplay.to_fountain(candidate["screenplay"], mode: :spec), text),
      do: "pass",
      else: "fail"
  end

  defp protected_status(%{"element_id" => id, "text" => text}, candidate)
       when is_binary(id) and is_binary(text) do
    case Fount.Query.node(candidate["screenplay"], id) do
      nil -> "fail"
      node -> if node.text == text, do: "pass", else: "fail"
    end
  end

  defp protected_status(%{"element_id" => id, "sha256" => sha}, candidate)
       when is_binary(id) and is_binary(sha) do
    case Fount.Query.node(candidate["screenplay"], id) do
      nil -> "fail"
      node -> if sha256(node.text) == sha, do: "pass", else: "fail"
    end
  end

  defp protected_status(%{"text" => text}, candidate) when is_binary(text),
    do: protected_status(text, candidate)

  defp protected_status(_, _candidate), do: "unknown"

  defp protected_message("pass"), do: "Protected material is unchanged."
  defp protected_message("fail"), do: "Protected material changed or disappeared."
  defp protected_message(_), do: "Protected material shape cannot be proven automatically."

  defp required_failures(checks),
    do:
      Enum.filter(checks, &(&1["severity"] == "required" and &1["status"] in ["fail", "unknown"]))

  defp finding_text(check),
    do: check["message"] || check["constraint_id"] || "required check failed"

  defp canonical_candidate(run, candidate) do
    cond do
      candidate["screenplay_id"] != run["screenplay_id"] ->
        {:error, :candidate_screenplay_mismatch}

      candidate["base_revision_id"] != run["plan"]["base_revision_id"] ->
        {:error, :candidate_base_mismatch}

      true ->
        :ok
    end
  end

  defp load_session_candidates(session, services) do
    session
    |> Map.get("progress", %{})
    |> Map.get("branches", %{})
    |> Map.values()
    |> Enum.map(& &1["candidate_id"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn id ->
      case Store.call(services.store, :candidate, [id]) do
        {:ok, candidate} -> [candidate]
        _ -> []
      end
    end)
  end

  defp report_ids(session, candidates) do
    Enum.uniq(
      (get_in(session, ["progress", "report_ids"]) || []) ++
        Enum.flat_map(candidates, fn candidate ->
          get_in(candidate, ["provenance", "report_ids"]) || []
        end)
    )
  end

  defp uncertainty(data) do
    [
      data["uncertainty"],
      data["uncertainties"],
      data["unknowns"],
      data["unresolved_questions"],
      get_in(data, ["investigation", "uncertainty"]),
      get_in(data, ["investigation", "uncertainties"])
    ]
    |> Enum.flat_map(fn
      list when is_list(list) -> list
      value when is_binary(value) -> [value]
      _ -> []
    end)
    |> Enum.filter(&FountRun.ClosedMap.json?/1)
  end

  defp omitted_scope(model, selection) do
    case Fount.Selection.selected_ids(model, selection) do
      {:ok, selected} ->
        model.ir.elements
        |> Enum.map(& &1.id)
        |> Enum.reject(&MapSet.member?(selected, &1))

      _ ->
        []
    end
  end

  defp load_base(repo, run),
    do: CorePersistence.load_revision(repo, run["screenplay_id"], run["plan"]["base_revision_id"])

  defp inference(opts) do
    case Keyword.fetch(opts, :inference) do
      {:ok, inference} -> {:ok, inference}
      :error -> {:error, :inference_unavailable}
    end
  end

  defp workshop_opts(repo, claim, spent, opts) do
    with {:ok, limits} <- ExecutionStore.remaining_limits(repo, claim) do
      counter = :atomics.new(1, signed: false)
      :atomics.put(counter, 1, claim["measurement_state_count"] || 0)

      reservation_hook = fn
        :measurement_states, n ->
          start = :atomics.add_get(counter, 1, n) - n

          operation_id =
            claim["operation_key"] <>
              ":measurement:" <> Integer.to_string(start) <> ":" <> Integer.to_string(n)

          ExecutionStore.reserve_measurement(repo, claim, operation_id, n)

        _kind, n ->
          {:ok, n}
      end

      stage_opts =
        [
          operation_key: claim["operation_key"],
          max_inference_calls: Map.get(spent, "inference", 0) + limits.max_inference_calls,
          max_measurement_states:
            Map.get(spent, "measurement_states", 0) + limits.max_measurement_states,
          max_repair_rounds: 0,
          decode_repairs: limits.decode_repairs,
          transient_retries: limits.transient_retries,
          reserved_cost_microunits: Keyword.get(opts, :reserved_cost_microunits),
          currency: Keyword.get(opts, :currency),
          reservation_hook: reservation_hook,
          dispatch_hook: DispatchHook.new(repo, claim, opts)
        ]
        |> WorkshopIntegration.durable_analysis_options(claim, opts)

      {:ok, stage_opts}
    end
  end

  defp base_revision(repo, claim) do
    SQL.query!(
      repo,
      "SELECT base_revision_id::text FROM fount_run_plans WHERE run_id=$1::text::uuid AND version=$2",
      [claim["run_id"], claim["plan_version"]],
      log: false
    ).rows
    |> hd()
    |> hd()
  end

  defp check_iteration_limit(iteration, maximum) when iteration <= maximum, do: :ok
  defp check_iteration_limit(_, _), do: {:error, :iteration_limit_reached}

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
