defmodule Fount.IR do
  @moduledoc "Builders and structural views for the canonical screenplay IR."

  alias Fount.Fountain.CST
  alias Fount.IR.{DialogueBlock, Element, OutlineNode, Scene, Script, TitlePage}
  alias Fount.Source.Span

  @spec from_cst(String.t(), CST.t()) :: Script.t()
  def from_cst(document_id, %CST{} = cst) do
    elements =
      cst.nodes
      |> Enum.reject(&(&1.type in [:title_page, :title_trivia]))
      |> Enum.map(fn node ->
        %Element{
          id: node.id,
          type: normalize_type(node.type),
          text: node.text,
          raw_text: node.raw,
          source_span: node.span,
          content_span: node.content_span,
          inline: node.inline || [],
          attrs: node.attrs || %{},
          origin: :fountain
        }
      end)

    rebuild_views(%Script{
      document_id: document_id,
      title_page: cst.title_page,
      elements: elements,
      scenes: [],
      dialogue_blocks: [],
      outline: [],
      metadata: %{}
    })
  end

  @spec rebuild_views(Script.t()) :: Script.t()
  def rebuild_views(%Script{} = script) do
    {scenes, scene_paths} = build_scenes(script.document_id, script.elements)
    dialogue_blocks = build_dialogue_blocks(script.document_id, script.elements)
    outline = build_outline(script.document_id, script.elements, scenes)

    scenes =
      Enum.map(scenes, fn scene ->
        %{scene | outline_path: Map.get(scene_paths, scene.id, [])}
      end)

    %{script | scenes: scenes, dialogue_blocks: dialogue_blocks, outline: outline}
  end

  @doc "Replace element IDs and rebuild all views that reference them."
  @spec remap_ids(Script.t(), map()) :: Script.t()
  def remap_ids(%Script{} = script, id_map) when is_map(id_map) do
    elements = Enum.map(script.elements, &remap_item(&1, id_map))

    title_page =
      case script.title_page do
        %TitlePage{} = page -> %{page | entries: Enum.map(page.entries, &remap_item(&1, id_map))}
        nil -> nil
      end

    rebuild_views(%{script | elements: elements, title_page: title_page})
  end

  defp remap_item(item, id_map) do
    case Map.fetch(id_map, item.id) do
      {:ok, id} -> %{item | id: id}
      :error -> item
    end
  end

  @spec element(Script.t(), String.t()) :: Element.t() | nil
  def element(%Script{elements: elements}, id), do: Enum.find(elements, &(&1.id == id))

  @spec scene(Script.t(), String.t()) :: Scene.t() | nil
  def scene(%Script{scenes: scenes}, id), do: Enum.find(scenes, &(&1.id == id))

  defp normalize_type(:title_page), do: :unknown
  defp normalize_type(type), do: type

  defp build_scenes(document_id, elements) do
    {scenes, current, stack, paths} =
      Enum.reduce(elements, {[], nil, [], %{}}, fn element, {scenes, current, stack, paths} ->
        stack = update_section_stack(stack, element, document_id)

        cond do
          element.type == :scene_heading ->
            scenes = finish_scene(scenes, current)
            id = Fount.ID.v5(document_id, ["scene:", element.id])

            scene = %Scene{
              id: id,
              heading_id: element.id,
              element_ids: [element.id],
              source_span: element.source_span,
              number: get_in(element.attrs || %{}, [:number]),
              outline_path: Enum.map(stack, & &1.id)
            }

            {scenes, scene, stack, Map.put(paths, id, scene.outline_path)}

          element.type in [:section, :synopsis] and current != nil ->
            {finish_scene(scenes, current), nil, stack, paths}

          current != nil ->
            scene = append_to_scene(current, element)
            {scenes, scene, stack, paths}

          true ->
            {scenes, current, stack, paths}
        end
      end)

    {finish_scene(scenes, current), paths}
  end

  defp finish_scene(scenes, nil), do: scenes
  defp finish_scene(scenes, scene), do: scenes ++ [scene]

  defp append_to_scene(scene, element) do
    span = merge_spans(scene.source_span, element.source_span)
    %{scene | element_ids: scene.element_ids ++ [element.id], source_span: span}
  end

  defp build_dialogue_blocks(document_id, elements) do
    blocks = do_build_dialogue_blocks(elements, document_id, [])
    link_dual_dialogue(blocks, elements)
  end

  defp do_build_dialogue_blocks([], _document_id, acc), do: Enum.reverse(acc)

  defp do_build_dialogue_blocks([%Element{type: :character} = cue | rest], document_id, acc) do
    {body, tail} = Enum.split_while(rest, &(&1.type in [:parenthetical, :dialogue]))

    ids = Enum.map(body, & &1.id)
    last = List.last(body) || cue
    span = merge_spans(cue.source_span, last.source_span)

    block = %DialogueBlock{
      id: Fount.ID.v5(document_id, ["dialogue-block:", cue.id]),
      cue_id: cue.id,
      body_ids: ids,
      source_span: span,
      dual_with: nil,
      side: nil
    }

    do_build_dialogue_blocks(tail, document_id, [block | acc])
  end

  defp do_build_dialogue_blocks([_ | rest], document_id, acc),
    do: do_build_dialogue_blocks(rest, document_id, acc)

  defp link_dual_dialogue(blocks, elements) do
    element_map = Map.new(elements, &{&1.id, &1})

    Enum.reduce(Enum.with_index(blocks), blocks, fn {block, index}, current ->
      cue = Map.get(element_map, block.cue_id)
      dual? = cue && Map.get(cue.attrs || %{}, :dual?, false)

      if dual? and index > 0 do
        previous = Enum.at(current, index - 1)
        left = %{previous | dual_with: block.id, side: :left}
        right = %{block | dual_with: previous.id, side: :right}
        current |> List.replace_at(index - 1, left) |> List.replace_at(index, right)
      else
        current
      end
    end)
  end

  defp build_outline(document_id, elements, scenes) do
    scene_by_heading = Map.new(scenes, &{&1.heading_id, &1})

    {nodes, stack} =
      Enum.reduce(elements, {[], []}, fn element, {nodes, stack} ->
        cond do
          element.type == :section ->
            level = Map.get(element.attrs || %{}, :level, 1)
            stack = Enum.take_while(stack, &(&1.level < level))
            parent = List.last(stack)

            node = %OutlineNode{
              id: Fount.ID.v5(document_id, ["outline:", element.id]),
              section_element_id: element.id,
              level: level,
              title: element.text,
              parent_id: parent && parent.id,
              child_ids: [],
              scene_ids: []
            }

            nodes =
              if parent do
                Enum.map(nodes, fn existing ->
                  if existing.id == parent.id,
                    do: %{existing | child_ids: existing.child_ids ++ [node.id]},
                    else: existing
                end)
              else
                nodes
              end

            {nodes ++ [node], stack ++ [node]}

          element.type == :scene_heading and stack != [] ->
            case Map.get(scene_by_heading, element.id) do
              nil -> {nodes, stack}
              scene ->
                ids = MapSet.new(Enum.map(stack, & &1.id))

                nodes =
                  Enum.map(nodes, fn node ->
                    if MapSet.member?(ids, node.id),
                      do: %{node | scene_ids: node.scene_ids ++ [scene.id]},
                      else: node
                  end)

                {nodes, stack}
            end

          true ->
            {nodes, stack}
        end
      end)

    _ = stack
    nodes
  end

  defp update_section_stack(stack, %Element{type: :section} = element, document_id) do
    level = Map.get(element.attrs || %{}, :level, 1)
    prefix = Enum.take_while(stack, &(&1.level < level))
    prefix ++ [%{id: Fount.ID.v5(document_id, ["outline:", element.id]), level: level}]
  end

  defp update_section_stack(stack, _element, _document_id), do: stack

  defp merge_spans(nil, right), do: right
  defp merge_spans(left, nil), do: left

  defp merge_spans(%Span{} = left, %Span{} = right) do
    Span.new(min(left.byte_start, right.byte_start), max(left.byte_end, right.byte_end),
      line_start: left.line_start || right.line_start,
      line_end: right.line_end || left.line_end
    )
  end
end
