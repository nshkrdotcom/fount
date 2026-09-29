defmodule FountWeb.Actors do
  @moduledoc "Trusted host construction of owner and configured automated ActorContexts."
  alias Fount.Writing.Principal
  alias FountRun.ActorContext

  def owner_context(owner_id, screenplay_id) do
    with {:ok, owner} <- Principal.new(:human, owner_id),
         {:ok, agent} <- Principal.new(:agent, demo_id(:agent)),
         {:ok, service} <- Principal.new(:service, demo_id(:service)) do
      ActorContext.new(owner, owner, screenplay_id, [:read_run, :manage_run], approvers: [agent, service])
    end
  end

  def automated_context(kind, owner_id, screenplay_id) when kind in [:agent, :service] do
    with {:ok, owner} <- Principal.new(:human, owner_id),
         {:ok, principal} <- Principal.new(kind, demo_id(kind)) do
      ActorContext.new(principal, owner, screenplay_id, [:read_run, :manage_run], approvers: [principal])
    end
  end

  def principal(kind) when kind in [:agent, :service] do
    {:ok, principal} = Principal.new(kind, demo_id(kind))
    principal
  end

  defp demo_id(:agent), do: Application.fetch_env!(:fount_web, :demo)[:agent_approver_id]
  defp demo_id(:service), do: Application.fetch_env!(:fount_web, :demo)[:service_approver_id]
end
