defmodule Fount.Fountain.Parser do
  @moduledoc "Context-aware Fountain parser producing a lossless CST and canonical IR."

  alias Fount.{Diagnostic, ID}
  alias Fount.Fountain.{CST, Classifier, Inline}
  alias Fount.Fountain.CST.Node
  alias Fount.IR
  alias Fount.Source
  alias Fount.Source.{Line, Span}

  @spec parse(Source.t(), String.t(), keyword()) :: {CST.t(), Fount.IR.Script.t(), [Diagnostic.t()]}
  def parse(%Source{} = source, document_id, _opts \\ []) do
    {title_page, start_index, title_nodes} = parse_title_page(source, document_id)
    {nodes, diagnostics} = parse_nodes(source, document_id, start_index, Enum.reverse(title_nodes), [])
    cst = %CST{nodes: nodes, title_page: title_page}
    ir = IR.from_cst(document_id, cst)

    diagnostics =
      if source.valid_utf8? do
        diagnostics
      else
        [
          %Diagnostic{
            severity: :warning,
            code: :invalid_utf8,
            message: "Source contains invalid UTF-8 bytes; exact round-trip is preserved but semantic parsing is conservative."
          }
          | diagnostics
        ]
      end

    {cst, ir, Enum.reverse(diagnostics)}
  end

  defp parse_title_page(%Source{lines: []}, _document_id), do: {%Fount.IR.TitlePage{}, 0, []}

  defp parse_title_page(%Source{} = source, document_id) do
    lines = source.lines

    if title_page_start?(lines) do
      {title_lines, rest_index} = take_title_lines(lines, 0, [])
      entries = title_entries(title_lines, source, document_id)
      nodes = title_nodes(entries, title_lines, source, document_id)
      {%Fount.IR.TitlePage{entries: entries}, rest_index, nodes}
    else
      {%Fount.IR.TitlePage{}, 0, []}
    end
  end

  defp title_page_start?([first | _]), do: Classifier.title_key?(first)

  defp take_title_lines(lines, index, acc) do
    case Enum.at(lines, index) do
      nil -> {Enum.reverse(acc), index}
      %Line{content: ""} = line ->
        next = Enum.at(lines, index + 1)

        if next == nil or not title_continuation?(next) do
          {Enum.reverse([line | acc]), index + 1}
        else
          take_title_lines(lines, index + 1, [line | acc])
        end

      line -> take_title_lines(lines, index + 1, [line | acc])
    end
  end

  defp title_continuation?(line) do
    Classifier.title_key?(line) or indented?(line)
  end

  defp title_entries(lines, source, document_id) do
    {entries, current} =
      Enum.reduce(lines, {[], nil}, fn line, {entries, current} ->
        cond do
          line.content == "" ->
            {entries, current}

          Classifier.title_key?(line) ->
            {key, value} = split_title_key(line.content)
            current = finish_title_entry(entries, current)
            entry = %{key: key, values: if(value == "", do: [], else: [value]), lines: [line]}
            {current, entry}

          current != nil and indented?(line) ->
            value = String.trim_leading(line.content)
            {entries, %{current | values: current.values ++ [value], lines: current.lines ++ [line]}}

          true ->
            {entries, current}
        end
      end)

    entries = finish_title_entry(entries, current)

    Enum.map(entries, fn entry ->
      span = span_for_lines(entry.lines)

      %Fount.IR.TitlePage.Entry{
        id: ID.v5(document_id, ["title:", entry.key, ":", Integer.to_string(span.byte_start)]),
        key: entry.key,
        values: entry.values,
        span: span,
        raw: Span.slice(source.raw, span)
      }
    end)
  end

  defp finish_title_entry(entries, nil), do: entries
  defp finish_title_entry(entries, current), do: entries ++ [current]

  defp split_title_key(content) do
    [key, rest] = String.split(content, ":", parts: 2)
    {String.trim(key), String.trim_leading(rest)}
  end

  defp indented?(%Line{content: content}) do
    String.starts_with?(content, "\t") or Regex.match?(~r/^ {3,}/, content)
  end

  defp title_entry_node(entry, source, document_id) do
    %Node{
      id: ID.v5(document_id, ["title-node:", entry.id]),
      type: :title_page,
      span: entry.span,
      content_span: entry.span,
      raw: Span.slice(source.raw, entry.span),
      text: Enum.join(entry.values, "\n"),
      attrs: %{key: entry.key, entry_id: entry.id},
      inline: [],
      line_start: entry.span.line_start,
      line_end: entry.span.line_end
    }
  end

  defp title_nodes(entries, lines, source, document_id) do
    covered_lines =
      Enum.reduce(entries, MapSet.new(), fn entry, set ->
        Enum.reduce(entry.span.line_start..entry.span.line_end, set, &MapSet.put(&2, &1))
      end)

    trivia =
      lines
      |> Enum.reject(&MapSet.member?(covered_lines, &1.number))
      |> Enum.map(&title_trivia_node(&1, source, document_id))

    (Enum.map(entries, &title_entry_node(&1, source, document_id)) ++ trivia)
    |> Enum.sort_by(& &1.span.byte_start)
  end

  defp title_trivia_node(line, source, document_id) do
    raw = Span.slice(source.raw, line.span)

    %Node{
      id: node_id(document_id, :title_trivia, line.span, raw),
      type: :title_trivia,
      span: line.span,
      content_span: line.content_span,
      raw: raw,
      text: Classifier.safe_text(line),
      attrs: %{},
      inline: Inline.scan(line.content),
      line_start: line.number,
      line_end: line.number
    }
  end

  defp parse_nodes(source, document_id, index, acc, diagnostics) do
    lines = source.lines

    case Enum.at(lines, index) do
      nil -> {Enum.reverse(acc), diagnostics}
      line ->
        previous = Enum.at(lines, index - 1)
        following = Enum.at(lines, index + 1)

        cond do
          Classifier.empty?(line) ->
            node = single_node(:blank, line, source, document_id, "", %{})
            parse_nodes(source, document_id, index + 1, [node | acc], diagnostics)

          Classifier.standalone_boneyard_start?(line) ->
            {taken, next_index, closed?} = take_until(lines, index, "*/")
            node = delimited_node(:boneyard, taken, source, document_id, "/*", "*/", closed?)

            diagnostics =
              if closed? do
                diagnostics
              else
                [diag(:warning, :unclosed_boneyard, "Boneyard is not closed before end of file.", node.span) | diagnostics]
              end

            parse_nodes(source, document_id, next_index, [node | acc], diagnostics)

          Classifier.standalone_note_start?(line) ->
            {taken, next_index, closed?} = take_note_until(lines, index)
            node = delimited_node(:note, taken, source, document_id, "[[", "]]", closed?)

            diagnostics =
              if closed? do
                diagnostics
              else
                [diag(:warning, :unclosed_note, "Standalone note is not closed before end of file.", node.span) | diagnostics]
              end

            parse_nodes(source, document_id, next_index, [node | acc], diagnostics)

          Classifier.page_break?(line) ->
            node = single_node(:page_break, line, source, document_id, "", %{})
            parse_nodes(source, document_id, index + 1, [node | acc], diagnostics)

          Classifier.section?(line) ->
            parts = Classifier.section_parts(line)
            content_span = span_from_local(line, parts.content_offset, parts.content_bytes)
            node = single_node(:section, line, source, document_id, parts.text, %{level: parts.level}, content_span)
            parse_nodes(source, document_id, index + 1, [node | acc], diagnostics)

          Classifier.synopsis?(line) ->
            parts = Classifier.synopsis_parts(line)
            content_span = span_from_local(line, parts.content_offset, parts.content_bytes)
            node = single_node(:synopsis, line, source, document_id, parts.text, %{}, content_span)
            parse_nodes(source, document_id, index + 1, [node | acc], diagnostics)

          Classifier.centered?(line) ->
            parts = Classifier.centered_parts(line)
            content_span = span_from_local(line, parts.content_offset, parts.content_bytes)
            node = single_node(:centered, line, source, document_id, parts.text, %{}, content_span)
            parse_nodes(source, document_id, index + 1, [node | acc], diagnostics)

          Classifier.lyric?(line) ->
            {text, content_span} = strip_prefix(line, "~")
            node = single_node(:lyric, line, source, document_id, text, %{}, content_span)
            parse_nodes(source, document_id, index + 1, [node | acc], diagnostics)

          Classifier.scene_heading?(line, previous, following) ->
            parts = Classifier.scene_parts(line)
            content_span = span_from_local(line, parts.content_offset, parts.content_bytes)

            node =
              single_node(
                :scene_heading,
                line,
                source,
                document_id,
                parts.heading,
                %{forced?: parts.forced?, number: parts.number},
                content_span
              )

            parse_nodes(source, document_id, index + 1, [node | acc], diagnostics)

          Classifier.transition?(line, previous, following) ->
            parts = Classifier.transition_parts(line)
            content_span = span_from_local(line, parts.content_offset, parts.content_bytes)

            node =
              single_node(
                :transition,
                line,
                source,
                document_id,
                parts.text,
                %{forced?: parts.forced?},
                content_span
              )

            parse_nodes(source, document_id, index + 1, [node | acc], diagnostics)

          Classifier.character?(line, previous, following) ->
            parts = Classifier.character_parts(line)
            content_span = span_from_local(line, parts.content_offset, parts.content_bytes)

            cue =
              single_node(
                :character,
                line,
                source,
                document_id,
                parts.name,
                %{extension: parts.extension, dual?: parts.dual?, forced?: parts.forced?},
                content_span
              )

            {dialogue_nodes, next_index} = parse_dialogue(lines, source, document_id, index + 1, [])
            next_acc = Enum.reverse(dialogue_nodes, [cue | acc])
            parse_nodes(source, document_id, next_index, next_acc, diagnostics)

          Classifier.forced_action?(line) ->
            {text, content_span} = strip_prefix(line, "!")
            node = single_node(:action, line, source, document_id, text, %{forced?: true}, content_span)
            parse_nodes(source, document_id, index + 1, [node | acc], diagnostics)

          true ->
            {taken, next_index} = take_action_lines(lines, index, [])
            node = multi_node(:action, taken, source, document_id, semantic_text(taken), %{forced?: false})
            parse_nodes(source, document_id, next_index, [node | acc], diagnostics)
        end
    end
  end

  defp parse_dialogue(lines, source, document_id, index, acc) do
    case Enum.at(lines, index) do
      nil -> {Enum.reverse(acc), index}
      %Line{content: ""} -> {Enum.reverse(acc), index}
      line ->
        trimmed = Classifier.trimmed(line)
        parenthetical? = String.starts_with?(trimmed, "(") and String.ends_with?(trimmed, ")")
        type = if parenthetical?, do: :parenthetical, else: :dialogue
        text = if Line.whitespace_only?(line), do: "", else: String.trim(line.content)
        attrs = if Line.whitespace_only?(line), do: %{intentional_blank?: true}, else: %{}

        content_span =
          if parenthetical? and byte_size(trimmed) >= 2 do
            inner = binary_part(trimmed, 1, byte_size(trimmed) - 2)
            offset = match_offset(line.content, inner, match_offset(line.content, "(", 0) + 1)
            span_from_local(line, offset, byte_size(inner))
          else
            line.content_span
          end

        node = single_node(type, line, source, document_id, Inline.plain(text), attrs, content_span)
        parse_dialogue(lines, source, document_id, index + 1, [node | acc])
    end
  end

  defp take_action_lines(lines, index, acc) do
    line = Enum.at(lines, index)

    cond do
      line == nil -> {Enum.reverse(acc), index}
      acc != [] and Classifier.empty?(line) -> {Enum.reverse(acc), index}
      acc != [] and top_level_boundary?(lines, index) -> {Enum.reverse(acc), index}
      true -> take_action_lines(lines, index + 1, [line | acc])
    end
  end

  defp top_level_boundary?(lines, index) do
    line = Enum.at(lines, index)
    previous = Enum.at(lines, index - 1)
    following = Enum.at(lines, index + 1)

    Classifier.page_break?(line) or Classifier.section?(line) or Classifier.synopsis?(line) or
      Classifier.lyric?(line) or Classifier.forced_action?(line) or Classifier.centered?(line) or
      Classifier.standalone_boneyard_start?(line) or Classifier.standalone_note_start?(line) or
      Classifier.scene_heading?(line, previous, following) or
      Classifier.transition?(line, previous, following) or
      Classifier.character?(line, previous, following)
  end

  defp take_note_until(lines, index), do: do_take_note_until(lines, index, [])

  defp do_take_note_until(lines, index, acc) do
    case Enum.at(lines, index) do
      nil -> {Enum.reverse(acc), index, false}
      %Line{content: ""} when acc != [] -> {Enum.reverse(acc), index, false}
      line ->
        next = [line | acc]

        if String.valid?(line.content) and String.contains?(line.content, "]]") do
          {Enum.reverse(next), index + 1, true}
        else
          do_take_note_until(lines, index + 1, next)
        end
    end
  end

  defp take_until(lines, index, terminator) do
    do_take_until(lines, index, terminator, [])
  end

  defp do_take_until(lines, index, terminator, acc) do
    case Enum.at(lines, index) do
      nil -> {Enum.reverse(acc), index, false}
      line ->
        next = [line | acc]

        if String.valid?(line.content) and String.contains?(line.content, terminator) do
          {Enum.reverse(next), index + 1, true}
        else
          do_take_until(lines, index + 1, terminator, next)
        end
    end
  end

  defp single_node(type, line, source, document_id, text, attrs, content_span \\ nil) do
    span = line.span
    raw = Span.slice(source.raw, span)
    content_span = content_span || line.content_span

    %Node{
      id: node_id(document_id, type, span, raw),
      type: type,
      span: span,
      content_span: content_span,
      raw: raw,
      text: text,
      attrs: attrs,
      inline: Inline.scan(line.content),
      line_start: line.number,
      line_end: line.number
    }
  end

  defp multi_node(type, lines, source, document_id, text, attrs) do
    span = span_for_lines(lines)
    raw = Span.slice(source.raw, span)
    first = hd(lines)
    last = List.last(lines)

    content_span =
      Span.new(first.content_span.byte_start, last.content_span.byte_end,
        line_start: first.number,
        column_start: 0,
        line_end: last.number,
        column_end: byte_size(last.content)
      )

    %Node{
      id: node_id(document_id, type, span, raw),
      type: type,
      span: span,
      content_span: content_span,
      raw: raw,
      text: Inline.plain(text),
      attrs: attrs,
      inline: Inline.scan(raw),
      line_start: first.number,
      line_end: last.number
    }
  end

  defp delimited_node(type, [first | _] = lines, source, document_id, opener, closer, closed?) do
    raw = raw_text(lines)
    opener_offset = match_offset(raw, opener, 0)
    content_start = opener_offset + byte_size(opener)

    content_end =
      if closed? do
        raw
        |> :binary.matches(closer)
        |> Enum.map(&elem(&1, 0))
        |> Enum.filter(&(&1 >= content_start))
        |> List.last()
        |> case do
          nil -> byte_size(raw)
          offset -> offset
        end
      else
        byte_size(raw)
      end

    exact_content = binary_part(raw, content_start, max(content_end - content_start, 0))
    semantic_content = normalize_newlines(exact_content)
    node = multi_node(type, lines, source, document_id, semantic_content, %{})

    span =
      Span.new(first.span.byte_start + content_start, first.span.byte_start + content_end,
        line_start: first.number,
        line_end: List.last(lines).number
      )

    %{node | content_span: span}
  end

  defp match_offset(source, pattern, fallback) do
    case :binary.match(source, pattern) do
      {offset, _} -> offset
      :nomatch -> fallback
    end
  end

  defp normalize_newlines(binary) do
    binary
    |> :binary.replace("\r\n", "\n", [:global])
    |> :binary.replace("\r", "\n", [:global])
  end

  defp semantic_text(lines), do: lines |> Enum.map(& &1.content) |> Enum.join("\n")

  defp strip_prefix(line, prefix) do
    source = line.content
    leading = if String.valid?(source), do: byte_size(source) - byte_size(String.trim_leading(source)), else: 0
    body = binary_part(source, leading, byte_size(source) - leading)

    if String.starts_with?(body, prefix) do
      start = leading + byte_size(prefix)
      text = binary_part(source, start, byte_size(source) - start)
      {Inline.plain(text), span_from_local(line, start, byte_size(text))}
    else
      {Inline.plain(source), line.content_span}
    end
  end

  defp span_from_local(line, local_start, length) do
    start = line.content_span.byte_start + local_start
    Span.new(start, start + length, line_start: line.number, line_end: line.number)
  end

  defp span_for_lines([first | _] = lines) do
    last = List.last(lines)

    Span.new(first.span.byte_start, last.span.byte_end,
      line_start: first.number,
      column_start: 0,
      line_end: last.number,
      column_end: byte_size(last.content)
    )
  end

  defp raw_text(lines), do: lines |> Enum.map(&Line.raw/1) |> IO.iodata_to_binary()

  defp node_id(document_id, type, span, raw) do
    ID.v5(document_id, [Atom.to_string(type), ":", Integer.to_string(span.byte_start), ":", ID.short_hash(raw)])
  end

  defp diag(severity, code, message, span),
    do: %Diagnostic{severity: severity, code: code, message: message, span: span}
end
