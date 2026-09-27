defmodule Fount.Observe.Question do
  @moduledoc "Provider-neutral atomic questions. Caller labels and ordered rubrics are data, never executable names."
  alias Fount.Observe.Error
  alias Fount.Writing.CanonicalJSON
  @enforce_keys [:kind, :instructions]
  defstruct [:kind, :instructions, criteria: [], levels: [], extra: %{}]

  @type t :: %__MODULE__{
          kind: :noul | :choice | :score,
          instructions: String.t(),
          criteria: list(),
          levels: list(),
          extra: map()
        }

  def noul(instructions, opts \\ []), do: make!(:noul, instructions, [], opts)
  def choice(instructions, criteria, opts \\ []), do: make!(:choice, instructions, criteria, opts)
  def score(instructions, levels, opts \\ []), do: make!(:score, instructions, levels, opts)

  def validate_many(questions) when is_list(questions) and questions != [] do
    Enum.reduce_while(questions, {:ok, [], MapSet.new()}, fn
      {key, %__MODULE__{} = q}, {:ok, acc, seen} when is_atom(key) or is_binary(key) ->
        name = to_string(key)

        with true <- name != "" and not MapSet.member?(seen, name),
             :ok <- validate(q) do
          {:cont, {:ok, acc ++ [{name, q}], MapSet.put(seen, name)}}
        else
          _ -> {:halt, {:error, Error.at(:invalid_request, ["questions", name])}}
        end

      _, _ ->
        {:halt, {:error, Error.at(:invalid_request, ["questions"])}}
    end)
    |> case do
      {:ok, pairs, _} -> {:ok, pairs}
      error -> error
    end
  end

  def validate_many(_), do: {:error, Error.at(:invalid_request, ["questions"])}

  def validate(%__MODULE__{} = q) do
    valid =
      is_binary(q.instructions) and String.trim(q.instructions) != "" and
        String.valid?(q.instructions) and is_map(q.extra) and
        match?({:ok, _}, CanonicalJSON.encode(q.extra)) and
        Enum.all?(Map.keys(q.extra), &(&1 not in ["type", "instructions", "criteria"])) and
        Fount.Observe.Options.safe_extra?(q.extra) and valid_shape?(q)

    if valid, do: :ok, else: {:error, Error.at(:invalid_request, ["question"])}
  end

  def validate(_), do: {:error, Error.at(:invalid_request, ["question"])}

  def specification(%__MODULE__{} = q) do
    %{
      "kind" => to_string(q.kind),
      "instructions" => q.instructions,
      "criteria" =>
        Enum.map(q.criteria, fn {label, meaning} -> %{"label" => label, "meaning" => meaning} end),
      "levels" =>
        Enum.map(q.levels, fn {label, description} ->
          %{"label" => label, "description" => description}
        end),
      "extra" => q.extra
    }
  end

  def specifications(pairs) do
    Enum.map(pairs, fn {key, q} -> Map.put(specification(q), "key", to_string(key)) end)
  end

  def output_contract(%__MODULE__{} = q), do: Fount.Observe.OutputContract.for_question(q)
  def output_digest(%__MODULE__{} = q), do: output_contract(q)["sha256"]

  def domain(%__MODULE__{kind: :noul}), do: ["true", "false"]
  def domain(%__MODULE__{kind: :choice, criteria: criteria}), do: Enum.map(criteria, &elem(&1, 0))

  def domain(%__MODULE__{kind: :score, levels: levels}),
    do: Enum.map(0..(length(levels) - 1), &to_string/1)

  defp make!(kind, instructions, values, opts) do
    unless is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- [:extra] == [],
      do: raise(ArgumentError, "invalid question options")

    q = %__MODULE__{kind: kind, instructions: instructions, extra: Keyword.get(opts, :extra, %{})}

    q =
      case kind do
        :choice -> %{q | criteria: criteria(values)}
        :score -> %{q | levels: levels(values)}
        :noul -> q
      end

    case validate(q) do
      :ok -> q
      {:error, _} -> raise ArgumentError, "invalid measurement question"
    end
  end

  defp criteria(values) when is_map(values),
    do: values |> Enum.sort_by(fn {k, _} -> to_string(k) end) |> criteria()

  defp criteria(values) when is_list(values) do
    Enum.map(values, fn
      {key, text} when (is_atom(key) or is_binary(key)) and is_binary(text) ->
        {to_string(key), text}

      _ ->
        {"", ""}
    end)
  end

  defp criteria(_), do: []

  defp levels(values) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.map(fn
      {{label, text}, _} when (is_atom(label) or is_binary(label)) and is_binary(text) ->
        {to_string(label), text}

      {text, i} when is_binary(text) ->
        {to_string(i), text}

      _ ->
        {"", ""}
    end)
  end

  defp levels(_), do: []
  defp valid_shape?(%{kind: :noul, criteria: [], levels: []}), do: true

  defp valid_shape?(%{kind: :choice, criteria: pairs, levels: []}) when is_list(pairs),
    do: length(pairs) in 2..255 and valid_pairs?(pairs)

  defp valid_shape?(%{kind: :score, levels: pairs, criteria: []}) when is_list(pairs),
    do: length(pairs) in 2..10 and valid_pairs?(pairs)

  defp valid_shape?(_), do: false

  defp valid_pairs?(pairs) do
    Enum.all?(pairs, fn
      {k, v} when is_binary(k) and is_binary(v) ->
        k != "" and String.valid?(k) and String.valid?(v) and String.trim(v) != ""

      _ ->
        false
    end) and
      length(Enum.uniq_by(pairs, &elem(&1, 0))) == length(pairs)
  end
end
