defmodule FountRun.WorkshopHandler do
  @moduledoc "Workshop stage adapter retaining the Phase 03 write lane and adding Phase 04 selected-route materialization."
  @behaviour FountRun.StageHandler

  alias Ecto.Adapters.SQL
  alias FountRun.{DispatchHook, ExecutionStore, Persistence, PipelineRequest}
  alias FountWorkshop.{Session, Store}
  alias FountWorkshop.Strategy

  @impl true
  def execute(claim, opts) do
    case PipelineRequest.validate(claim["request"]) do
      {:ok, envelope} -> execute_pipeline_write(claim, envelope, opts)
      {:error, _} -> execute_legacy_write(claim, opts)
    end
  end

  defp execute_legacy_write(claim, opts) do
    repo = Keyword.fetch!(opts, :repo)
    base_revision_id = claim["input_revision_id"] || base_revision(repo, claim)

    with {:ok, inference} <- inference(opts),
         {:ok, model} <-
           Fount.Persistence.load_revision(repo, claim["screenplay_id"], base_revision_id),
         services = guarded_services(repo, claim, inference),
         {:ok, session} <-
           Session.open(model, claim["request"], services,
             operation_key: claim["operation_key"],
             max_repair_rounds: 0
           ),
         :ok <- fault(opts, :after_session_open),
         {:ok, _} <- ExecutionStore.link_session(repo, claim, session["id"]),
         :ok <- fault(opts, :after_session_link),
         claim = Map.put(claim, "session_id", session["id"]),
         {:ok, limits} <- ExecutionStore.remaining_limits(repo, claim) do
      run_session(claim, session, services, limits, opts)
    end
  end

  defp execute_pipeline_write(claim, envelope, opts) do
    repo = Keyword.fetch!(opts, :repo)
    context = Keyword.fetch!(opts, :actor_context)
    session_id = envelope["strategy_session_id"]
    selected = envelope["selected_strategy_ids"] || []

    with true <- is_binary(session_id) or {:error, :strategy_session_required},
         true <- selected != [] or {:error, :strategy_selection_required},
         :ok <- verify_strategy_authorization(repo, claim, envelope),
         {:ok, inference} <- inference(opts),
         services = guarded_services(repo, claim, inference),
         {:ok, session} <- Store.call(services.store, :session, [session_id]),
         true <- Enum.all?(selected, &Enum.any?(session["strategies"] || [], fn s -> s["id"] == &1 end)) or
                   {:error, :unknown_strategy_selection},
         {:ok, _} <- ExecutionStore.link_session(repo, claim, session_id),
         claim = Map.put(claim, "session_id", session_id),
         {:ok, limits} <- ExecutionStore.remaining_limits(repo, claim),
         {:ok, saved_session} <- run_selected_session(claim, session, selected, services, limits, opts),
         write_result = result(saved_session, services),
         [_ | _] = candidate_ids <- write_result["candidate_ids"],
         {:ok, next_request} <-
           PipelineRequest.advance(envelope, %{
             candidate_ids: candidate_ids,
             report_ids: Enum.uniq((envelope["report_ids"] || []) ++ write_result["report_ids"]),
             lineage: (envelope["lineage"] || []) ++ Enum.map(candidate_ids, &%{"candidate_id" => &1, "operation" => "write"})
           }),
         {:ok, next} <-
           Persistence.create_step(
             repo,
             claim["run_id"],
             %{
               "stage" => "check",
               "iteration" => claim["iteration"],
               "branch_id" => claim["branch_id"] || "main",
               "input_revision_id" => claim["input_revision_id"] || base_revision(repo, claim),
               "input_candidate_id" => hd(candidate_ids),
               "idempotency_key" => claim["operation_key"] <> ":next:check",
               "request" => next_request
             },
             context
           ) do
      {:ok,
       write_result
       |> Map.put("status", "selected_route_materialized")
       |> Map.put("selected_strategy_ids", selected)
       |> Map.put("selection_decision_id", envelope["decision_id"])
       |> Map.put("scheduled_step_id", next["id"])}
    else
      false -> {:error, :strategy_session_required}
      [] -> {:error, :write_produced_no_candidate}
      {:error, reason, partial} when is_map(partial) -> {:partial, reason, result(partial, guarded_services(repo, claim, Keyword.fetch!(opts, :inference)))}
      {:error, _} = error -> error
    end
  end

  defp run_session(claim, session, services, limits, opts) do
    repo = Keyword.fetch!(opts, :repo)
    spent = get_in(session, ["progress", "spent"]) || %{}
    measurement_counter = :atomics.new(1, signed: false)
    :atomics.put(measurement_counter, 1, claim["measurement_state_count"] || 0)

    reservation_hook = fn
      :measurement_states, n ->
        start = :atomics.add_get(measurement_counter, 1, n) - n

        operation_id =
          claim["operation_key"] <>
            ":measurement:" <> Integer.to_string(start) <> ":" <> Integer.to_string(n)

        case ExecutionStore.reserve_measurement(repo, claim, operation_id, n) do
          {:ok, granted} -> {:ok, granted}
          {:error, _} = error -> error
        end

      _kind, n ->
        {:ok, n}
    end

    dispatch_hook = DispatchHook.new(repo, claim, opts)

    session_opts = [
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
      dispatch_hook: dispatch_hook
    ]

    case Session.resume(session["id"], services, session_opts) do
      {:ok, saved_session} ->
        :ok = fault(opts, :after_candidate_persisted)
        {:ok, result(saved_session, services)}

      {:error, reason, partial_session} when is_map(partial_session) ->
        {:partial, reason, result(partial_session, services)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_selected_session(claim, session, selected, services, limits, opts) do
    spent = get_in(session, ["progress", "spent"]) || %{}
    measurement_counter = :atomics.new(1, signed: false)
    :atomics.put(measurement_counter, 1, claim["measurement_state_count"] || 0)

    reservation_hook = fn
      :measurement_states, n ->
        start = :atomics.add_get(measurement_counter, 1, n) - n
        operation_id = claim["operation_key"] <> ":measurement:" <> Integer.to_string(start) <> ":" <> Integer.to_string(n)
        ExecutionStore.reserve_measurement(Keyword.fetch!(opts, :repo), claim, operation_id, n)
      _kind, n -> {:ok, n}
    end

    session_opts = [
      operation_key: claim["operation_key"],
      strategy_ids: selected,
      max_inference_calls: Map.get(spent, "inference", 0) + limits.max_inference_calls,
      max_measurement_states: Map.get(spent, "measurement_states", 0) + limits.max_measurement_states,
      max_repair_rounds: 0,
      decode_repairs: limits.decode_repairs,
      transient_retries: limits.transient_retries,
      reserved_cost_microunits: Keyword.get(opts, :reserved_cost_microunits),
      currency: Keyword.get(opts, :currency),
      reservation_hook: reservation_hook,
      dispatch_hook: DispatchHook.new(Keyword.fetch!(opts, :repo), claim, opts)
    ]

    case Strategy.materialize(session["id"], selected, services, session_opts) do
      {:ok, saved} ->
        :ok = fault(opts, :after_candidate_persisted)
        {:ok, saved}
      {:error, reason, partial} when is_map(partial) -> {:error, reason, partial}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_strategy_authorization(repo, claim, envelope) do
    policy =
      SQL.query!(
        repo,
        "SELECT policy FROM fount_run_policies WHERE run_id=$1::text::uuid AND version=$2",
        [claim["run_id"], claim["policy_version"]],
        log: false
      ).rows
      |> hd()
      |> hd()

    requires_decision =
      get_in(policy, ["gates", "strategy_choice"]) == "human" or
        get_in(policy, ["route_choice", "rule"]) == "registered_reviewer"

    case {requires_decision, envelope["decision_id"]} do
      {false, nil} -> :ok
      {true, nil} -> {:error, :strategy_decision_required}
      {_required, decision_id} -> verify_resolved_decision(repo, claim, envelope, decision_id)
    end
  end

  defp verify_resolved_decision(repo, claim, envelope, decision_id) do
    case SQL.query!(
           repo,
           "SELECT status,plan_version,policy_version,response FROM fount_run_decisions WHERE id=$1::text::uuid AND run_id=$2::text::uuid AND kind='strategy'",
           [decision_id, claim["run_id"]],
           log: false
         ).rows do
      [["resolved", plan_version, policy_version, %{"choice" => choice}]]
      when plan_version == claim["plan_version"] and policy_version == claim["policy_version"] ->
        if envelope["selected_strategy_ids"] == [choice], do: :ok, else: {:error, :strategy_decision_mismatch}

      [["resolved", _, _, _]] -> {:error, :stale_decision}
      [[_, _, _, _]] -> {:error, :strategy_decision_unresolved}
      [] -> {:error, :strategy_decision_not_found}
    end
  end

  defp inference(opts) do
    case Keyword.fetch(opts, :inference) do
      {:ok, inference} -> {:ok, inference}
      :error -> {:error, :inference_unavailable}
    end
  end

  defp guarded_services(repo, claim, inference) do
    guard = fn kind, identity -> ExecutionStore.domain_guard(repo, claim, kind, identity) end
    %{store: Store.new(repo, guard: guard), inference: inference}
  end

  defp result(session, services) do
    branches = Map.values(get_in(session, ["progress", "branches"]) || %{})
    candidate_ids = candidate_ids(branches)
    candidates = load_candidates(services, candidate_ids)
    first = List.first(candidates)

    %{
      "session_id" => session["id"],
      "status" => session["status"],
      "candidate_id" => if(first, do: first["id"]),
      "candidate_ids" => candidate_ids,
      "revision_id" => if(first, do: first["result_revision_id"]),
      "report_ids" => report_ids(session, branches),
      "checks" => Enum.flat_map(candidates, &(get_in(&1, ["provenance", "checks"]) || [])),
      "usage" => get_in(session, ["progress", "spent"]) || %{},
      "changes_canon" => false
    }
  end

  defp candidate_ids(branches) do
    branches
    |> Enum.map(& &1["candidate_id"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp load_candidates(services, ids) do
    Enum.flat_map(ids, fn id ->
      case Store.call(services[:store], :candidate, [id]) do
        {:ok, candidate} -> [candidate]
        _ -> []
      end
    end)
  end

  defp report_ids(session, branches) do
    Enum.uniq(
      (get_in(session, ["progress", "report_ids"]) || []) ++
        Enum.flat_map(branches, &(&1["report_ids"] || []))
    )
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

  defp fault(opts, stage) do
    case Keyword.get(opts, :fault_injector) do
      nil -> :ok
      fun when is_function(fun, 1) -> fun.(stage)
    end
  end
end
