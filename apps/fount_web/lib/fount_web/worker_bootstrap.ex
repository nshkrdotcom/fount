defmodule FountWeb.WorkerBootstrap do
  @moduledoc "Restarts durable workers after host/process loss from host mappings plus PostgreSQL Run state."
  use GenServer
  require Logger

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    Process.send_after(self(), :restore, 750)
    {:ok, state}
  end

  @impl true
  def handle_info(:restore, state) do
    case FountWeb.Store.launched_runs(Fount.Repo) do
      runs when is_list(runs) ->
        Enum.each(runs, fn access ->
          case FountWeb.WorkerSupervisor.start_run(access) do
            {:ok, _pid} -> :ok
            {:error, reason} -> Logger.error("Run worker restore refused: #{inspect(reason)}")
          end
        end)

      {:error, reason} ->
        Logger.error("Run worker restore unavailable: #{inspect(reason)}")
        Process.send_after(self(), :restore, 1_000)
    end

    {:noreply, state}
  end
end
