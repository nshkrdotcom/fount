defmodule FountRun.ActorContext do
  @moduledoc """
  Trusted, host-constructed identity and authorization context for Run commands.

  Request JSON is never converted into this struct. A host authenticates the
  acting principal, resolves the project owner and configured automated
  principals, then constructs the context at its trusted boundary.
  """

  alias Fount.Writing.Principal

  @permissions [:read_run, :manage_run]
  @enforce_keys [:principal, :owner, :screenplay_id, :permissions]
  defstruct [:principal, :owner, :screenplay_id, :permissions, approvers: MapSet.new(), route_reviewers: MapSet.new()]

  @type permission :: :read_run | :manage_run
  @type t :: %__MODULE__{
          principal: Principal.t(),
          owner: Principal.t(),
          screenplay_id: String.t(),
          permissions: MapSet.t(permission()),
          approvers: MapSet.t({Principal.type(), String.t()}),
          route_reviewers: MapSet.t(String.t())
        }

  @spec new(Principal.t(), Principal.t(), String.t(), [permission()], keyword()) :: {:ok, t()} | {:error, term()}
  def new(%Principal{} = principal, %Principal{type: :human} = owner, screenplay_id, permissions, opts \\ []) do
    with true <- FountRun.ClosedMap.uuid_string(screenplay_id),
         {:ok, permissions} <- normalize_permissions(permissions),
         {:ok, approvers} <- normalize_principals(Keyword.get(opts, :approvers, [])),
         {:ok, reviewers} <- normalize_reviewers(Keyword.get(opts, :route_reviewers, [])) do
      allowed = MapSet.put(approvers, identity(owner))

      {:ok,
       %__MODULE__{
         principal: principal,
         owner: owner,
         screenplay_id: screenplay_id,
         permissions: permissions,
         approvers: allowed,
         route_reviewers: reviewers
       }}
    else
      false -> {:error, :invalid_screenplay_id}
      {:error, _} = error -> error
    end
  end

  def new(_, _, _, _, _), do: {:error, :invalid_actor_context}

  @spec authorize(t(), permission(), String.t()) :: :ok | {:error, :unauthorized}
  def authorize(%__MODULE__{} = context, permission, screenplay_id) when permission in @permissions do
    allowed =
      screenplay_id == context.screenplay_id and
        (MapSet.member?(context.permissions, permission) or
           (permission == :read_run and MapSet.member?(context.permissions, :manage_run)))

    if allowed, do: :ok, else: {:error, :unauthorized}
  end

  @spec owner?(t(), Principal.t()) :: boolean()
  def owner?(%__MODULE__{owner: owner}, %Principal{} = principal), do: identity(owner) == identity(principal)

  @spec allowed_approver?(t(), Principal.t()) :: boolean()
  def allowed_approver?(%__MODULE__{approvers: approvers}, %Principal{} = principal),
    do: MapSet.member?(approvers, identity(principal))

  @spec allowed_route_reviewer?(t(), String.t()) :: boolean()
  def allowed_route_reviewer?(%__MODULE__{route_reviewers: reviewers}, id),
    do: is_binary(id) and MapSet.member?(reviewers, id)

  @spec identity(Principal.t()) :: {Principal.type(), String.t()}
  def identity(%Principal{type: type, id: id}), do: {type, id}

  defp normalize_permissions(values) when is_list(values) do
    if Enum.all?(values, &(&1 in @permissions)),
      do: {:ok, MapSet.new(values)},
      else: {:error, :invalid_permission}
  end

  defp normalize_permissions(_), do: {:error, :invalid_permission}

  defp normalize_principals(values) when is_list(values) do
    valid? =
      Enum.all?(values, fn
        %Principal{type: type} when type in [:agent, :service] -> true
        _ -> false
      end)

    if valid?,
      do: {:ok, MapSet.new(Enum.map(values, &identity/1))},
      else: {:error, :invalid_approver_registry}
  end

  defp normalize_principals(_), do: {:error, :invalid_approver_registry}

  defp normalize_reviewers(values) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and String.trim(&1) != "")),
      do: {:ok, MapSet.new(values)},
      else: {:error, :invalid_route_reviewer_registry}
  end

  defp normalize_reviewers(_), do: {:error, :invalid_route_reviewer_registry}
end
