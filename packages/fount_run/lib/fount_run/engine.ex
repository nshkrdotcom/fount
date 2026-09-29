defmodule FountRun.Engine do
  @moduledoc "Executes exactly one claimed durable Run step; Phase 04 handlers schedule persisted successors without changing the engine contract."

  alias FountRun.{ExecutionStore, StageRegistry}

  def step(repo, run_id, context, opts \\ []) do
    worker_id = Keyword.get(opts, :worker_id, default_worker_id())

    with {:ok, registry} <- registry(opts),
         {:ok, claim} <- ExecutionStore.claim(repo, run_id, worker_id, context, opts),
         :ok <- fault(opts, :after_claim) do
      execute_claim(repo, claim, registry, context, opts)
    end
  end

  defp execute_claim(repo, claim, registry, context, opts) do
    case StageRegistry.fetch(registry, claim["stage"]) do
      {:ok, handler} ->
        with_heartbeat(repo, claim, opts, fn -> run_handler(repo, claim, handler, context, opts) end)

      {:error, reason} ->
        _ = ExecutionStore.fail(repo, claim, reason)
        {:error, reason}
    end
  end

  defp run_handler(repo, claim, handler, context, opts) do
    handler_opts =
      opts
      |> Keyword.put(:repo, repo)
      |> Keyword.put(:actor_context, context)

    case handler.execute(claim, handler_opts) do
      {:ok, result} when is_map(result) ->
        complete_and_fault(repo, claim, result, opts)

      {:partial, reason, details} when is_map(details) ->
        ExecutionStore.partial(repo, claim, reason, details)

      {:error, reason} ->
        ExecutionStore.fail(repo, claim, reason)
        {:error, reason}

      other ->
        ExecutionStore.fail(repo, claim, :invalid_stage_handler_result)
        {:error, {:invalid_stage_handler_result, other}}
    end
  end

  defp complete_and_fault(repo, claim, result, opts) do
    case ExecutionStore.complete(repo, claim, result) do
      {:ok, _} = completed ->
        :ok = fault(opts, :after_step_completed)
        completed

      other ->
        other
    end
  end

  defp with_heartbeat(repo, claim, opts, fun) do
    interval = Keyword.get(opts, :heartbeat_ms, max(div(claim["lease_ms"], 3), 500))
    parent = self()

    {:ok, pid} =
      Task.start_link(fn ->
        heartbeat_loop(repo, claim, interval, opts, parent)
      end)

    try do
      fun.()
    after
      send(pid, :stop)
    end
  end

  defp heartbeat_loop(repo, claim, interval, opts, parent) do
    receive do
      :stop ->
        :ok
    after
      interval ->
        if Process.alive?(parent) do
          _ =
            ExecutionStore.heartbeat(repo, claim,
              lease_ms: Keyword.get(opts, :lease_ms, claim["lease_ms"])
            )

          heartbeat_loop(repo, claim, interval, opts, parent)
        end
    end
  end

  defp registry(opts) do
    case Keyword.get(opts, :registry) do
      nil -> StageRegistry.new()
      registry when is_map(registry) -> StageRegistry.new(registry)
      _ -> {:error, :invalid_stage_registry}
    end
  end

  defp fault(opts, stage) do
    case Keyword.get(opts, :fault_injector) do
      nil -> :ok
      fun when is_function(fun, 1) -> fun.(stage)
    end
  end

  defp default_worker_id do
    "direct:" <>
      Atom.to_string(node()) <> ":" <> Integer.to_string(System.unique_integer([:positive]))
  end
end
