defmodule FountWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  @impl true
  def init(_arg), do: Supervisor.init([], strategy: :one_for_one)

  def metrics do
    [
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      counter("fount_run.worker.step.count"),
      counter("fount_run.worker.idle.count")
    ]
  end
end
