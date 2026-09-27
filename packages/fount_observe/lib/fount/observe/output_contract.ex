defmodule Fount.Observe.OutputContract do
  @moduledoc """
  Logical output identities and canonical data-shape digests. This deliberately
  small, closed schema vocabulary cannot load code or resolve remote references.
  A stale digest is an error, never a request for an older contract reader.
  """
  alias Fount.Observe.{Error, Question}
  alias Fount.Writing.CanonicalJSON

  def digest(shape), do: CanonicalJSON.hash(shape)

  def literal(id, shape) do
    contract = %{"id" => id, "shape" => shape, "sha256" => digest(shape)}
    case validate(contract) do
      :ok -> contract
      _ -> raise ArgumentError, "invalid output contract"
    end
  end

  def for_question(%Question{} = q) do
    number = %{"type" => "number", "minimum" => 0, "maximum" => 1}
    probabilities = object(Map.new(Question.domain(q), &{&1, number}))
    common = %{"type" => %{"type" => "string", "const" => to_string(q.kind)},
      "probabilities" => probabilities}
    fields =
      case q.kind do
        :noul -> %{"probability" => number}
        :choice -> %{"choice" => %{"type" => "string", "enum" => Question.domain(q)},
          "confidence" => number,
          "option_order" => %{"type" => "array", "items" => %{"type" => "string"},
            "const" => Question.domain(q)}}
        :score -> %{"score" => %{"type" => "number", "minimum" => 0,
            "maximum" => length(q.levels) - 1}, "confidence" => number,
          "rubric" => %{"type" => "array", "items" => %{"type" => "string"},
            "const" => Enum.map(q.levels, &elem(&1, 1))}}
      end
    literal("observe.distribution", object(Map.merge(common, fields)))
  end

  def validate(%{"id" => id, "shape" => shape, "sha256" => sha} = contract) do
    if map_size(contract) == 3 and logical_id?(id) and
         byte_size(CanonicalJSON.encode!(shape)) <= 65_536 and schema?(shape, 0) and
         sha == digest(shape), do: :ok, else: stale()
  rescue
    _ -> stale()
  end
  def validate(_), do: stale()

  def validate_value(contract, value) do
    with :ok <- validate(contract), {:ok, _} <- CanonicalJSON.encode(value),
         true <- matches?(value, contract["shape"]) do
      :ok
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new(:invalid_provider_response)}
    end
  rescue
    _ -> {:error, Error.new(:invalid_provider_response)}
  end

  def logical_id?(id), do: is_binary(id) and byte_size(id) <= 160 and
    Regex.match?(~r/^[a-z][a-z0-9_.-]*$/, id)

  defp object(properties), do: %{"type" => "object", "properties" => properties,
    "required" => properties |> Map.keys() |> Enum.sort(), "additionalProperties" => false}

  defp schema?(shape, depth) when is_map(shape) and depth <= 8 do
    type = shape["type"]
    allowed = ~w(type const enum minimum maximum properties required additionalProperties items)
    Map.keys(shape) -- allowed == [] and type in ~w(string number integer boolean null array object) and
      match?({:ok, _}, CanonicalJSON.encode(shape)) and
      constraints?(shape) and structure?(type, shape, depth)
  end
  defp schema?(_, _), do: false

  defp constraints?(s) do
    (not Map.has_key?(s, "enum") or (is_list(s["enum"]) and s["enum"] != [])) and
      Enum.all?(["minimum", "maximum"], fn key ->
        not Map.has_key?(s, key) or (s["type"] in ~w(number integer) and is_number(s[key]))
      end) and
      (not (Map.has_key?(s, "minimum") and Map.has_key?(s, "maximum")) or
        s["minimum"] <= s["maximum"])
  end

  defp structure?("object", s, depth) do
    is_map(s["properties"]) and is_list(s["required"]) and s["additionalProperties"] == false and
      Map.keys(s) -- ~w(type const enum properties required additionalProperties) == [] and
      length(s["required"]) == length(Enum.uniq(s["required"])) and
      s["required"] -- Map.keys(s["properties"]) == [] and
      Enum.all?(s["properties"], fn {key, value} -> is_binary(key) and schema?(value, depth + 1) end)
  end
  defp structure?("array", s, depth), do:
    Map.keys(s) -- ~w(type const enum items) == [] and schema?(s["items"], depth + 1)
  defp structure?(_, s, _), do: Map.keys(s) -- ~w(type const enum minimum maximum) == []

  defp matches?(value, s) do
    type_matches?(value, s) and
      (not Map.has_key?(s, "const") or value == s["const"]) and
      (not Map.has_key?(s, "enum") or value in s["enum"]) and
      (not Map.has_key?(s, "minimum") or value >= s["minimum"]) and
      (not Map.has_key?(s, "maximum") or value <= s["maximum"])
  end
  defp type_matches?(v, %{"type" => "string"}), do: is_binary(v) and String.valid?(v)
  defp type_matches?(v, %{"type" => "number"}), do: is_number(v)
  defp type_matches?(v, %{"type" => "integer"}), do: is_integer(v)
  defp type_matches?(v, %{"type" => "boolean"}), do: is_boolean(v)
  defp type_matches?(v, %{"type" => "null"}), do: is_nil(v)
  defp type_matches?(v, %{"type" => "array", "items" => item}), do:
    is_list(v) and Enum.all?(v, &matches?(&1, item))
  defp type_matches?(v, %{"type" => "object"} = s) when is_map(v), do:
    Map.keys(v) -- Map.keys(s["properties"]) == [] and s["required"] -- Map.keys(v) == [] and
      Enum.all?(v, fn {key, value} -> matches?(value, s["properties"][key]) end)
  defp type_matches?(_, _), do: false
  defp stale, do: {:error, Error.new(:stale_contract)}
end
