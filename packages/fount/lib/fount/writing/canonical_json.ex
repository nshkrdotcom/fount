defmodule Fount.Writing.CanonicalJSON do
  @moduledoc """
  A deterministic JSON encoder for content fingerprints.

  Maps use string keys in lexical order. Arrays retain semantic order. Callers
  explicitly exclude revision/source/provenance fields before content hashing;
  this encoder does not guess which domain fields are authored.
  """

  @spec encode(term()) :: {:ok, binary()} | {:error, term()}
  def encode(value) do
    try do
      {:ok, value |> encode_value() |> IO.iodata_to_binary()}
    catch
      {:invalid_canonical_json, reason} -> {:error, reason}
    end
  end

  @spec encode!(term()) :: binary()
  def encode!(value) do
    case encode(value) do
      {:ok, json} -> json
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  @spec hash(term()) :: binary()
  def hash(value) do
    :crypto.hash(:sha256, encode!(value)) |> Base.encode16(case: :lower)
  end

  defp encode_value(nil), do: "null"
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(value) when is_integer(value), do: Integer.to_string(value)

  defp encode_value(value) when is_float(value) do
    # Jason rejects non-finite values. Normalize negative zero without changing
    # meaningful numeric values.
    if value == 0.0, do: "0", else: Jason.encode!(value)
  end

  defp encode_value(value) when is_binary(value) do
    if String.valid?(value) do
      Jason.encode!(value)
    else
      throw({:invalid_canonical_json, :invalid_utf8})
    end
  end

  defp encode_value(value) when is_list(value) do
    ["[", Enum.intersperse(Enum.map(value, &encode_value/1), ","), "]"]
  end

  defp encode_value(%{__struct__: _}) do
    throw({:invalid_canonical_json, :runtime_struct_not_json})
  end

  defp encode_value(value) when is_map(value) do
    unless Enum.all?(Map.keys(value), &is_binary/1) do
      throw({:invalid_canonical_json, :object_keys_must_be_strings})
    end

    pairs =
      value
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.map(fn {key, item} ->
        [encode_value(key), ":", encode_value(item)]
      end)

    ["{", Enum.intersperse(pairs, ","), "}"]
  end

  defp encode_value(_), do: throw({:invalid_canonical_json, :not_json})
end
