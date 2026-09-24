defmodule Fount.Query do
  @moduledoc "Headless screenplay query API."

  alias Fount.Source.Span

  def node(%{index: index}, id), do: Map.get(index.by_id, id)
  def scene(%{index: index}, id), do: Map.get(index.scenes_by_id, id)
  def dialogue_block(%{index: index}, id), do: Map.get(index.dialogue_blocks_by_id, id)
  def scenes(%{ir: ir}), do: ir.scenes
  def dialogue_blocks(%{ir: ir}), do: ir.dialogue_blocks
  def outline(%{ir: ir}), do: ir.outline
  def elements(%{ir: ir}), do: ir.elements

  def node_at(%{ir: ir}, byte_offset) when is_integer(byte_offset) and byte_offset >= 0 do
    Enum.find(ir.elements, fn element ->
      case element.source_span do
        nil -> false
        span -> Span.contains?(span, byte_offset)
      end
    end)
  end

  def nodes_in_span(%{ir: ir}, %Span{} = span) do
    Enum.filter(ir.elements, fn element ->
      case element.source_span do
        nil -> false
        element_span -> Span.overlaps?(element_span, span)
      end
    end)
  end

  def scene_for(%{index: index} = doc, element_id) do
    with scene_id when not is_nil(scene_id) <- Map.get(index.scene_for_element, element_id) do
      scene(doc, scene_id)
    end
  end

  def character_cues(%{index: index}, name) do
    key = Fount.Index.normalize_character(name)
    Enum.map(Map.get(index.character_cues, key, []), &Map.get(index.by_id, &1))
  end

  def characters(%Fount.Screenplay{cast: cast}), do: cast |> Map.values() |> Enum.sort_by(&{&1.display_name, &1.id})

  def characters(%{index: index}) do
    index.character_cues
    |> Enum.map(fn {name, ids} -> %{name: name, cue_ids: ids, cue_count: length(ids)} end)
    |> Enum.sort_by(&{-&1.cue_count, &1.name})
  end

  def search_text(%{ir: ir}, needle, opts \\ []) when is_binary(needle) do
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

  def scenes(subject, opts),
    do: Enum.filter(scenes(subject), &(Keyword.get(opts, :include_omitted, false) or !&1.omitted?))

  def elements(%{index: index}, type) when is_atom(type), do: Map.get(index.by_type, type, [])

  def elements(subject, opts) when is_list(opts) do
    omitted = MapSet.new(for s <- subject.ir.scenes, s.omitted?, id <- s.element_ids, do: id)
    Enum.filter(elements(subject), &(Keyword.get(opts, :include_omitted, false) or !MapSet.member?(omitted, &1.id)))
  end

  def dialogue_blocks(subject, opts),
    do:
      Enum.filter(dialogue_blocks(subject), fn b ->
        s = scene_for(subject, b.cue_id)
        Keyword.get(opts, :include_omitted, false) or is_nil(s) or !s.omitted?
      end)

  def scene_elements(subject, id) do
    case scene(subject, id) do
      nil -> {:error, :unknown_scene}
      s -> {:ok, Enum.map(s.element_ids, &node(subject, &1))}
    end
  end

  def scene_dialogue_blocks(subject, id) do
    with {:ok, elements} <- scene_elements(subject, id) do
      ids = MapSet.new(Enum.map(elements, & &1.id))
      {:ok, Enum.filter(dialogue_blocks(subject), &MapSet.member?(ids, &1.cue_id))}
    end
  end

  def block_for(subject, id), do: Enum.find(dialogue_blocks(subject), &(id == &1.cue_id or id in &1.body_ids))
  def elements_between(subject, first, last), do: between(elements(subject), first, last)
  def scenes_between(subject, first, last), do: between(scenes(subject), first, last)
  def character(%Fount.Screenplay{cast: cast}, id), do: cast[id]

  def character_mentions(model, id, opts \\ []),
    do:
      model.mentions
      |> Map.values()
      |> Enum.filter(
        &(&1.character_id == id and (Keyword.get(opts, :include_candidates, false) or &1.status == :confirmed))
      )
      |> Enum.sort_by(&{Enum.find_index(model.ir.elements, fn e -> e.id == &1.element_id end), &1.byte_start})

  def character_dialogue(model, id) do
    cues = MapSet.new(for m <- character_mentions(model, id), m.role == :speaker_cue, do: m.element_id)
    Enum.filter(dialogue_blocks(model), &MapSet.member?(cues, &1.cue_id))
  end

  def scenes_with_character(model, id, opts \\ []) do
    element_ids =
      case Keyword.get(opts, :role, :speaker) do
        :speaker -> Enum.map(character_dialogue(model, id), & &1.cue_id)
        :mention -> Enum.map(character_mentions(model, id), & &1.element_id)
        :declared_present -> []
      end

    wanted = element_ids |> Enum.map(&scene_for(model, &1)) |> Enum.reject(&is_nil/1) |> Enum.map(& &1.id)
    Enum.filter(scenes(model, opts), &(&1.id in wanted))
  end

  def authored_items(model, kind, opts \\ []),
    do:
      model.authored_items
      |> Map.values()
      |> Enum.filter(
        &(&1["kind"] == to_string(kind) and
            (is_nil(Keyword.get(opts, :status)) or &1["status"] == to_string(opts[:status])))
      )
      |> Enum.sort_by(& &1["id"])

  def location_groups(subject), do: Enum.group_by(scenes(subject), fn scene -> node(subject, scene.heading_id).text end)

  def swimlanes(model),
    do: Enum.map(characters(model), fn c -> %{character: c, scenes: scenes_with_character(model, c.id)} end)

  defp between(list, first, last) do
    a = Enum.find_index(list, &(&1.id == first))
    b = Enum.find_index(list, &(&1.id == last))
    if is_integer(a) and is_integer(b) and a <= b, do: {:ok, Enum.slice(list, a..b)}, else: {:error, :invalid_range}
  end
end
