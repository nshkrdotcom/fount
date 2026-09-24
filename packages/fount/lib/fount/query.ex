defmodule Fount.Query do
  @moduledoc "Headless screenplay query API."

  alias Fount.Document
  alias Fount.Source.Span

  def node(%Document{index: index}, id), do: Map.get(index.by_id, id)
  def scene(%Document{index: index}, id), do: Map.get(index.scenes_by_id, id)
  def dialogue_block(%Document{index: index}, id), do: Map.get(index.dialogue_blocks_by_id, id)
  def scenes(%Document{ir: ir}), do: ir.scenes
  def dialogue_blocks(%Document{ir: ir}), do: ir.dialogue_blocks
  def outline(%Document{ir: ir}), do: ir.outline
  def elements(%Document{ir: ir}), do: ir.elements
  def elements(%Document{index: index}, type), do: Map.get(index.by_type, type, [])

  def node_at(%Document{ir: ir}, byte_offset) when is_integer(byte_offset) and byte_offset >= 0 do
    Enum.find(ir.elements, fn element ->
      case element.source_span do
        nil -> false
        span -> Span.contains?(span, byte_offset)
      end
    end)
  end

  def nodes_in_span(%Document{ir: ir}, %Span{} = span) do
    Enum.filter(ir.elements, fn element ->
      case element.source_span do
        nil -> false
        element_span -> Span.overlaps?(element_span, span)
      end
    end)
  end

  def scene_for(%Document{index: index} = doc, element_id) do
    with scene_id when not is_nil(scene_id) <- Map.get(index.scene_for_element, element_id) do
      scene(doc, scene_id)
    end
  end

  def character_cues(%Document{index: index}, name) do
    key = Fount.Index.normalize_character(name)
    Enum.map(Map.get(index.character_cues, key, []), &Map.get(index.by_id, &1))
  end

  def characters(%Document{index: index}) do
    index.character_cues
    |> Enum.map(fn {name, ids} -> %{name: name, cue_ids: ids, cue_count: length(ids)} end)
    |> Enum.sort_by(&{-&1.cue_count, &1.name})
  end

  def search_text(%Document{ir: ir}, needle, opts \\ []) when is_binary(needle) do
    case_sensitive? = Keyword.get(opts, :case_sensitive, false)
    wanted = if case_sensitive?, do: needle, else: String.downcase(needle)

    Enum.filter(ir.elements, &text_matches?(&1.text || "", wanted, case_sensitive?))
  end

  defp text_matches?(text, wanted, case_sensitive?) do
    if String.valid?(text) do
      haystack = if case_sensitive?, do: text, else: String.downcase(text)
      String.contains?(haystack, wanted)
    else
      false
    end
  end
end
