defmodule Fount.Writing.LocalReferences do
  @moduledoc """
  Candidate-local reference allocation with explicit declaration accounting.

  A `local_id` declares an object. Other `new:...` strings reference declarations.
  Exact string values in prose fields are never interpreted as references.
  UUID generation is injectable for offline tests; the production default uses
  cryptographically random RFC 4122 version-4 UUIDs.
  """

  @reference_keys ~w(id anchor_id after_scene_id before_scene_id scene_id
    heading_id character_id dialogue_block_id element_id target_id
    source_id destination_id partner_id replaces)
  @reference_list_keys ~w(ids scene_ids element_ids mention_ids)

  @spec compile(map() | list(), keyword()) ::
          {:ok, term(), map()} | {:error, term()}
  def compile(value, opts \\ []) do
    generator = Keyword.get(opts, :uuid, &uuid/0)

    with {:ok, labels} <- declarations(value, []),
         :ok <- unique(labels),
         {:ok, mapping} <- allocate(labels, generator),
         {:ok, compiled} <- rewrite(value, mapping, nil) do
      {:ok, compiled, mapping}
    end
  end

  def uuid do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    [hex(a, 8), hex(b, 4), hex(c, 4), hex(d, 4), hex(e, 12)]
    |> Enum.join("-")
  end

  defp hex(number, width) do
    number |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")
  end

  defp declarations(map, acc) when is_map(map) do
    with {:ok, next} <- declaration(map, acc) do
      Enum.reduce_while(map, {:ok, next}, fn {_key, value}, {:ok, found} ->
        case declarations(value, found) do
          {:ok, values} -> {:cont, {:ok, values}}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp declarations(list, acc) when is_list(list) do
    Enum.reduce_while(list, {:ok, acc}, fn value, {:ok, found} ->
      case declarations(value, found) do
        {:ok, values} -> {:cont, {:ok, values}}
        error -> {:halt, error}
      end
    end)
  end

  defp declarations(_, acc), do: {:ok, acc}

  defp declaration(%{"local_id" => "new:" <> label = local} = object, acc) do
    cond do
      Map.has_key?(object, "id") -> {:error, {:conflicting_identity, local}}
      label == "" or not Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/, label) ->
        {:error, {:invalid_local_id, local}}
      true -> {:ok, acc ++ [local]}
    end
  end

  defp declaration(%{"local_id" => value}, _acc),
    do: {:error, {:invalid_local_id, value}}
  defp declaration(_, acc), do: {:ok, acc}

  defp unique(labels) do
    duplicates =
      labels |> Enum.frequencies() |> Enum.filter(fn {_, n} -> n > 1 end)
      |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    if duplicates == [], do: :ok, else: {:error, {:duplicate_local_ids, duplicates}}
  end

  defp allocate(labels, generator) do
    mapping = Map.new(labels, &{&1, generator.()})
    values = Map.values(mapping)

    cond do
      not Enum.all?(values, &valid_uuid?/1) -> {:error, :invalid_allocated_uuid}
      length(Enum.uniq(values)) != length(values) -> {:error, :duplicate_allocated_uuid}
      true -> {:ok, mapping}
    end
  end

  defp valid_uuid?(value) when is_binary(value),
    do: Regex.match?(~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/, value)
  defp valid_uuid?(_), do: false

  defp rewrite(map, mapping, _key) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {key, value}, {:ok, output} ->
      result =
        if key == "local_id" do
          {:ok, Map.fetch!(mapping, value)}
        else
          rewrite(value, mapping, key)
        end

      case result do
        {:ok, rewritten} ->
          output_key = if key == "local_id", do: "id", else: key
          {:cont, {:ok, Map.put(output, output_key, rewritten)}}
        error -> {:halt, error}
      end
    end)
  end

  defp rewrite(list, mapping, key) when is_list(list) do
    item_key = if key in @reference_list_keys, do: "id", else: nil

    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, items} ->
      case rewrite(item, mapping, item_key) do
        {:ok, rewritten} -> {:cont, {:ok, [rewritten | items]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp rewrite("new:" <> _ = value, mapping, key) when key in @reference_keys do
    case Map.fetch(mapping, value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:undeclared_local_reference, value}}
    end
  end

  defp rewrite(value, _mapping, _key), do: {:ok, value}
end
