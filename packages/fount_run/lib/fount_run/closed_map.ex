defmodule FountRun.ClosedMap do
  @moduledoc false

  @spec normalize(map(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def normalize(value, allowed) when is_map(value) do
    aliases = Map.new(allowed, fn key -> {String.to_atom(key), key} end)
    allowed_set = MapSet.new(allowed)

    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, acc} ->
      normalized =
        cond do
          is_binary(key) and MapSet.member?(allowed_set, key) -> key
          is_atom(key) -> Map.get(aliases, key)
          true -> nil
        end

      if normalized,
        do: {:cont, {:ok, Map.put(acc, normalized, item)}},
        else: {:halt, {:error, {:unknown_field, key}}}
    end)
  end

  def normalize(_, _), do: {:error, :expected_object}

  @spec json?(term()) :: boolean()
  def json?(nil), do: true
  def json?(value) when is_boolean(value) or is_binary(value) or is_integer(value), do: true
  def json?(value) when is_float(value), do: value == value
  def json?(value) when is_list(value), do: Enum.all?(value, &json?/1)

  def json?(value) when is_map(value) do
    Enum.all?(value, fn {key, item} -> is_binary(key) and json?(item) end)
  end

  def json?(_), do: false

  def nonempty_string(value), do: is_binary(value) and String.trim(value) != ""
  def uuid_string(value), do: is_binary(value) and Ecto.UUID.cast(value) != :error
end
