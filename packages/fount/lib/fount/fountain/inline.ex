defmodule Fount.Fountain.Inline do
  @moduledoc "Conservative inline Fountain markup discovery without rewriting source."

  defmodule Mark do
    @moduledoc "A source span and exact spelling for an inline Fountain mark."
    @enforce_keys [:kind, :byte_start, :byte_end, :raw]
    defstruct [:kind, :byte_start, :byte_end, :raw, :content]
    @type t :: %__MODULE__{}
  end

  @patterns [
    {:bold_italic, ~r/(?<!\\)\*\*\*(\S(?:[^\n]*?\S)?)\*\*\*/u},
    {:bold, ~r/(?<!\\)\*\*(\S(?:[^\n]*?\S)?)\*\*/u},
    {:italic, ~r/(?<!\\)\*(\S(?:[^\n]*?\S)?)\*/u},
    {:underline, ~r/(?<!\\)_(\S(?:[^\n]*?\S)?)_/u},
    {:strikeout, ~r/(?<!\\)~~(\S(?:[^\n]*?\S)?)~~/u}
  ]

  @spec scan(binary()) :: [Mark.t()]
  def scan(text) when is_binary(text) do
    if String.valid?(text) do
      (scan_notes(text) ++ scan_emphasis(text))
      |> Enum.sort_by(&{&1.byte_start, &1.byte_end})
    else
      []
    end
  end

  @spec plain(binary()) :: binary()
  def plain(text) when is_binary(text) do
    if String.valid?(text) do
      text
      |> then(&Regex.replace(~r/\[\[(?:.|\n)*?\]\]/u, &1, ""))
      |> then(&Regex.replace(~r/(?<!\\)\*\*\*(\S(?:[^\n]*?\S)?)\*\*\*/u, &1, "\\1"))
      |> then(&Regex.replace(~r/(?<!\\)\*\*(\S(?:[^\n]*?\S)?)\*\*/u, &1, "\\1"))
      |> then(&Regex.replace(~r/(?<!\\)\*(\S(?:[^\n]*?\S)?)\*/u, &1, "\\1"))
      |> then(&Regex.replace(~r/(?<!\\)_(\S(?:[^\n]*?\S)?)_/u, &1, "\\1"))
      |> then(&Regex.replace(~r/(?<!\\)~~(\S(?:[^\n]*?\S)?)~~/u, &1, "\\1"))
      |> String.replace(~r/\\([*_~\\])/, "\\1")
    else
      text
    end
  end

  defp scan_notes(text), do: scan_delimited(text, "[[", "]]", :note, 0, [])

  defp scan_delimited(text, open, close, kind, offset, acc) do
    case :binary.match(text, open) do
      :nomatch ->
        Enum.reverse(acc)

      {start, _} ->
        after_open = start + byte_size(open)
        remainder = binary_part(text, after_open, byte_size(text) - after_open)

        case :binary.match(remainder, close) do
          :nomatch ->
            Enum.reverse(acc)

          {finish, _} ->
            size = byte_size(open) + finish + byte_size(close)
            raw = binary_part(text, start, size)
            content = binary_part(text, after_open, finish)

            mark = %Mark{
              kind: kind,
              byte_start: offset + start,
              byte_end: offset + start + size,
              raw: raw,
              content: content
            }

            consumed = start + size
            tail = binary_part(text, consumed, byte_size(text) - consumed)
            scan_delimited(tail, open, close, kind, offset + consumed, [mark | acc])
        end
    end
  end

  defp scan_emphasis(text) do
    Enum.flat_map(@patterns, fn {kind, regex} -> regex_marks(text, kind, regex) end)
  end

  defp regex_marks(text, kind, regex) do
    Regex.scan(regex, text, return: :index)
    |> Enum.map(fn
      [{start, length}, {content_start, content_length}] ->
        %Mark{
          kind: kind,
          byte_start: start,
          byte_end: start + length,
          raw: binary_part(text, start, length),
          content: binary_part(text, content_start, content_length)
        }

      [{start, length} | _] ->
        %Mark{
          kind: kind,
          byte_start: start,
          byte_end: start + length,
          raw: binary_part(text, start, length),
          content: nil
        }
    end)
  end
end
