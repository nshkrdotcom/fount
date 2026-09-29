defmodule FountRun.WorkshopHandler do
  @moduledoc "Phase-03 real Workshop operation adapter: durable open/link/resume and candidate persistence."
  @behaviour FountRun.StageHandler

  alias FountRun.{DispatchHook, ExecutionStore}
  alias FountWorkshop.{Session, Store}

  @impl true
  def execute(claim, opts) do
    repo = Keyword.fetch!(opts, :repo)
    base_revision_id = claim["input_revision_id"] || base_revision(repo, claim)

    with {:ok, inference} <- inference(opts),
         {:ok, model} <- Fount.Persistence.load_revision(repo, claim["screenplay_id"], base_revision_id),
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

  defp run_session(claim, session, services, limits, opts) do
    repo = Keyword.fetch!(opts, :repo)
    spent = get_in(session, ["progress", "spent"]) || %{}
    measurement_counter = :atomics.new(1, signed: false)
    :atomics.put(measurement_counter, 1, claim["measurement_state_count"] || 0)

    reservation_hook = fn
      :measurement_states, n ->
        start = :atomics.add_get(measurement_counter, 1, n) - n
        operation_id = claim["operation_key"] <> ":measurement:" <> Integer.to_string(start) <> ":" <> Integer.to_string(n)

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
      reservation_hook: reservation_hook,
      dispatch_hook: dispatch_hook
    ]

    case Session.resume(session["id"], services, session_opts) do
      {:ok, saved_session} ->
        {:ok, result(saved_session, services)}

      {:error, reason, partial_session} when is_map(partial_session) ->
        {:partial, reason, result(partial_session, services)}

      {:error, reason} ->
        {:error, reason}
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

    candidate_ids =
      branches
      |> Enum.map(& &1["candidate_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    candidates =
      Enum.flat_map(candidate_ids, fn id ->
        case Store.call(services[:store], :candidate, [id]) do
          {:ok, candidate} -> [candidate]
          _ -> []
        end
      end)

    first = List.first(candidates)

    %{
      "session_id" => session["id"],
      "status" => session["status"],
      "candidate_id" => if(first, do: first["id"]),
      "candidate_ids" => candidate_ids,
      "revision_id" => if(first, do: first["result_revision_id"]),
      "report_ids" =>
        Enum.uniq(
          (get_in(session, ["progress", "report_ids"]) || []) ++
            Enum.flat_map(branches, &(&1["report_ids"] || []))
        ),
      "checks" => Enum.flat_map(candidates, &(get_in(&1, ["provenance", "checks"]) || [])),
      "usage" => get_in(session, ["progress", "spent"]) || %{},
      "changes_canon" => false
    }
  end

  defp base_revision(repo, claim) do
    Ecto.Adapters.SQL.query!(
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
