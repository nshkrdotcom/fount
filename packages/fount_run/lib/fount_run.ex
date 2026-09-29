defmodule FountRun do
  @moduledoc """
  Durable Run foundation for Fount.

  Phase 03 retains the Phase 02 immutable storage/approval contracts and adds a
  fenced engine for one bounded operation at a time: enqueue, claim, heartbeat,
  execute, checkpoint, reconcile and inspect. It does not schedule the Phase 04
  screenplay pipeline, choose strategies, dispatch approvers, accept canon or
  deliver artifacts.
  """

  alias FountRun.Persistence

  @spec migrations_path() :: String.t()
  def migrations_path, do: Application.app_dir(:fount_run, "priv/repo/migrations")

  def start_run(repo, attrs, actor_context, opts \\ []) do
    repo
    |> Persistence.start_run(attrs, actor_context, opts)
    |> emit(:start_run)
  end

  def get_run(repo, run_id, actor_context) do
    repo
    |> Persistence.get_run(run_id, actor_context)
    |> emit(:get_run)
  end

  def list_runs(repo, filter, actor_context) do
    repo
    |> Persistence.list_runs(filter, actor_context)
    |> emit(:list_runs)
  end

  @doc "Creates one explicit durable operation; Phase 04 is responsible for workflow scheduling."
  def enqueue_step(repo, run_id, attrs, actor_context) do
    repo
    |> Persistence.create_step(run_id, attrs, actor_context)
    |> emit(:enqueue_step)
  end

  @doc "Claims and executes at most one durable operation."
  def step(repo, run_id, actor_context, opts \\ []) do
    repo
    |> FountRun.Engine.step(run_id, actor_context, opts)
    |> emit(:step)
  end

  @doc "Returns persisted run/step/provider usage without prompts or provider response bodies."
  def progress(repo, run_id, actor_context) do
    repo
    |> FountRun.ExecutionStore.progress(run_id, actor_context)
    |> emit(:progress)
  end

  # Writer-facing pause/stop/approve/deliver commands remain deliberately absent;
  # they arrive only with their Phase 05 authorization and stale-base semantics.

  defp emit({:ok, _value} = result, operation) do
    :telemetry.execute([:fount_run, operation], %{system_time: System.system_time()}, %{
      status: :ok
    })

    result
  end

  defp emit({:error, reason} = result, operation) do
    :telemetry.execute([:fount_run, operation], %{system_time: System.system_time()}, %{
      status: :error,
      reason: reason_tag(reason)
    })

    result
  end

  defp reason_tag(reason) when is_atom(reason), do: reason
  defp reason_tag({reason, _detail}) when is_atom(reason), do: reason
  defp reason_tag(_reason), do: :error
end
