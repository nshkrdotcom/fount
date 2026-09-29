defmodule FountWeb.WorkerBootstrap do
  @moduledoc "Restarts durable workers after host/process loss from host mappings plus PostgreSQL Run state."
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    Process.send_after(self(), :restore, 750)
    {:ok, state}
  end

  @impl true
  def handle_info(:restore, state) do
    FountWeb.Store.launched_runs(Fount.Repo)
    |> Enum.each(&FountWeb.WorkerSupervisor.start_run/1)

    {:noreply, state}
  end
end
