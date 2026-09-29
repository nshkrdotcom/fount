defmodule FountRun.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      Application.get_env(:fount_run, :workers, [])
      |> Enum.with_index()
      |> Enum.map(fn {opts, index} ->
        Supervisor.child_spec({FountRun.Worker, opts}, id: {:fount_run_worker, index})
      end)

    Supervisor.start_link(children, strategy: :one_for_one, name: FountRun.Supervisor)
  end
end
