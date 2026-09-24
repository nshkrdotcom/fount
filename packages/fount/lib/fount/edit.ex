defmodule Fount.Edit do
  @moduledoc "Source-backed edit algebra for screenplay refactoring, structured generation, and agent operations."

  alias Fount.{Annotations, Document, Fragment, Index}
  alias Fount.Edit.{ChangeSet, Op, Patch, Step}
  alias Fount.Source.Span

  @spec replace_text(String.t(), binary()) :: Op.t()
  def replace_text(element_id, text), do: %Op{kind: :replace_text, target: element_id, value: text}

  @spec set_scene_heading(String.t(), binary()) :: Op.t()
  def set_scene_heading(scene_id, heading), do: %Op{kind: :set_scene_heading, target: scene_id, value: heading}

  @spec rename_character(binary(), binary()) :: Op.t()
  def rename_character(old_name, new_name), do: %Op{kind: :rename_character, target: old_name, value: new_name}

  @spec insert_before(String.t(), binary() | Fragment.t()) :: Op.t()
  def insert_before(element_id, source_or_fragment),
    do: %Op{kind: :insert_before, target: element_id, value: source_or_fragment}

  @spec insert_after(String.t(), binary() | Fragment.t()) :: Op.t()
  def insert_after(element_id, source_or_fragment),
    do: %Op{kind: :insert_after, target: element_id, value: source_or_fragment}

  @spec insert_scene_after(String.t(), binary(), [Fragment.t() | binary()], keyword()) :: Op.t()
  def insert_scene_after(scene_id, heading, content \\ [], opts \\ []) do
    %Op{
      kind: :insert_scene_after,
      target: scene_id,
      value: %{heading: heading, content: content, options: opts}
    }
  end

  @spec insert_dialogue_after(String.t(), binary(), binary() | [binary()], keyword()) :: Op.t()
  def insert_dialogue_after(element_id, character, text, opts \\ []) do
    %Op{
      kind: :insert_dialogue_after,
      target: element_id,
      value: %{character: character, text: text, options: opts}
    }
  end

  @spec delete(String.t()) :: Op.t()
  def delete(element_id), do: %Op{kind: :delete, target: element_id}

  @spec delete_scene(String.t()) :: Op.t()
  def delete_scene(scene_id), do: %Op{kind: :delete_scene, target: scene_id}

  @spec move_scene(String.t(), String.t()) :: Op.t()
  def move_scene(scene_id, after_scene_id), do: %Op{kind: :move_scene, target: scene_id, value: after_scene_id}

  @spec apply(Document.t(), Op.t() | [Op.t()], keyword()) ::
          {:ok, Document.t(), ChangeSet.t()} | {:error, term()}
  def apply(%Document{} = original, operations, opts \\ []) do
    operations = List.wrap(operations)

    result =
      Enum.reduce_while(operations, {:ok, original, [], MapSet.new()}, fn op,
                                                                          {:ok, doc, steps, affected} ->
        case apply_one(doc, op, opts) do
          {:ok, next, op_patches, op_affected} ->
            step = %Step{
              before_revision: doc.revision.id,
              after_revision: next.revision.id,
              operation: op,
              patches: op_patches,
              affected_node_ids: MapSet.to_list(op_affected)
            }

            {:cont, {:ok, next, steps ++ [step], MapSet.union(affected, op_affected)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    with {:ok, final, steps, affected} <- result do
      affected = affected |> expand_affected(original) |> expand_affected(final)
      annotations = Annotations.invalidate_nodes(final.annotations, affected)
      final = %{final | annotations: annotations, index: Index.build(final.ir)}

      change_set = %ChangeSet{
        before_revision: original.revision.id,
        after_revision: final.revision.id,
        operations: operations,
        steps: steps,
        patches: Enum.flat_map(steps, & &1.patches),
        affected_node_ids: MapSet.to_list(affected),
        diagnostics: final.diagnostics,
        inverse_source: original.source.raw,
        inverse_identity_anchors: Fount.Identity.anchors(original.ir),
        inverse_annotations: original.annotations,
        forward_source: final.source.raw,
        forward_identity_anchors: Fount.Identity.anchors(final.ir),
        forward_annotations: final.annotations
      }

      {:ok, final, change_set}
    end
  end

  @spec undo(Document.t(), ChangeSet.t()) :: {:ok, Document.t()} | {:error, term()}
  def undo(%Document{} = current, %ChangeSet{inverse_source: raw} = change_set) when is_binary(raw) do
    Fount.parse(raw,
      document_id: current.id,
      identity_anchors: change_set.inverse_identity_anchors || [],
      annotations: change_set.inverse_annotations || Annotations.new(),
      parent_revision_id: current.revision.id,
      message: "undo"
    )
  end

  @spec redo(Document.t(), ChangeSet.t()) :: {:ok, Document.t()} | {:error, term()}
  def redo(%Document{} = current, %ChangeSet{forward_source: raw} = change_set) when is_binary(raw) do
    Fount.parse(raw,
      document_id: current.id,
      identity_anchors: change_set.forward_identity_anchors || [],
      annotations: change_set.forward_annotations || Annotations.new(),
      parent_revision_id: current.revision.id,
      message: "redo"
    )
  end

  defp apply_one(doc, %Op{kind: :replace_text, target: id, value: text}, _opts) when is_binary(text) do
    with element when not is_nil(element) <- Fount.Query.node(doc, id),
         %Span{} = span <- element.content_span do
      patch = patch(span, text, id, :replace_text)
      hint = %{old_id: id, type: element.type, byte_start: span.byte_start}
      reparse_with_patches(doc, [patch], [hint], MapSet.new([id]))
    else
      nil -> {:error, {:unknown_element, id}}
      _ -> {:error, {:element_not_source_addressable, id}}
    end
  end

  defp apply_one(doc, %Op{kind: :set_scene_heading, target: scene_id, value: heading}, _opts)
       when is_binary(heading) do
    with scene when not is_nil(scene) <- Fount.Query.scene(doc, scene_id),
         element when not is_nil(element) <- Fount.Query.node(doc, scene.heading_id),
         %Span{} = span <- element.content_span do
      already_forced? = Map.get(element.attrs || %{}, :forced?, false)
      force? = not already_forced? and not Fount.SceneHeading.standard_fountain?(heading)
      replacement = if force?, do: "." <> heading, else: heading
      patch = patch(span, replacement, element.id, :set_scene_heading)
      hint = %{old_id: element.id, type: :scene_heading, byte_start: span.byte_start}
      reparse_with_patches(doc, [patch], [hint], MapSet.new([scene.id, element.id]))
    else
      nil -> {:error, {:unknown_scene, scene_id}}
      _ -> {:error, {:scene_not_source_addressable, scene_id}}
    end
  end

  defp apply_one(doc, %Op{kind: :rename_character, target: old_name, value: new_name}, _opts)
       when is_binary(old_name) and is_binary(new_name) do
    cues = Fount.Query.character_cues(doc, old_name)

    if cues == [] do
      {:error, {:unknown_character, old_name}}
    else
      patches =
        Enum.map(cues, fn cue ->
          forced? = Map.get(cue.attrs || %{}, :forced?, false)
          needs_force? = not forced? and String.upcase(new_name) != new_name
          replacement = if needs_force?, do: "@" <> new_name, else: new_name
          patch(cue.content_span, replacement, cue.id, :rename_character)
        end)

      hints =
        Enum.map(cues, fn cue ->
          %{
            old_id: cue.id,
            type: cue.type,
            byte_start: Patch.translate_offset(cue.source_span.byte_start, patches)
          }
        end)

      affected = cues |> Enum.map(& &1.id) |> MapSet.new()
      reparse_with_patches(doc, patches, hints, affected)
    end
  end

  defp apply_one(doc, %Op{kind: :insert_before, target: id, value: value}, _opts) do
    with element when not is_nil(element) <- Fount.Query.node(doc, id),
         %Span{} = span <- element.source_span,
         {:ok, raw} <- source_value(value, doc) do
      patch = %Patch{
        byte_start: span.byte_start,
        byte_end: span.byte_start,
        replacement: raw,
        target_id: id,
        kind: :insert_before
      }

      reparse_with_patches(doc, [patch], [], MapSet.new([id]))
    else
      nil -> {:error, {:unknown_element, id}}
      {:error, _} = error -> error
      _ -> {:error, {:element_not_source_addressable, id}}
    end
  end

  defp apply_one(doc, %Op{kind: :insert_after, target: id, value: value}, _opts) do
    with element when not is_nil(element) <- Fount.Query.node(doc, id),
         %Span{} = span <- element.source_span,
         {:ok, raw} <- source_value(value, doc) do
      patch = %Patch{
        byte_start: span.byte_end,
        byte_end: span.byte_end,
        replacement: raw,
        target_id: id,
        kind: :insert_after
      }

      reparse_with_patches(doc, [patch], [], MapSet.new([id]))
    else
      nil -> {:error, {:unknown_element, id}}
      {:error, _} = error -> error
      _ -> {:error, {:element_not_source_addressable, id}}
    end
  end

  defp apply_one(
         doc,
         %Op{kind: :insert_scene_after, target: scene_id, value: %{heading: heading, content: content, options: options}},
         _opts
       ) do
    with scene when not is_nil(scene) <- Fount.Query.scene(doc, scene_id),
         %Span{} = span <- scene.source_span do
      newline = preferred_newline(doc)
      normalized_content = Enum.map(List.wrap(content), &normalize_fragment(&1, newline))
      fragment = Fragment.scene(heading, normalized_content, Keyword.put(options, :newline, newline))
      replacement = ensure_leading_blank(doc.source.raw, span.byte_end, fragment.source, newline)

      patch = %Patch{
        byte_start: span.byte_end,
        byte_end: span.byte_end,
        replacement: replacement,
        target_id: scene_id,
        kind: :insert_scene_after
      }

      reparse_with_patches(doc, [patch], [], MapSet.new([scene.id | scene.element_ids]))
    else
      nil -> {:error, {:unknown_scene, scene_id}}
      _ -> {:error, {:scene_not_source_addressable, scene_id}}
    end
  end

  defp apply_one(
         doc,
         %Op{kind: :insert_dialogue_after, target: element_id, value: %{character: character, text: text, options: options}},
         _opts
       ) do
    with element when not is_nil(element) <- Fount.Query.node(doc, element_id),
         %Span{} = span <- element.source_span do
      newline = preferred_newline(doc)
      fragment = Fragment.dialogue(character, text, Keyword.put(options, :newline, newline))
      replacement = ensure_leading_blank(doc.source.raw, span.byte_end, fragment.source, newline)

      patch = %Patch{
        byte_start: span.byte_end,
        byte_end: span.byte_end,
        replacement: replacement,
        target_id: element_id,
        kind: :insert_dialogue_after
      }

      reparse_with_patches(doc, [patch], [], MapSet.new([element_id]))
    else
      nil -> {:error, {:unknown_element, element_id}}
      _ -> {:error, {:element_not_source_addressable, element_id}}
    end
  end

  defp apply_one(doc, %Op{kind: :delete, target: id}, _opts) do
    with element when not is_nil(element) <- Fount.Query.node(doc, id),
         %Span{} = span <- element.source_span do
      patch = patch(span, "", id, :delete)
      reparse_with_patches(doc, [patch], [], MapSet.new([id]))
    else
      nil -> {:error, {:unknown_element, id}}
      _ -> {:error, {:element_not_source_addressable, id}}
    end
  end

  defp apply_one(doc, %Op{kind: :delete_scene, target: scene_id}, _opts) do
    with scene when not is_nil(scene) <- Fount.Query.scene(doc, scene_id),
         %Span{} = span <- scene.source_span do
      patch = patch(span, "", scene_id, :delete_scene)
      reparse_with_patches(doc, [patch], [], MapSet.new([scene.id | scene.element_ids]))
    else
      nil -> {:error, {:unknown_scene, scene_id}}
      _ -> {:error, {:scene_not_source_addressable, scene_id}}
    end
  end

  defp apply_one(doc, %Op{kind: :move_scene, target: scene_id, value: after_scene_id}, _opts) do
    with source_scene when not is_nil(source_scene) <- Fount.Query.scene(doc, scene_id),
         destination when not is_nil(destination) <- Fount.Query.scene(doc, after_scene_id),
         false <- source_scene.id == destination.id,
         %Span{} = source_span <- source_scene.source_span,
         %Span{} = destination_span <- destination.source_span do
      raw = Span.slice(doc.source.raw, source_span)
      delete_patch = patch(source_span, "", scene_id, :move_scene_delete)
      source_length = Span.length(source_span)

      insertion_offset =
        if source_span.byte_start < destination_span.byte_end do
          destination_span.byte_end - source_length
        else
          destination_span.byte_end
        end

      without_source = apply_patch!(doc.source.raw, [delete_patch])
      insert_patch = %Patch{
        byte_start: insertion_offset,
        byte_end: insertion_offset,
        replacement: raw,
        target_id: scene_id,
        kind: :move_scene_insert
      }

      final_raw = apply_patch!(without_source, [insert_patch])
      moved_elements = Enum.map(source_scene.element_ids, &Fount.Query.node(doc, &1)) |> Enum.reject(&is_nil/1)

      hints =
        Enum.map(moved_elements, fn element ->
          relative = element.source_span.byte_start - source_span.byte_start
          %{old_id: element.id, type: element.type, byte_start: insertion_offset + relative}
        end)

      affected = MapSet.new([source_scene.id, destination.id] ++ source_scene.element_ids ++ destination.element_ids)

      with {:ok, next} <-
             Fount.parse(final_raw,
               document_id: doc.id,
               prior: doc,
               identity_hints: hints,
               parent_revision_id: doc.revision.id,
               annotations: doc.annotations,
               message: "move scene"
             ) do
        {:ok, next, [delete_patch, insert_patch], affected}
      end
    else
      nil -> {:error, :unknown_scene}
      true -> {:error, :cannot_move_scene_after_itself}
      _ -> {:error, :scene_not_source_addressable}
    end
  end

  defp apply_one(_doc, %Op{} = op, _opts), do: {:error, {:unsupported_operation, op.kind}}

  defp reparse_with_patches(doc, patches, hints, affected) do
    with {:ok, raw} <- Patch.apply(doc.source.raw, patches),
         {:ok, next} <-
           Fount.parse(raw,
             document_id: doc.id,
             prior: doc,
             identity_hints: hints,
             parent_revision_id: doc.revision.id,
             annotations: doc.annotations
           ) do
      {:ok, next, patches, affected}
    end
  end

  defp expand_affected(ids, %Document{} = doc), do: expand_affected(doc, ids)

  defp expand_affected(%Document{} = doc, ids) do
    scene_ids =
      Enum.reduce(doc.index.scene_for_element, ids, fn {element_id, scene_id}, acc ->
        if MapSet.member?(acc, element_id), do: MapSet.put(acc, scene_id), else: acc
      end)

    dialogue_ids =
      Enum.reduce(doc.ir.dialogue_blocks, scene_ids, fn block, acc ->
        members = [block.cue_id | block.body_ids]
        if Enum.any?(members, &MapSet.member?(acc, &1)), do: MapSet.put(acc, block.id), else: acc
      end)

    Enum.reduce(doc.ir.outline, dialogue_ids, fn outline, acc ->
      touches_section = MapSet.member?(acc, outline.section_element_id)
      touches_scene = Enum.any?(outline.scene_ids, &MapSet.member?(acc, &1))
      if touches_section or touches_scene, do: MapSet.put(acc, outline.id), else: acc
    end)
  end

  defp source_value(%Fragment{} = fragment, doc), do: {:ok, normalize_fragment(fragment, preferred_newline(doc))}
  defp source_value(raw, _doc) when is_binary(raw), do: {:ok, raw}
  defp source_value(_, _doc), do: {:error, :invalid_insert_value}

  defp normalize_fragment(%Fragment{} = fragment, newline), do: normalize_fragment(fragment.source, newline)

  defp normalize_fragment(raw, newline) when is_binary(raw) do
    raw
    |> :binary.replace("\r\n", "\n", [:global])
    |> :binary.replace("\r", "\n", [:global])
    |> :binary.replace("\n", newline, [:global])
  end

  defp ensure_leading_blank(source, offset, replacement, newline) do
    prefix = binary_part(source, 0, offset)

    cond do
      ends_with?(prefix, newline <> newline) -> replacement
      ends_with?(prefix, newline) -> newline <> replacement
      prefix == "" -> replacement
      true -> newline <> newline <> replacement
    end
  end

  defp ends_with?(binary, suffix) when byte_size(binary) < byte_size(suffix), do: false

  defp ends_with?(binary, suffix) do
    size = byte_size(suffix)
    binary_part(binary, byte_size(binary) - size, size) == suffix
  end

  defp preferred_newline(%Document{source: %{newline_style: :crlf}}), do: "\r\n"
  defp preferred_newline(%Document{source: %{newline_style: :cr}}), do: "\r"
  defp preferred_newline(%Document{source: %{newline_style: :lf}}), do: "\n"

  defp preferred_newline(%Document{source: source}) do
    Enum.find_value(source.lines, "\n", fn line -> if line.eol != "", do: line.eol end)
  end

  defp patch(%Span{} = span, replacement, target_id, kind) do
    %Patch{
      byte_start: span.byte_start,
      byte_end: span.byte_end,
      replacement: replacement,
      target_id: target_id,
      kind: kind
    }
  end

  defp apply_patch!(source, patches) do
    {:ok, raw} = Patch.apply(source, patches)
    raw
  end
end
