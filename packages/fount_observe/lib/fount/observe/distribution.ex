defmodule Fount.Observe.Distribution do
  @moduledoc "Raw normalized probabilities. A successful uncertain distribution is not an acquisition failure."
  alias Fount.Observe.Error
  @enforce_keys [:kind, :values]
  defstruct [:kind, :values, :selected, :scalar, :confidence, labels: []]
  @type t :: %__MODULE__{}

  def proposition(p) when is_number(p) and p >= 0 and p <= 1,
    do: {:ok, %__MODULE__{kind: :noul, values: [{"true", p}, {"false", 1.0 - p}]}}

  def proposition(_), do: invalid()

  def choice(probabilities, order, selected, confidence) do
    with {:ok, values} <- values(probabilities, order),
         true <-
           (is_binary(selected) or is_atom(selected)) and to_string(selected) in order and
             length(order) in 2..255 and probability?(confidence) do
      {:ok,
       %__MODULE__{
         kind: :choice,
         values: values,
         selected: to_string(selected),
         confidence: confidence
       }}
    else
      _ -> invalid()
    end
  end

  def score(probabilities, labels, scalar, confidence)
      when is_list(labels) and length(labels) in 2..10 do
    order = Enum.map(0..(length(labels) - 1), &to_string/1)

    with {:ok, values} <- values(probabilities, order),
         true <-
           Enum.all?(labels, &(is_binary(&1) and String.valid?(&1) and String.trim(&1) != "")),
         true <- is_number(scalar) and scalar >= 0 and scalar <= length(labels) - 1,
         true <- probability?(confidence) do
      {:ok,
       %__MODULE__{
         kind: :score,
         values: values,
         scalar: scalar,
         confidence: confidence,
         labels: labels
       }}
    else
      _ -> invalid()
    end
  end

  def score(_, _, _, _), do: invalid()

  def validate(%__MODULE__{
        kind: :noul,
        values: [{"true", p}, {"false", complement}],
        confidence: nil,
        selected: nil,
        scalar: nil,
        labels: []
      }) do
    if probability?(p) and probability?(complement) and abs(p + complement - 1) < 1.0e-9,
      do: :ok,
      else: invalid_validation()
  end

  def validate(%__MODULE__{kind: kind} = d) when kind in [:choice, :score] do
    shape_valid =
      case kind do
        :choice -> is_nil(d.scalar) and d.labels == []
        :score -> is_nil(d.selected)
      end

    if shape_valid and pair_values?(d.values) do
      case kind do
        :choice ->
          valid_result(
            choice(Map.new(d.values), Enum.map(d.values, &elem(&1, 0)), d.selected, d.confidence)
          )

        :score ->
          valid_result(score(Map.new(d.values), d.labels, d.scalar, d.confidence))
      end
    else
      invalid_validation()
    end
  end

  def validate(_), do: invalid_validation()

  def to_map(%__MODULE__{kind: :noul, values: values}) do
    %{
      "type" => "noul",
      "probability" => Map.new(values)["true"],
      "probabilities" => Map.new(values)
    }
  end

  def to_map(%__MODULE__{kind: :choice} = d) do
    %{
      "type" => "choice",
      "choice" => d.selected,
      "confidence" => d.confidence,
      "probabilities" => Map.new(d.values),
      "option_order" => Enum.map(d.values, &elem(&1, 0))
    }
  end

  def to_map(%__MODULE__{kind: :score} = d) do
    %{
      "type" => "score",
      "score" => d.scalar,
      "confidence" => d.confidence,
      "probabilities" => Map.new(d.values),
      "rubric" => d.labels
    }
  end

  defp pair_values?(values) when is_list(values) do
    Enum.all?(values, fn
      {key, value} -> is_binary(key) and probability?(value)
      _ -> false
    end) and
      length(Enum.uniq_by(values, &elem(&1, 0))) == length(values)
  end

  defp pair_values?(_), do: false

  defp values(probabilities, order)
       when is_map(probabilities) and is_list(order) and order != [] do
    safe_keys? =
      Enum.all?(Map.keys(probabilities), &(is_binary(&1) or is_atom(&1) or is_integer(&1)))

    normalized =
      if safe_keys?,
        do: Map.new(probabilities, fn {key, value} -> {to_string(key), value} end),
        else: %{}

    if valid_values?(safe_keys?, probabilities, normalized, order),
      do: {:ok, Enum.map(order, &{&1, normalized[&1]})},
      else: invalid()
  end

  defp values(_, _), do: invalid()

  defp valid_values?(safe_keys?, probabilities, normalized, order) do
    safe_keys? and map_size(normalized) == map_size(probabilities) and
      MapSet.new(Map.keys(normalized)) == MapSet.new(order) and
      length(Enum.uniq(order)) == length(order) and
      Enum.all?(Map.values(normalized), &probability?/1) and
      abs(Enum.sum(Map.values(normalized)) - 1.0) <= 0.020000000001
  end

  defp probability?(p), do: is_number(p) and p >= 0 and p <= 1
  defp invalid, do: {:error, Error.new(:invalid_provider_response)}
  defp invalid_validation, do: {:error, Error.new(:invalid_provider_response)}
  defp valid_result({:ok, _}), do: :ok
  defp valid_result(error), do: error
end
