defmodule FountWeb.RunEvents do
  @moduledoc "PubSub wakeups are an optimization; every LiveView re-reads durable Run state."
  use GenServer

  @events [[:fount_run, :worker, :step], [:fount_run, :worker, :idle]]
  @handler_id {__MODULE__, :worker_events}

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def topic(run_id), do: "fount-run:" <> run_id

  def notify(run_id),
    do: Phoenix.PubSub.broadcast(FountWeb.PubSub, topic(run_id), {:run_changed, run_id})

  @impl true
  def init(state) do
    :telemetry.detach(@handler_id)
    :ok = :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  def handle_event(_event, _measurements, %{run_id: run_id}, _config) when is_binary(run_id),
    do: notify(run_id)

  def handle_event(_, _, _, _), do: :ok
end
