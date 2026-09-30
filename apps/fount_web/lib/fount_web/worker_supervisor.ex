defmodule FountWeb.WorkerSupervisor do
  @moduledoc false

  def start_run(access) when is_map(access) do
    run_id = access["run_id"]

    case Registry.lookup(FountWeb.WorkerRegistry, run_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> start_new(access)
    end
  end

  defp start_new(access) do
    owner = access["owner_id"]
    screenplay_id = access["screenplay_id"]

    with {:ok, context} <- FountWeb.Actors.owner_context(owner, screenplay_id),
         {:ok, run} <- FountRun.get_run(Fount.Repo, access["run_id"], context),
         {:ok, step_opts} <- FountWeb.Services.worker_step_opts(owner, screenplay_id, run) do
      opts = [
        repo: Fount.Repo,
        run_id: access["run_id"],
        context: context,
        name: {:via, Registry, {FountWeb.WorkerRegistry, access["run_id"]}},
        interval_ms: 350,
        step_opts: step_opts
      ]

      case DynamicSupervisor.start_child(FountWeb.WorkerSupervisor, {FountRun.Worker, opts}) do
        {:ok, _pid} = started -> started
        {:error, {:already_started, _pid}} = started -> started
        {:error, _reason} -> {:error, :worker_start_failed}
      end
    end
  end
end
