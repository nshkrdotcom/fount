defmodule Fount.Validate do
  @moduledoc "Structural validation of CST coverage, source spans, identities, and IR references."

  alias Fount.{Diagnostic, Document}
  alias Fount.Fountain.CST
  alias Fount.Source.Span

  @spec document(Document.t()) :: [Diagnostic.t()]
  def document(%Document{} = doc) do
    []
    |> validate_cst_exactness(doc)
    |> validate_cst_nodes(doc)
    |> validate_unique_ids(doc)
    |> validate_spans(doc)
    |> validate_cst_ir_alignment(doc)
    |> validate_title_identity(doc)
    |> validate_scene_refs(doc)
    |> validate_dialogue_refs(doc)
    |> Enum.reverse()
  end

  @doc "Checks canonical structure independently of source parsing."
  def screenplay(model) do
    ids = Enum.map(model.ir.elements, & &1.id)
    membership = Enum.flat_map(model.ir.scenes, & &1.element_ids)
    blocks = model.ir.dialogue_blocks
    body_ids = Enum.flat_map(blocks, & &1.body_ids)
    errors = []

    errors =
      if length(ids) != length(Enum.uniq(ids)),
        do: [error(:duplicate_element_id, "Duplicate element identity") | errors],
        else: errors

    errors =
      if length(membership) != length(Enum.uniq(membership)),
        do: [error(:duplicate_membership, "Element belongs to multiple scenes") | errors],
        else: errors

    errors =
      Enum.reduce(model.ir.elements, errors, fn e, acc ->
        cond do
          e.type in [:dialogue, :parenthetical] and e.id not in body_ids ->
            [error(:orphan_dialogue, "Dialogue has no cue", e.id) | acc]

          not is_binary(e.text) or not String.valid?(e.text) ->
            [error(:invalid_text, "Invalid UTF-8 text", e.id) | acc]

          true ->
            acc
        end
      end)

    errors =
      Enum.reduce(blocks, errors, fn b, acc ->
        partner = Enum.find(blocks, &(&1.id == b.dual_with))
        cue = Fount.Query.node(model, b.cue_id)
        scene = Fount.Query.scene_for(model, b.cue_id)

        invalid =
          b.body_ids == [] or
            (not is_nil(b.dual_with) and
               (is_nil(partner) or partner.dual_with != b.id or partner.side == b.side or
                  Fount.Query.scene_for(model, partner.cue_id) != scene)) or
            (Map.get(cue.attrs || %{}, :dual?, false) and is_nil(b.dual_with)) or
            Enum.any?(b.body_ids, &(Fount.Query.scene_for(model, &1) != scene))

        if invalid, do: [error(:invalid_dialogue_group, "Invalid dialogue or dual group", b.id) | acc], else: acc
      end)

    Enum.reverse(errors)
  end

  defp validate_cst_exactness(diags, doc) do
    if CST.exact?(doc.cst, doc.source) do
      diags
    else
      [error(:cst_source_mismatch, "CST does not reconstruct the exact source binary.") | diags]
    end
  end

  defp validate_cst_nodes(diags, doc) do
    {_offset, diags} =
      Enum.reduce(doc.cst.nodes, {0, diags}, fn node, {expected_start, acc} ->
        acc =
          cond do
            node.span.byte_start != expected_start ->
              [
                %Diagnostic{
                  severity: :error,
                  code: :cst_gap_or_overlap,
                  message: "CST node does not begin where the previous node ended.",
                  span: node.span,
                  node_id: node.id
                }
                | acc
              ]

            not Span.valid_for?(node.span, doc.source.raw) ->
              [error(:invalid_cst_span, "CST node span is outside the source binary.", node.id) | acc]

            Span.slice(doc.source.raw, node.span) != node.raw ->
              [error(:cst_raw_mismatch, "CST node raw bytes do not match its source span.", node.id) | acc]

            not content_inside?(node.content_span, node.span) ->
              [error(:content_span_outside_node, "CST content span lies outside its source node.", node.id) | acc]

            true ->
              acc
          end

        {node.span.byte_end, acc}
      end)

    final_end =
      case List.last(doc.cst.nodes) do
        nil -> 0
        node -> node.span.byte_end
      end

    if final_end == byte_size(doc.source.raw) do
      diags
    else
      [error(:cst_incomplete_coverage, "CST nodes do not cover the full source binary.") | diags]
    end
  end

  defp content_inside?(nil, _source), do: true

  defp content_inside?(%Span{} = content, %Span{} = source) do
    content.byte_start >= source.byte_start and content.byte_end <= source.byte_end
  end

  defp validate_unique_ids(diags, doc) do
    ids = Enum.map(doc.ir.elements, & &1.id)

    if length(ids) == MapSet.size(MapSet.new(ids)) do
      diags
    else
      [error(:duplicate_element_id, "IR contains duplicate element IDs.") | diags]
    end
  end

  defp validate_spans(diags, doc) do
    Enum.reduce(doc.ir.elements, diags, fn element, acc ->
      validate_element_span(acc, element, doc.source.raw)
    end)
  end

  defp validate_element_span(diags, %{source_span: nil}, _raw), do: diags

  defp validate_element_span(diags, %{source_span: %Span{} = span} = element, raw) do
    cond do
      not Span.valid_for?(span, raw) ->
        [
          %Diagnostic{
            severity: :error,
            code: :invalid_source_span,
            message: "Element source span is outside the source binary.",
            span: span,
            node_id: element.id
          }
          | diags
        ]

      not content_inside?(element.content_span, span) ->
        [
          error(:element_content_span_outside_source, "Element content span lies outside its source span.", element.id)
          | diags
        ]

      true ->
        diags
    end
  end

  defp validate_cst_ir_alignment(diags, doc) do
    cst_ids =
      doc.cst.nodes
      |> Enum.reject(&(&1.type in [:title_page, :title_trivia]))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    ir_ids = doc.ir.elements |> Enum.map(& &1.id) |> MapSet.new()

    if MapSet.equal?(cst_ids, ir_ids) do
      diags
    else
      [error(:cst_ir_identity_mismatch, "CST screenplay node IDs and semantic IR element IDs diverge.") | diags]
    end
  end

  defp validate_title_identity(diags, doc) do
    cst_ids =
      doc.cst.nodes
      |> Enum.filter(&(&1.type == :title_page))
      |> Enum.map(& &1.id)

    ir_ids = if doc.ir.title_page, do: Enum.map(doc.ir.title_page.entries, & &1.id), else: []

    if cst_ids == ir_ids do
      diags
    else
      [error(:title_identity_mismatch, "CST title nodes and IR title entries have different IDs.") | diags]
    end
  end

  defp validate_scene_refs(diags, doc) do
    ids = MapSet.new(Enum.map(doc.ir.elements, & &1.id))

    Enum.reduce(doc.ir.scenes, diags, fn scene, acc ->
      invalid = Enum.reject([scene.heading_id | scene.element_ids], &MapSet.member?(ids, &1))

      if invalid == [],
        do: acc,
        else: [error(:dangling_scene_reference, "Scene references missing elements.", scene.id) | acc]
    end)
  end

  defp validate_dialogue_refs(diags, doc) do
    ids = MapSet.new(Enum.map(doc.ir.elements, & &1.id))

    Enum.reduce(doc.ir.dialogue_blocks, diags, fn block, acc ->
      invalid = Enum.reject([block.cue_id | block.body_ids], &MapSet.member?(ids, &1))

      if invalid == [],
        do: acc,
        else: [error(:dangling_dialogue_reference, "Dialogue block references missing elements.", block.id) | acc]
    end)
  end

  defp error(code, message, node_id \\ nil),
    do: %Diagnostic{severity: :error, code: code, message: message, node_id: node_id}
end
