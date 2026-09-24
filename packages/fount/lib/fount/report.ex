defmodule Fount.Report do
  @moduledoc "Useful headless screenplay reports derived from canonical IR."

  alias Fount.Document

  @spec summary(Document.t()) :: map()
  def summary(%Document{} = doc) do
    dialogue_elements = Fount.Query.elements(doc, :dialogue)
    action_elements = Fount.Query.elements(doc, :action)

    %{
      scenes: length(doc.ir.scenes),
      elements: length(doc.ir.elements),
      dialogue_turns: length(doc.ir.dialogue_blocks),
      characters: Fount.Query.characters(doc),
      dialogue_words: sum_words(dialogue_elements),
      action_words: sum_words(action_elements),
      notes: length(Fount.Query.elements(doc, :note)),
      sections: length(Fount.Query.elements(doc, :section))
    }
  end

  @spec scenes(Document.t()) :: [map()]
  def scenes(%Document{} = doc) do
    Enum.map(doc.ir.scenes, fn scene ->
      elements = Enum.map(scene.element_ids, &Fount.Query.node(doc, &1)) |> Enum.reject(&is_nil/1)
      heading = Fount.Query.node(doc, scene.heading_id)
      cues = elements |> Enum.filter(&(&1.type == :character)) |> Enum.map(&Fount.Index.normalize_character(&1.text))

      %{
        id: scene.id,
        number: scene.number,
        heading: heading && heading.text,
        heading_parts: if(heading, do: Fount.SceneHeading.parse(heading.text), else: nil),
        characters: Enum.uniq(cues),
        action_words: elements |> Enum.filter(&(&1.type == :action)) |> sum_words(),
        dialogue_words: elements |> Enum.filter(&(&1.type == :dialogue)) |> sum_words(),
        element_ids: scene.element_ids
      }
    end)
  end

  @spec dialogue(Document.t()) :: [map()]
  def dialogue(%Document{} = doc) do
    Enum.with_index(doc.ir.dialogue_blocks, 1)
    |> Enum.map(fn {block, ordinal} ->
      cue = Fount.Query.node(doc, block.cue_id)
      body = Enum.map(block.body_ids, &Fount.Query.node(doc, &1)) |> Enum.reject(&is_nil/1)
      lines = body |> Enum.filter(&(&1.type == :dialogue)) |> Enum.map(& &1.text)
      parentheticals = body |> Enum.filter(&(&1.type == :parenthetical)) |> Enum.map(& &1.text)

      %{
        id: block.id,
        ordinal: ordinal,
        character: cue && cue.text,
        extension: cue && Map.get(cue.attrs || %{}, :extension),
        dialogue: Enum.join(lines, "\n"),
        parentheticals: parentheticals,
        words: lines |> Enum.join(" ") |> word_count(),
        dual_with: block.dual_with,
        side: block.side,
        scene_id: Map.get(doc.index.scene_for_element, block.cue_id)
      }
    end)
  end

  @spec locations(Document.t()) :: [map()]
  def locations(%Document{} = doc) do
    scenes(doc)
    |> Enum.group_by(fn scene -> get_in(scene, [:heading_parts, :location]) || "" end)
    |> Enum.reject(fn {location, _} -> location == "" end)
    |> Enum.map(fn {location, scenes} ->
      %{
        location: location,
        scene_count: length(scenes),
        scene_ids: Enum.map(scenes, & &1.id),
        times: scenes |> Enum.map(&get_in(&1, [:heading_parts, :time])) |> Enum.reject(&is_nil/1) |> Enum.frequencies()
      }
    end)
    |> Enum.sort_by(&{-&1.scene_count, &1.location})
  end

  defp sum_words(elements), do: elements |> Enum.map(& &1.text) |> Enum.join(" ") |> word_count()
  defp word_count(text), do: text |> String.split(~r/\s+/u, trim: true) |> length()
end
