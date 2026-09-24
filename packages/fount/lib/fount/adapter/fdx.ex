defmodule Fount.Adapter.FDX do
  @moduledoc "Practical Final Draft XML adapter for import/export at Fount's model boundary."

  import Saxy.XML

  alias Fount.Adapter.{ExportResult, ImportResult}

  @supported_styles MapSet.new(["Bold", "Italic", "Underline"])

  @spec decode(binary(), keyword()) :: {:ok, ImportResult.t()} | {:error, term()}
  def decode(xml, opts \\ []) when is_binary(xml) do
    # :keep expands XML predefined entities such as &amp; while never dereferencing
    # external entities. That is the correct behavior for screenplay text.
    with {:ok, simple} <- Saxy.SimpleForm.parse_string(xml, expand_entity: :keep),
         {:ok, paragraphs, metadata} <- extract(simple) do
      fountain = paragraphs_to_fountain(paragraphs)

      parse_opts =
        opts
        |> Keyword.take([:document_id, :actor, :message])
        |> Keyword.put(:message, Keyword.get(opts, :message, "import FDX"))

      with {:ok, document} <- Fount.parse(fountain, parse_opts) do
        losses = import_losses(simple, paragraphs)
        {:ok, %ImportResult{document: document, losses: losses, metadata: metadata}}
      end
    end
  end

  @spec export(Fount.Document.t(), keyword()) :: {:ok, ExportResult.t()}
  def export(doc, _opts \\ []) do
    {content_children, losses} = export_elements(doc)
    title_children = export_title_page(doc.ir.title_page)

    children =
      case title_children do
        [] -> [element("Content", [], content_children)]
        items -> [element("TitlePage", [], items), element("Content", [], content_children)]
      end

    root =
      element(
        "FinalDraft",
        [{"DocumentType", "Script"}, {"Template", "No"}, {"Version", "2"}],
        children
      )

    xml = Saxy.encode!(root, version: "1.0", encoding: "UTF-8")
    {:ok, %ExportResult{data: xml, losses: Enum.uniq(Enum.reverse(losses)), metadata: %{document_id: doc.id}}}
  end

  defp extract({"FinalDraft", attrs, children}) do
    content = Enum.find(children, &match?({"Content", _, _}, &1))

    case content do
      {"Content", _, content_children} ->
        paragraphs = collect_paragraphs(content_children, nil, [], 0)
        {:ok, paragraphs, %{root_attributes: Map.new(attrs)}}

      _ ->
        {:error, :fdx_missing_content}
    end
  end

  defp extract(_), do: {:error, :not_final_draft_xml}

  defp collect_paragraphs([], _dual_group, acc, _counter), do: Enum.reverse(acc)

  defp collect_paragraphs([{"Paragraph", attrs, children} | rest], dual_group, acc, counter) do
    type = attr(attrs, "Type") || "General"

    case Enum.find(children, &match?({"DualDialogue", _, _}, &1)) do
      {"DualDialogue", _, dual_children} ->
        group = "dual-#{counter}"
        dual = collect_paragraphs(dual_children, group, [], counter + 1)
        collect_paragraphs(rest, dual_group, Enum.reverse(dual, acc), counter + 1)

      nil ->
        runs =
          children
          |> Enum.filter(&match?({"Text", _, _}, &1))
          |> Enum.map(&text_run/1)

        scene_props = children |> Enum.find(&match?({"SceneProperties", _, _}, &1)) |> element_attrs()

        paragraph = %{
          type: type,
          text: fountain_text_from_runs(runs),
          plain_text: Enum.map_join(runs, & &1.text),
          runs: runs,
          attrs: Map.new(attrs),
          scene_properties: scene_props,
          dual_group: dual_group
        }

        collect_paragraphs(rest, dual_group, [paragraph | acc], counter + 1)
    end
  end

  defp collect_paragraphs([{"DualDialogue", _, children} | rest], _dual_group, acc, counter) do
    group = "dual-#{counter}"
    dual = collect_paragraphs(children, group, [], counter + 1)
    collect_paragraphs(rest, nil, Enum.reverse(dual, acc), counter + 1)
  end

  defp collect_paragraphs([_ | rest], dual_group, acc, counter),
    do: collect_paragraphs(rest, dual_group, acc, counter + 1)

  defp paragraphs_to_fountain(paragraphs) do
    dual_second_characters = dual_second_character_indexes(paragraphs)

    paragraphs
    |> Enum.with_index()
    |> Enum.map(fn {paragraph, index} ->
      next = Enum.at(paragraphs, index + 1)
      paragraph_to_fountain(paragraph, next, index, dual_second_characters)
    end)
    |> IO.iodata_to_binary()
    |> ensure_single_final_newline()
  end

  defp paragraph_to_fountain(paragraph, next, index, dual_second_characters) do
    text = paragraph_text(paragraph)
    fountain_paragraph(paragraph.type, text, paragraph, next, index, dual_second_characters)
  end

  defp paragraph_text(%{type: type, plain_text: text})
       when type in ["Scene Heading", "Character", "Transition", "Shot"],
       do: text || ""

  defp paragraph_text(paragraph), do: paragraph.text || ""

  defp fountain_paragraph("Scene Heading", text, paragraph, _next, _index, _dual) do
    number = Map.get(paragraph.scene_properties || %{}, "Number")
    suffix = if is_binary(number) and number != "", do: " ##{number}#", else: ""
    prefix = if Fount.SceneHeading.standard_fountain?(text), do: "", else: "."
    [prefix, text, suffix, "\n\n"]
  end

  defp fountain_paragraph("Character", text, _paragraph, _next, index, dual) do
    prefix = if String.upcase(text) == text, do: "", else: "@"
    [prefix, text, if(MapSet.member?(dual, index), do: " ^\n", else: "\n")]
  end

  defp fountain_paragraph("Parenthetical", text, _paragraph, _next, _index, _dual),
    do: [ensure_parenthetical(text), "\n"]

  defp fountain_paragraph("Dialogue", text, _paragraph, next, _index, _dual),
    do: [text, if(dialogue_continues?(next), do: "\n", else: "\n\n")]

  defp fountain_paragraph("Lyrics", text, _paragraph, _next, _index, _dual), do: ["~", text, "\n\n"]
  defp fountain_paragraph("Shot", text, _paragraph, _next, _index, _dual), do: [".", text, "\n\n"]
  defp fountain_paragraph(_type, text, _paragraph, _next, _index, _dual), do: [text, "\n\n"]

  defp dialogue_continues?(%{type: type}) when type in ["Dialogue", "Parenthetical"], do: true
  defp dialogue_continues?(_), do: false

  defp ensure_single_final_newline(binary) do
    String.trim_trailing(binary, "\n") <> "\n"
  end

  defp dual_second_character_indexes(paragraphs) do
    paragraphs
    |> Enum.with_index()
    |> Enum.group_by(fn {paragraph, _index} -> paragraph.dual_group end)
    |> Map.delete(nil)
    |> Enum.reduce(MapSet.new(), fn {_group, entries}, set ->
      characters = Enum.filter(entries, fn {paragraph, _} -> paragraph.type == "Character" end)

      case Enum.at(characters, 1) do
        nil -> set
        {_paragraph, index} -> MapSet.put(set, index)
      end
    end)
  end

  defp export_elements(doc) do
    element_map = Map.new(doc.ir.elements, &{&1.id, &1})
    dual_right_ids = doc.ir.dialogue_blocks |> Enum.filter(&(&1.side == :right)) |> Enum.map(& &1.id) |> MapSet.new()
    block_by_cue = Map.new(doc.ir.dialogue_blocks, &{&1.cue_id, &1})

    {children, losses, _consumed} =
      Enum.reduce(doc.ir.elements, {[], [], MapSet.new()}, fn element, {children, losses, consumed} ->
        export_element(element, {children, losses, consumed}, doc, element_map, block_by_cue, dual_right_ids)
      end)

    {children, losses}
  end

  defp export_element(element_data, {children, losses, consumed}, doc, element_map, blocks, dual_right_ids) do
    cond do
      MapSet.member?(consumed, element_data.id) ->
        {children, losses, consumed}

      element_data.type == :character and Map.has_key?(blocks, element_data.id) ->
        export_dialogue_block(blocks[element_data.id], {children, losses, consumed}, doc, element_map, dual_right_ids)

      element_data.type == :blank ->
        {children, losses, MapSet.put(consumed, element_data.id)}

      element_data.type in [:section, :synopsis, :note, :boneyard, :page_break] ->
        {children, ["#{element_data.type} not represented in base FDX export" | losses],
         MapSet.put(consumed, element_data.id)}

      true ->
        losses = losses |> maybe_add_inline_loss(element_data) |> maybe_add_projection_loss(element_data)
        {children ++ [paragraph_element(element_data)], losses, MapSet.put(consumed, element_data.id)}
    end
  end

  defp export_dialogue_block(block, state, doc, element_map, dual_right_ids) do
    cond do
      block.side == :left and block.dual_with -> export_dual_block(block, state, doc, element_map)
      MapSet.member?(dual_right_ids, block.id) -> state
      true -> export_single_block(block, state, element_map)
    end
  end

  defp export_dual_block(block, {children, losses, consumed}, doc, element_map) do
    right = Enum.find(doc.ir.dialogue_blocks, &(&1.id == block.dual_with))
    ids = [block.cue_id | block.body_ids] ++ [right.cue_id | right.body_ids]
    paragraphs = Enum.map(ids, &paragraph_element(Map.fetch!(element_map, &1)))
    outer = element("Paragraph", [], [element("DualDialogue", [], paragraphs)])
    {children ++ [outer], inline_losses(ids, element_map, losses), put_all(consumed, ids)}
  end

  defp export_single_block(block, {children, losses, consumed}, element_map) do
    ids = [block.cue_id | block.body_ids]
    paragraphs = Enum.map(ids, &paragraph_element(Map.fetch!(element_map, &1)))
    {children ++ paragraphs, inline_losses(ids, element_map, losses), put_all(consumed, ids)}
  end

  defp put_all(set, ids), do: Enum.reduce(ids, set, &MapSet.put(&2, &1))

  defp inline_losses(ids, element_map, losses) do
    Enum.reduce(ids, losses, fn id, acc -> maybe_add_inline_loss(acc, Map.fetch!(element_map, id)) end)
  end

  defp maybe_add_inline_loss(losses, %{inline: marks}) when is_list(marks) and marks != [],
    do: ["inline Fountain styling is flattened in base FDX export" | losses]

  defp maybe_add_inline_loss(losses, _), do: losses

  defp maybe_add_projection_loss(losses, %{type: :centered}),
    do: ["centered Fountain element exported as FDX Action" | losses]

  defp maybe_add_projection_loss(losses, _), do: losses

  defp paragraph_element(element_data) do
    text = paragraph_export_text(element_data)
    children = paragraph_children(element_data, text)
    element("Paragraph", [{"Type", paragraph_type(element_data.type)}], children)
  end

  defp paragraph_type(:scene_heading), do: "Scene Heading"
  defp paragraph_type(:action), do: "Action"
  defp paragraph_type(:character), do: "Character"
  defp paragraph_type(:dialogue), do: "Dialogue"
  defp paragraph_type(:parenthetical), do: "Parenthetical"
  defp paragraph_type(:transition), do: "Transition"
  defp paragraph_type(:lyric), do: "Lyrics"
  defp paragraph_type(:centered), do: "Action"
  defp paragraph_type(_), do: "General"

  defp paragraph_export_text(%{type: :character} = data) do
    case Map.get(data.attrs || %{}, :extension) do
      extension when is_binary(extension) and extension != "" -> data.text <> " " <> extension
      _ -> data.text
    end
  end

  defp paragraph_export_text(data), do: data.text

  defp paragraph_children(%{type: :scene_heading} = data, text) do
    attrs =
      case Map.get(data.attrs || %{}, :number) do
        nil -> []
        number -> [{"Number", to_string(number)}]
      end

    [element("SceneProperties", attrs, []), element("Text", [], characters(text))]
  end

  defp paragraph_children(_data, text), do: [element("Text", [], characters(text))]

  defp export_title_page(nil), do: []

  defp export_title_page(%{entries: entries}) do
    Enum.flat_map(entries, fn entry ->
      values = if entry.values == [], do: [""], else: entry.values

      Enum.map(values, fn value ->
        element("Paragraph", [{"Type", "Action"}], [element("Text", [], characters("#{entry.key}: #{value}"))])
      end)
    end)
  end

  defp import_losses(simple, paragraphs) do
    []
    |> maybe_loss(find_element(simple, "TitlePage"), "FDX title-page positioning/formatting is not preserved on import")
    |> maybe_loss(has_attribute?(simple, "RevisionID"), "FDX revision metadata is not imported into screenplay truth")
    |> maybe_loss(find_element(simple, "ScriptNote"), "FDX script notes are not yet projected into Fountain notes")
    |> maybe_loss(find_element(simple, "TagData"), "FDX production tags are not imported into screenplay truth")
    |> maybe_loss(find_element(simple, "LockedPages"), "FDX locked-page production state is not imported")
    |> maybe_loss(find_element(simple, "Summary"), "FDX scene summaries are not imported")
    |> then(&(&1 ++ unsupported_style_losses(paragraphs) ++ structural_style_losses(paragraphs)))
    |> Enum.uniq()
  end

  defp maybe_loss(losses, nil, _message), do: losses
  defp maybe_loss(losses, false, _message), do: losses
  defp maybe_loss(losses, _present, message), do: losses ++ [message]

  defp unsupported_style_losses(paragraphs) do
    paragraphs
    |> Enum.flat_map(& &1.runs)
    |> Enum.flat_map(& &1.styles)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(@supported_styles, &1))
    |> Enum.map(&"FDX text style #{&1} has no lossless Fountain equivalent")
  end

  defp structural_style_losses(paragraphs) do
    if Enum.any?(paragraphs, fn paragraph ->
         paragraph.type in ["Scene Heading", "Character", "Transition", "Shot"] and
           Enum.any?(paragraph.runs, &(&1.styles != []))
       end) do
      ["FDX styling on structural paragraph types is flattened on Fountain import"]
    else
      []
    end
  end

  defp text_run({"Text", attrs, children}) do
    style = attr(attrs, "Style") || ""

    %{
      text: text_children(children),
      styles: style |> String.split("+", trim: true) |> Enum.reject(&(&1 == "")),
      revision_id: attr(attrs, "RevisionID")
    }
  end

  defp fountain_text_from_runs(runs) do
    Enum.map_join(runs, fn run -> apply_fountain_styles(run.text, run.styles) end)
  end

  defp apply_fountain_styles(text, styles) do
    supported = MapSet.intersection(MapSet.new(styles), @supported_styles)
    bold? = MapSet.member?(supported, "Bold")
    italic? = MapSet.member?(supported, "Italic")
    underline? = MapSet.member?(supported, "Underline")

    text =
      cond do
        bold? and italic? -> "***" <> text <> "***"
        bold? -> "**" <> text <> "**"
        italic? -> "*" <> text <> "*"
        true -> text
      end

    if underline?, do: "_" <> text <> "_", else: text
  end

  defp find_element({name, _attrs, _children} = found, wanted) when name == wanted, do: found

  defp find_element({_name, _attrs, children}, wanted) do
    Enum.find_value(children, fn
      {_, _, _} = child -> find_element(child, wanted)
      _ -> nil
    end)
  end

  defp has_attribute?({_name, attrs, children}, wanted) do
    Enum.any?(attrs, fn {name, _value} -> name == wanted end) or
      Enum.any?(children, fn
        {_, _, _} = child -> has_attribute?(child, wanted)
        _ -> false
      end)
  end

  defp text_children(children) do
    Enum.map_join(children, fn
      value when is_binary(value) -> value
      {:cdata, value} -> value
      _ -> ""
    end)
  end

  defp element_attrs(nil), do: %{}
  defp element_attrs({_name, attrs, _children}), do: Map.new(attrs)
  defp attr(attrs, key), do: Enum.find_value(attrs, fn {name, value} -> if name == key, do: value end)

  defp ensure_parenthetical(text) do
    if String.starts_with?(text, "(") and String.ends_with?(text, ")"), do: text, else: "(" <> text <> ")"
  end
end
