defmodule Fount.Intelligence.Diagnosis.Concern do
  @moduledoc "Pure normalized writer concern. IDs are deterministic and carry no clock/random dependency."

  alias Fount.Writing.CanonicalJSON

  @enforce_keys [:id, :statement]
  defstruct [
    :id,
    :statement,
    desired_effect: nil,
    scope: %{},
    intent: %{},
    protected_strengths: [],
    source: "writer"
  ]

  @type t :: %__MODULE__{}

  @spec new(String.t() | map()) :: {:ok, t()} | {:error, atom()}
  def new(statement) when is_binary(statement), do: new(%{"statement" => statement})

  def new(value) when is_map(value) do
    normalized = stringify(value)
    statement = normalized["statement"] || normalized["concern"]
    desired_effect = normalized["desired_effect"]
    scope = normalized["scope"] || %{}
    intent = normalized["intent"] || %{}
    strengths = normalized["protected_strengths"] || []
    source = normalized["source"] || "writer"

    with true <- text?(statement),
         true <- is_nil(desired_effect) or text?(desired_effect),
         true <- is_map(scope),
         true <- is_map(intent),
         true <- strings?(strengths),
         true <- text?(source),
         {:ok, _} <- CanonicalJSON.encode(%{
           "statement" => statement,
           "desired_effect" => desired_effect,
           "scope" => scope,
           "intent" => intent,
           "protected_strengths" => strengths,
           "source" => source
         }) do
      identity = %{
        "statement" => statement,
        "desired_effect" => desired_effect,
        "scope" => scope,
        "intent" => intent,
        "protected_strengths" => strengths,
        "source" => source
      }

      id =
        case normalized["id"] do
          id when is_binary(id) and id != "" -> id
          _ -> "concern-" <> String.slice(CanonicalJSON.hash(identity), 0, 24)
        end

      {:ok,
       %__MODULE__{
         id: id,
         statement: statement,
         desired_effect: desired_effect,
         scope: scope,
         intent: intent,
         protected_strengths: Enum.uniq(strengths),
         source: source
       }}
    else
      _ -> {:error, :invalid_concern}
    end
  rescue
    _ -> {:error, :invalid_concern}
  end

  def new(_), do: {:error, :invalid_concern}

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = concern) do
    %{
      "id" => concern.id,
      "statement" => concern.statement,
      "desired_effect" => concern.desired_effect,
      "scope" => concern.scope,
      "intent" => concern.intent,
      "protected_strengths" => concern.protected_strengths,
      "source" => concern.source
    }
  end

  defp stringify(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp text?(value), do: is_binary(value) and String.trim(value) != "" and String.valid?(value)
  defp strings?(values), do: is_list(values) and Enum.all?(values, &text?/1)
end
