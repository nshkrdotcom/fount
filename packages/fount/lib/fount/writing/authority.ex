defmodule Fount.Writing.Authority do
  @moduledoc """
  Trusted host authorization context for canonical screenplay decisions.

  This structure is runtime authority, not an input payload. Request JSON must
  never be deserialized into an authority value. Hosts construct it only after
  authenticating the principal and checking project/screenplay ownership.
  """

  alias Fount.Writing.Principal

  @enforce_keys [:principal, :screenplay_id, :permissions]
  defstruct [:principal, :screenplay_id, :permissions]

  @type t :: %__MODULE__{
          principal: Principal.t(),
          screenplay_id: String.t(),
          permissions: MapSet.t(atom())
        }

  @spec new(Principal.t(), String.t(), [atom()]) :: {:ok, t()} | {:error, term()}
  def new(%Principal{} = principal, screenplay_id, permissions \\ [:approve])
      when is_binary(screenplay_id) and is_list(permissions) do
    cond do
      String.trim(screenplay_id) == "" -> {:error, :invalid_authority_screenplay}
      Enum.any?(permissions, &(not is_atom(&1))) -> {:error, :invalid_authority_permissions}
      true -> {:ok, %__MODULE__{principal: principal, screenplay_id: screenplay_id, permissions: MapSet.new(permissions)}}
    end
  end

  def new(_, _, _), do: {:error, :invalid_authority}

  @spec authorize(t(), atom(), String.t(), Principal.t()) :: :ok | {:error, term()}
  def authorize(%__MODULE__{} = authority, permission, screenplay_id, %Principal{} = principal) do
    cond do
      authority.screenplay_id != screenplay_id -> {:error, :authority_screenplay_mismatch}
      authority.principal != principal -> {:error, :authority_principal_mismatch}
      not MapSet.member?(authority.permissions, permission) -> {:error, :approval_not_authorized}
      true -> :ok
    end
  end

  def authorize(_, _, _, _), do: {:error, :invalid_authority}
end
