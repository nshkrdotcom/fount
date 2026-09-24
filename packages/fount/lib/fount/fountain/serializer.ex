defmodule Fount.Fountain.Serializer do
  @moduledoc """
  Canonical Fountain serialization from semantic IR.

  This is deliberately different from `Fount.render/2`: rendering an untouched
  Fountain document returns the exact source bytes, while serialization emits a
  normalized Fountain projection. Where an element still has source-backed lexical
  content, inline Fountain markup is retained from its content span.
  """

  alias Fount.IR.{Element, Script}
  alias Fount.Source.Span

  @spec serialize(Script.t(), keyword()) :: binary()
  def serialize(%Script{} = script, opts \\ []) do
    newline = Keyword.get(opts, :newline, "\n")

    title = serialize_title_page(script.title_page, newline)
    body = serialize_elements(script.elements, newline)

    cond do
      title == "" -> body
      body == "" -> title
      true -> title <> newline <> newline <> body
    end
  end

  defp serialize_title_page(nil, _newline), do: ""
  defp serialize_title_page(%{entries: []}, _newline), do: ""

  defp serialize_title_page(%{entries: entries}, newline) do
    entries
    |> Enum.map(fn entry ->
      case entry.values do
        [] ->
          "#{entry.key}:"

        [single] ->
          "#{entry.key}: #{single}"

        [first | rest] ->
          ["#{entry.key}: #{first}" | Enum.map(rest, &"   #{&1}")]
          |> Enum.join(newline)
      end
    end)
    |> Enum.join(newline)
  end

  defp serialize_elements(elements, newline) do
    elements
    |> Enum.map(&serialize_element(&1, newline))
    |> IO.iodata_to_binary()
  end

  defp serialize_element(%Element{type: :blank}, newline), do: newline

  defp serialize_element(%Element{type: :scene_heading} = e, newline) do
    forced = if Map.get(e.attrs || %{}, :forced?, false), do: ".", else: ""

    number =
      case Map.get(e.attrs || %{}, :number) do
        nil -> ""
        value -> " ##{value}#"
      end

    [forced, lexical_text(e, newline), number, newline]
  end

  defp serialize_element(%Element{type: :character} = e, newline) do
    forced = if Map.get(e.attrs || %{}, :forced?, false), do: "@", else: ""

    extension =
      case Map.get(e.attrs || %{}, :extension) do
        nil -> ""
        value -> " #{value}"
      end

    dual = if Map.get(e.attrs || %{}, :dual?, false), do: " ^", else: ""
    [forced, lexical_text(e, newline), extension, dual, newline]
  end

  defp serialize_element(%Element{type: :parenthetical} = e, newline),
    do: [ensure_parenthetical(lexical_text(e, newline)), newline]

  defp serialize_element(%Element{type: :dialogue} = e, newline) do
    text =
      if Map.get(e.attrs || %{}, :intentional_blank?, false),
        do: "  ",
        else: lexical_text(e, newline)

    [text, newline]
  end

  defp serialize_element(%Element{type: :transition} = e, newline) do
    forced = if Map.get(e.attrs || %{}, :forced?, false), do: ">", else: ""
    [forced, lexical_text(e, newline), newline]
  end

  defp serialize_element(%Element{type: :centered} = e, newline),
    do: [">", lexical_text(e, newline), "<", newline]

  defp serialize_element(%Element{type: :lyric} = e, newline),
    do: ["~", lexical_text(e, newline), newline]

  defp serialize_element(%Element{type: :section} = e, newline),
    do: [String.duplicate("#", Map.get(e.attrs || %{}, :level, 1)), " ", lexical_text(e, newline), newline]

  defp serialize_element(%Element{type: :synopsis} = e, newline),
    do: ["= ", lexical_text(e, newline), newline]

  defp serialize_element(%Element{type: :page_break}, newline), do: ["===", newline]

  defp serialize_element(%Element{type: :note} = e, newline),
    do: ["[[", lexical_text(e, newline), "]]", newline]

  defp serialize_element(%Element{type: :boneyard} = e, newline),
    do: ["/*", lexical_text(e, newline), "*/", newline]

  defp serialize_element(%Element{type: :action} = e, newline) do
    forced = if Map.get(e.attrs || %{}, :forced?, false), do: "!", else: ""
    [forced, lexical_text(e, newline), newline]
  end

  defp serialize_element(%Element{} = e, newline), do: [lexical_text(e, newline), newline]

  defp lexical_text(%Element{raw_text: raw, source_span: %Span{} = source, content_span: %Span{} = content} = element, newline)
       when is_binary(raw) do
    local_start = content.byte_start - source.byte_start
    length = Span.length(content)

    if local_start >= 0 and local_start + length <= byte_size(raw) do
      raw
      |> binary_part(local_start, length)
      |> normalize_newlines(newline)
    else
      normalize_newlines(element.text || "", newline)
    end
  end

  defp lexical_text(%Element{text: text}, newline), do: normalize_newlines(text || "", newline)

  defp normalize_newlines(value, newline) when is_binary(value) do
    value
    |> :binary.replace("\r\n", "\n", [:global])
    |> :binary.replace("\r", "\n", [:global])
    |> :binary.replace("\n", newline, [:global])
  end

  defp ensure_parenthetical(text) do
    if String.starts_with?(text, "(") and String.ends_with?(text, ")"),
      do: text,
      else: "(" <> text <> ")"
  end
end
