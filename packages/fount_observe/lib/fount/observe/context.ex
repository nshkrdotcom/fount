defmodule Fount.Observe.Context do
  @moduledoc "Closed, lens-declared context slots containing only neutral typed primitives or explicitly permitted JSON literals."
  alias Fount.Observe.Context.{Belief, EntityRef, Fact, Quantity, Relation, TemporalRef, Turn}
  alias Fount.Observe.Error
  alias Fount.Writing.CanonicalJSON
  defstruct slots: %{}
  @type t :: %__MODULE__{slots: map()}

  def validate(%__MODULE__{slots: slots}, contract) when is_map(slots) and is_map(contract) do
    :ok = validate_contract(contract)
    required = Map.get(contract, "required", %{})
    optional = Map.get(contract, "optional", %{})
    known = Map.merge(required, optional)
    unknown = Map.keys(slots) -- Map.keys(known)
    missing = Map.keys(required) -- Map.keys(slots)

    cond do
      not Enum.all?(Map.keys(slots), &is_binary/1) ->
        invalid(["slots"])

      missing != [] ->
        invalid(["slots", hd(Enum.sort(missing))])

      unknown != [] and not Map.get(contract, "allow_unknown", false) ->
        invalid(["slots", hd(Enum.sort(unknown))])

      true ->
        validate_slots(slots, known)
    end
  rescue
    _ -> invalid(["slots"])
  end

  def validate(_, _), do: invalid(["slots"])

  defp validate_slots(slots, known) do
    slots
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn {key, value}, :ok ->
      schema = Map.get(known, key, %{"type" => "literal"})
      if valid_value?(value, schema), do: {:cont, :ok}, else: {:halt, invalid(["slots", key])}
    end)
  end

  def to_map(%__MODULE__{slots: slots}),
    do: %{"slots" => Map.new(slots, fn {k, v} -> {k, plain(v)} end)}

  def hash(context), do: context |> semantic_map() |> CanonicalJSON.hash()



  @doc "Validates a closed schema before any value or provider dispatch. No remote or executable schemas."
  def validate_contract(%{"required" => required, "optional" => optional, "allow_unknown" => false} = contract)
      when is_map(required) and is_map(optional) do
    valid = map_size(contract) == 3 and map_size(required) + map_size(optional) <= 64 and
      MapSet.disjoint?(MapSet.new(Map.keys(required)), MapSet.new(Map.keys(optional))) and
      Enum.all?(Map.merge(required, optional), fn {key, schema} ->
        text?(key) and schema?(schema, 0)
      end)
    if valid, do: :ok, else: invalid(["context_contract"])
  end
  def validate_contract(_), do: invalid(["context_contract"])

  def contract_digest(contract) do
    case validate_contract(contract) do
      :ok -> {:ok, CanonicalJSON.hash(contract)}
      error -> error
    end
  end

  @doc "Storage representation retains evidence pointers; semantic representation deliberately omits them."
  def semantic_map(%__MODULE__{slots: slots}), do:
    %{"slots" => Map.new(slots, fn {k, v} -> {k, semantic(v)} end)}

  def evidence_ids(%__MODULE__{slots: slots}), do:
    slots |> Map.values() |> Enum.flat_map(&pointers/1) |> Enum.uniq() |> Enum.sort()

  @doc "Decodes only installed primitive types; input strings never become atoms or modules."
  def from_map(%{"slots" => slots} = value, contract) when map_size(value) == 1 and is_map(slots) do
    with :ok <- validate_contract(contract) do
      schemas = Map.merge(contract["required"], contract["optional"])
      decoded = Map.new(slots, fn {key, item} -> {key, decode(item, schemas[key])} end)
      context = %__MODULE__{slots: decoded}
      with :ok <- validate(context, contract), do: {:ok, context}
    end
  rescue
    _ -> invalid(["slots"])
  end
  def from_map(_, _), do: invalid(["slots"])

  @doc false
  def prepare_many(contexts, contract) do
    {results, _seen} = Enum.map_reduce(contexts, %{}, fn context, seen ->
      prepare_cached(context, contract, seen)
    end)
    results
  end

  defp prepare_cached(context, contract, seen) do
    key = context |> to_map() |> CanonicalJSON.hash()
    case Map.fetch(seen, key) do
      {:ok, result} -> {result, seen}
      :error ->
        result = with :ok <- validate(context, contract), do: {:ok, semantic_map(context)}
        {result, Map.put(seen, key, result)}
    end
  rescue
    _ -> {invalid(["slots"]), seen}
  end

  defp schema?(%{"type" => "list", "items" => item} = schema, depth) when depth < 8 do
    map_size(schema) == 2 and schema?(if(is_binary(item), do: %{"type" => item}, else: item), depth + 1)
  end
  defp schema?(%{"type" => type} = schema, _), do:
    map_size(schema) == 1 and type in ~w(literal fact belief relation relation_summary turn entity_ref quantity score temporal_ref)
  defp schema?(_, _), do: false

  defp semantic(%Fact{} = value), do: value |> Map.put(:evidence_ids, []) |> plain() |> Map.delete("evidence_ids")
  defp semantic(%module{} = value) when module in [Belief, Relation, Turn, EntityRef, Quantity, TemporalRef], do: plain(value)
  defp semantic(%{__struct__: _}), do: raise(ArgumentError, "unknown context primitive")
  defp semantic(values) when is_list(values), do: Enum.map(values, &semantic/1)
  defp semantic(values) when is_map(values), do: Map.new(values, fn {k, v} -> {k, semantic(v)} end)
  defp semantic(value), do: value

  defp pointers(%Fact{evidence_ids: ids}) when is_list(ids), do: ids
  defp pointers(%{__struct__: _}), do: []
  defp pointers(values) when is_list(values), do: Enum.flat_map(values, &pointers/1)
  defp pointers(values) when is_map(values), do: values |> Map.values() |> Enum.flat_map(&pointers/1)
  defp pointers(_), do: []

  defp decode(values, %{"type" => "list", "items" => item}) when is_list(values), do:
    Enum.map(values, &decode(&1, if(is_binary(item), do: %{"type" => item}, else: item)))
  defp decode(value, %{"type" => "literal"}), do: value
  defp decode(value, %{"type" => type}) when is_map(value) do
    module = case type do
      "fact" -> Fact
      "belief" -> Belief
      "relation" -> Relation
      "relation_summary" -> Relation
      "turn" -> Turn
      "entity_ref" -> EntityRef
      "quantity" -> Quantity
      "score" -> Quantity
      "temporal_ref" -> TemporalRef
      _ -> raise ArgumentError, "unknown context primitive"
    end
    fields = module |> struct() |> Map.from_struct() |> Map.keys()
    if Map.keys(value) -- Enum.map(fields, &to_string/1) != [], do: raise(ArgumentError, "unknown context field")
    attrs = for key <- fields, Map.has_key?(value, to_string(key)), into: %{} do
      item = value[to_string(key)]
      {key, if(key in [:subject, :object, :owner, :speaker], do: decode_entity(item), else: item)}
    end
    struct(module, attrs)
  end
  defp decode(_, _), do: raise(ArgumentError, "invalid context value")
  defp decode_entity(%{"id" => id, "kind" => kind} = v) when map_size(v) == 2, do: %EntityRef{id: id, kind: kind}
  defp decode_entity(v), do: v

  defp valid_value?(value, %{"type" => "list", "items" => item}) when is_list(value),
    do:
      Enum.all?(value, &valid_value?(&1, if(is_binary(item), do: %{"type" => item}, else: item)))

  defp valid_value?(value, %{"type" => "literal"}),
    do: match?({:ok, _}, CanonicalJSON.encode(value))

  defp valid_value?(%Fact{} = f, %{"type" => "fact"}),
    do:
      entity?(f.subject) and text?(f.predicate) and literal_or_entity?(f.object) and
        f.stance in ~w(asserted denied unknown) and strings?(f.evidence_ids)

  defp valid_value?(%Belief{} = b, %{"type" => "belief"}),
    do:
      entity?(b.owner) and text?(b.proposition) and
        b.stance in ~w(believes disbelieves uncertain unknown) and
        optional_probability?(b.probability)

  defp valid_value?(%Relation{} = r, %{"type" => type})
       when type in ~w(relation relation_summary),
       do:
         entity?(r.subject) and text?(r.predicate) and entity?(r.object) and
           optional_probability?(r.strength)

  defp valid_value?(%Turn{} = t, %{"type" => "turn"}),
    do: entity?(t.speaker) and text?(t.text) and text?(t.channel)

  defp valid_value?(%EntityRef{} = e, %{"type" => "entity_ref"}),
    do: text?(e.id) and text?(e.kind)

  defp valid_value?(%Quantity{} = q, %{"type" => type}) when type in ~w(quantity score),
    do: is_number(q.value) and text?(q.unit)

  defp valid_value?(%TemporalRef{} = t, %{"type" => "temporal_ref"}),
    do:
      t.relation in ~w(before at after unknown) and
        match?({:ok, _}, CanonicalJSON.encode(t.point))

  defp valid_value?(_, _), do: false
  defp text?(s), do: is_binary(s) and s != "" and String.valid?(s)
  defp strings?(xs), do: is_list(xs) and Enum.all?(xs, &text?/1)
  defp entity?(%EntityRef{} = e), do: text?(e.id) and text?(e.kind)
  defp entity?(x), do: text?(x)
  defp literal_or_entity?(%EntityRef{} = e), do: entity?(e)
  defp literal_or_entity?(x), do: match?({:ok, _}, CanonicalJSON.encode(x))
  defp optional_probability?(nil), do: true
  defp optional_probability?(p), do: is_number(p) and p >= 0 and p <= 1

  defp plain(%module{} = value)
       when module in [Fact, Belief, Relation, Turn, EntityRef, Quantity, TemporalRef] do
    value |> Map.from_struct() |> Map.new(fn {k, v} -> {to_string(k), plain(v)} end)
  end

  defp plain(%{__struct__: _}), do: raise(ArgumentError, "unknown context primitive")
  defp plain(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, plain(v)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value), do: value
  defp invalid(path), do: {:error, Error.at(:invalid_context, path)}
end
