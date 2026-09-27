defmodule Fount.Observe.Context do
  @moduledoc "Closed, lens-declared context slots containing only neutral typed primitives or explicitly permitted JSON literals."
  alias Fount.Observe.Error
  alias Fount.Observe.Context.{Belief, EntityRef, Fact, Quantity, Relation, TemporalRef, Turn}
  alias Fount.Writing.CanonicalJSON
  defstruct slots: %{}
  @type t :: %__MODULE__{slots: map()}

  def validate(%__MODULE__{slots: slots}, contract) when is_map(slots) and is_map(contract) do
    required = Map.get(contract, "required", %{})
    optional = Map.get(contract, "optional", %{})
    known = Map.merge(required, optional)
    unknown = Map.keys(slots) -- Map.keys(known)
    missing = Map.keys(required) -- Map.keys(slots)
    cond do
      not Enum.all?(Map.keys(slots), &is_binary/1) -> invalid(["slots"])
      missing != [] -> invalid(["slots", hd(Enum.sort(missing))])
      unknown != [] and not Map.get(contract, "allow_unknown", false) -> invalid(["slots", hd(Enum.sort(unknown))])
      true ->
        slots |> Enum.sort() |> Enum.reduce_while(:ok, fn {key, value}, :ok ->
          schema = Map.get(known, key, %{"type" => "literal"})
          if valid_value?(value, schema), do: {:cont, :ok}, else: {:halt, invalid(["slots", key])}
        end)
    end
  rescue
    _ -> invalid(["slots"])
  end
  def validate(_, _), do: invalid(["slots"])

  def to_map(%__MODULE__{slots: slots}), do: %{"slots" => Map.new(slots, fn {k, v} -> {k, plain(v)} end)}
  def hash(context), do: context |> to_map() |> CanonicalJSON.hash()

  defp valid_value?(value, %{"type" => "list", "items" => item}) when is_list(value),
    do: Enum.all?(value, &valid_value?(&1, if(is_binary(item), do: %{"type" => item}, else: item)))
  defp valid_value?(value, %{"type" => "literal"}), do: match?({:ok, _}, CanonicalJSON.encode(value))
  defp valid_value?(%Fact{} = f, %{"type" => "fact"}),
    do: entity?(f.subject) and text?(f.predicate) and literal_or_entity?(f.object) and f.stance in ~w(asserted denied unknown) and strings?(f.evidence_ids)
  defp valid_value?(%Belief{} = b, %{"type" => "belief"}),
    do: entity?(b.owner) and text?(b.proposition) and b.stance in ~w(believes disbelieves uncertain unknown) and optional_probability?(b.probability)
  defp valid_value?(%Relation{} = r, %{"type" => type}) when type in ~w(relation relation_summary),
    do: entity?(r.subject) and text?(r.predicate) and entity?(r.object) and optional_probability?(r.strength)
  defp valid_value?(%Turn{} = t, %{"type" => "turn"}), do: entity?(t.speaker) and text?(t.text) and text?(t.channel)
  defp valid_value?(%EntityRef{} = e, %{"type" => "entity_ref"}), do: text?(e.id) and text?(e.kind)
  defp valid_value?(%Quantity{} = q, %{"type" => type}) when type in ~w(quantity score), do: is_number(q.value) and text?(q.unit)
  defp valid_value?(%TemporalRef{} = t, %{"type" => "temporal_ref"}),
    do: t.relation in ~w(before at after unknown) and match?({:ok, _}, CanonicalJSON.encode(t.point))
  defp valid_value?(_, _), do: false
  defp text?(s), do: is_binary(s) and s != "" and String.valid?(s)
  defp strings?(xs), do: is_list(xs) and Enum.all?(xs, &text?/1)
  defp entity?(%EntityRef{} = e), do: text?(e.id) and text?(e.kind)
  defp entity?(x), do: text?(x)
  defp literal_or_entity?(%EntityRef{} = e), do: entity?(e)
  defp literal_or_entity?(x), do: match?({:ok, _}, CanonicalJSON.encode(x))
  defp optional_probability?(nil), do: true
  defp optional_probability?(p), do: is_number(p) and p >= 0 and p <= 1
  defp plain(%module{} = value) when module in [Fact, Belief, Relation, Turn, EntityRef, Quantity, TemporalRef] do
    value |> Map.from_struct() |> Map.new(fn {k, v} -> {to_string(k), plain(v)} end)
  end
  defp plain(%{__struct__: _}), do: raise(ArgumentError, "unknown context primitive")
  defp plain(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, plain(v)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value), do: value
  defp invalid(path), do: {:error, Error.at(:invalid_context, path)}
end
