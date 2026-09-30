defmodule FountWeb.Actors do
  @moduledoc "Trusted host construction of owner and configured automated ActorContexts."
  alias Fount.Writing.Principal
  alias FountRun.ActorContext

  def owner_context(owner_id, screenplay_id) do
    with {:ok, owner} <- Principal.new(:human, owner_id),
         {:ok, agent} <- Principal.new(:agent, demo_id(:agent)),
         {:ok, service} <- Principal.new(:service, demo_id(:service)) do
      ActorContext.new(owner, owner, screenplay_id, [:read_run, :manage_run],
        approvers: [agent, service],
        route_reviewers: [owner_id]
      )
    end
  end

  def automated_context(kind, owner_id, screenplay_id) when kind in [:agent, :service] do
    with {:ok, owner} <- Principal.new(:human, owner_id),
         {:ok, principal} <- Principal.new(kind, demo_id(kind)) do
      ActorContext.new(principal, owner, screenplay_id, [:read_run, :manage_run],
        approvers: [principal]
      )
    end
  end

  def principal(kind) when kind in [:agent, :service] do
    {:ok, principal} = Principal.new(kind, demo_id(kind))
    principal
  end

  @doc "Returns the closed set of trusted principals that policy forms may reference."
  def policy_principals(owner_id) when is_binary(owner_id) do
    {:ok, owner} = Principal.new(:human, owner_id)

    [
      %{"key" => "owner", "label" => "Authenticated owner", "principal" => owner},
      %{
        "key" => "agent",
        "label" => "Configured agent approver",
        "principal" => principal(:agent)
      },
      %{
        "key" => "service",
        "label" => "Configured service approver",
        "principal" => principal(:service)
      }
    ]
  end

  @doc "Resolves a policy form key without accepting a browser-supplied principal type or id."
  def resolve_policy_principal(owner_id, key) when is_binary(owner_id) and is_binary(key) do
    case Enum.find(policy_principals(owner_id), &(&1["key"] == key)) do
      nil -> {:error, :unauthorized_principal_selection}
      %{"principal" => principal} -> {:ok, Principal.to_map(principal)}
    end
  end

  def resolve_policy_principal(_owner_id, _key), do: {:error, :unauthorized_principal_selection}

  @doc "Returns the closed set of trusted human route reviewers available to policy forms."
  def policy_reviewers(owner_id) when is_binary(owner_id) do
    [%{"key" => "owner", "label" => "Authenticated owner", "reviewer_id" => owner_id}]
  end

  @doc "Resolves a route-reviewer form key without accepting a browser-supplied reviewer id."
  def resolve_route_reviewer(owner_id, key) when is_binary(owner_id) and is_binary(key) do
    case Enum.find(policy_reviewers(owner_id), &(&1["key"] == key)) do
      nil -> {:error, :unauthorized_route_reviewer_selection}
      %{"reviewer_id" => reviewer_id} -> {:ok, reviewer_id}
    end
  end

  def resolve_route_reviewer(_owner_id, _key),
    do: {:error, :unauthorized_route_reviewer_selection}

  defp demo_id(:agent), do: Application.fetch_env!(:fount_web, :demo)[:agent_approver_id]
  defp demo_id(:service), do: Application.fetch_env!(:fount_web, :demo)[:service_approver_id]
end
