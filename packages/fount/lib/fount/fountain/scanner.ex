defmodule Fount.Fountain.Scanner do
  @moduledoc "Byte-preserving Fountain line scanner."
  alias Fount.Source
  alias Fount.Source.Line
  alias Fount.Source.Span

  @spec scan(binary(), keyword()) :: Source.t()
  def scan(raw, opts \\ []) when is_binary(raw) do
    lines = scan_lines(raw, raw, 0, 1, [])

    %Source{
      format: :fountain,
      raw: raw,
      lines: lines,
      path: Keyword.get(opts, :path),
      valid_utf8?: String.valid?(raw),
      newline_style: newline_style(lines)
    }
  end

  defp scan_lines(_original, <<>>, _offset, _number, acc), do: Enum.reverse(acc)

  defp scan_lines(original, remaining, offset, number, acc) do
    {content_length, eol, rest} = take_line(remaining, 0)
    content = binary_part(remaining, 0, content_length)
    raw_length = content_length + byte_size(eol)

    line = %Line{
      number: number,
      content: content,
      eol: eol,
      span:
        Span.new(offset, offset + raw_length,
          line_start: number,
          column_start: 0,
          line_end: number,
          column_end: content_length
        ),
      content_span:
        Span.new(offset, offset + content_length,
          line_start: number,
          column_start: 0,
          line_end: number,
          column_end: content_length
        )
    }

    # Keep the original argument in the recursion signature so accidental slicing of
    # transformed text can never creep into this scanner.
    _ = original
    scan_lines(original, rest, offset + raw_length, number + 1, [line | acc])
  end

  defp take_line(<<>>, length), do: {length, "", <<>>}

  defp take_line(<<"\r\n", rest::binary>>, length),
    do: {length, "\r\n", rest}

  defp take_line(<<"\n", rest::binary>>, length),
    do: {length, "\n", rest}

  defp take_line(<<"\r", rest::binary>>, length),
    do: {length, "\r", rest}

  defp take_line(<<_byte, rest::binary>>, length), do: take_line(rest, length + 1)

  defp newline_style(lines) do
    styles =
      lines
      |> Enum.map(& &1.eol)
      |> Enum.reject(&(&1 == ""))
      |> MapSet.new()

    case MapSet.to_list(styles) do
      [] -> :none
      ["\n"] -> :lf
      ["\r\n"] -> :crlf
      ["\r"] -> :cr
      _ -> :mixed
    end
  end
end
