defmodule FountRun do
  @moduledoc """
  Durable Run foundation for Fount.

  Phase 02 implements run creation/read/list plus explicit persistence primitives
  for immutable plan/policy snapshots, decisions, approval attempts, steps, usage
  and delivery identity. It intentionally does not claim work, invoke providers,
  materialize screenplay routes, dispatch approvers, accept canon, or deliver
  artifacts; those behaviors belong to later phases.
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

  # Deliberately no successful no-op implementations of step/update/pause/resume/
  # stop/approve/deliver. Later phases add those commands when their behavior is real.

  defp emit({:ok, _value} = result, operation) do
    :telemetry.execute([:fount_run, operation], %{system_time: System.system_time()}, %{status: :ok})
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
