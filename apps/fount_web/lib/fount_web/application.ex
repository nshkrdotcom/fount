defmodule FountWeb.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Fount.Repo,
      {Phoenix.PubSub, name: FountWeb.PubSub},
      {Registry, keys: :unique, name: FountWeb.WorkerRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: FountWeb.WorkerSupervisor},
      FountWeb.RunEvents,
      FountWeb.WorkerBootstrap,
      FountWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: FountWeb.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FountWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
