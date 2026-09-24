defmodule Fount.ID do
  @moduledoc "UUID generation for durable screenplay identities."

  import Bitwise

  @spec v4() :: String.t()
  def v4 do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = (c &&& 0x0FFF) ||| 0x4000
    d = (d &&& 0x3FFF) ||| 0x8000
    encode(<<a::32, b::16, c::16, d::16, e::48>>)
  end

  @doc "Deterministic RFC 4122 UUIDv5 using a UUID namespace string."
  @spec v5(String.t(), iodata()) :: String.t()
  def v5(namespace, name) when is_binary(namespace) do
    namespace_bytes = namespace_bytes(namespace)
    digest = :crypto.hash(:sha, [namespace_bytes, IO.iodata_to_binary(name)])
    <<uuid::binary-size(16), _::binary>> = digest
    <<a::32, b::16, c::16, d::16, e::48>> = uuid
    c = (c &&& 0x0FFF) ||| 0x5000
    d = (d &&& 0x3FFF) ||| 0x8000
    encode(<<a::32, b::16, c::16, d::16, e::48>>)
  end

  @spec hash(iodata()) :: String.t()
  def hash(data), do: data |> IO.iodata_to_binary() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  @spec short_hash(iodata()) :: String.t()
  def short_hash(data) do
    :crypto.hash(:sha256, data)
    |> binary_part(0, 12)
    |> Base.encode16(case: :lower)
  end

  defp namespace_bytes(namespace) do
    compact = String.replace(namespace, "-", "")

    case Base.decode16(compact, case: :mixed) do
      {:ok, <<uuid::binary-size(16)>>} -> uuid
      _ -> :crypto.hash(:sha256, namespace) |> binary_part(0, 16)
    end
  end

  defp encode(<<a::32, b::16, c::16, d::16, e::48>>) do
    IO.iodata_to_binary([
      hex(a, 8),
      "-",
      hex(b, 4),
      "-",
      hex(c, 4),
      "-",
      hex(d, 4),
      "-",
      hex(e, 12)
    ])
  end

  defp hex(integer, width) do
    integer
    |> Integer.to_string(16)
    |> String.pad_leading(width, "0")
    |> String.downcase()
  end
end
