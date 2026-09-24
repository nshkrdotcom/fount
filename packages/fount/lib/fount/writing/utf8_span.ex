defmodule Fount.Writing.UTF8Span do
  @moduledoc """
  Validates half-open byte spans in current UTF-8 element text.

  Source-artifact offsets are deliberately not accepted here. A relocated pin
  must be found exactly once in the retained element, not at its old offset.
  """

  @type span :: {non_neg_integer(), pos_integer()}

  @spec extract(String.t(), span() | [integer()]) ::
          {:ok, String.t()} | {:error, atom()}
  def extract(text, [first, last]), do: extract(text, {first, last})

  def extract(text, {first, last})
      when is_binary(text) and is_integer(first) and is_integer(last) do
    cond do
      not String.valid?(text) -> {:error, :invalid_utf8}
      first < 0 or last <= first or last > byte_size(text) ->
        {:error, :invalid_span}
      not boundary?(text, first) or not boundary?(text, last) ->
        {:error, :split_utf8_codepoint}
      true ->
        {:ok, binary_part(text, first, last - first)}
    end
  end

  def extract(_, _), do: {:error, :invalid_span}

  @spec verify(String.t(), span() | [integer()], String.t()) ::
          :ok | {:error, atom()}
  def verify(text, span, excerpt) when is_binary(excerpt) do
    case extract(text, span) do
      {:ok, ^excerpt} -> :ok
      {:ok, _} -> {:error, :excerpt_mismatch}
      {:error, _} = error -> error
    end
  end

  def verify(_, _, _), do: {:error, :invalid_excerpt}

  @spec relocate(String.t(), String.t()) ::
          {:ok, span()} | {:error, atom()}
  def relocate(text, pin)
      when is_binary(text) and is_binary(pin) and byte_size(pin) > 0 do
    cond do
      not String.valid?(text) or not String.valid?(pin) ->
        {:error, :invalid_utf8}
      true ->
        case occurrences(text, pin, 0, []) do
          [{first, size}] -> {:ok, {first, first + size}}
          [] -> {:error, :protected_text_changed}
          _ -> {:error, :ambiguous_protected_text}
        end
    end
  end

  def relocate(_, _), do: {:error, :invalid_pin}

  defp occurrences(text, pin, offset, found) when offset <= byte_size(text) do
    remaining = byte_size(text) - offset

    if remaining < byte_size(pin) do
      Enum.reverse(found)
    else
      case :binary.match(text, pin, scope: {offset, remaining}) do
        :nomatch ->
          Enum.reverse(found)
        {first, size} ->
          # Advance one byte so overlapping occurrences also make a pin
          # ambiguous. Never silently choose one instance.
          occurrences(text, pin, first + 1, [{first, size} | found])
      end
    end
  end

  defp boundary?(_text, 0), do: true
  defp boundary?(text, offset) when offset == byte_size(text), do: true
  defp boundary?(text, offset) do
    byte = :binary.at(text, offset)
    byte < 128 or byte >= 192
  end
end
