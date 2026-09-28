defmodule Fount.Writing.Principal do
  @moduledoc """
  Authenticated approval principal supplied by a trusted host boundary.

  Principal values are deliberately not inferred from screenplay/request JSON.
  The host authenticates a user, agent, or service and constructs this value.
  """

  @types [:human, :agent, :service]
  @enforce_keys [:type, :id]
  defstruct [:type, :id]

  @type type :: :human | :agent | :service
  @type t :: %__MODULE__{type: type(), id: String.t()}

  @spec new(type() | String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def new(type, id) do
    with {:ok, type} <- normalize_type(type),
         true <- is_binary(id) and String.trim(id) != "" do
      {:ok, %__MODULE__{type: type, id: id}}
    else
      false -> {:error, :invalid_principal_id}
      {:error, _} = error -> error
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = principal), do: %{"type" => Atom.to_string(principal.type), "id" => principal.id}

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"type" => type, "id" => id} = map) when map_size(map) == 2, do: new(type, id)
  def from_map(_), do: {:error, :invalid_principal}

  defp normalize_type(type) when type in @types, do: {:ok, type}
  defp normalize_type(type) when is_binary(type) do
    case Enum.find(@types, &(Atom.to_string(&1) == type)) do
      nil -> {:error, :invalid_principal_type}
      value -> {:ok, value}
    end
  end

  defp normalize_type(_), do: {:error, :invalid_principal_type}
end
