defmodule FountWeb.ScreenplayIndex do
  @moduledoc "Provider-free projections of Fount's deterministic screenplay analyzers."

  alias Fount.Analyzers.{Characters, Dialogue, Locations}
  alias Fount.Query

  @reading_words_per_minute 180
  @screenplay_words_per_page 250

  def build(screenplay, opts \\ []) do
    scenes = scene_index(screenplay)

    %{
      scenes: scenes,
      characters: character_index(screenplay, Keyword.get(opts, :character_filter)),
      dialogue: dialogue_index(screenplay),
      locations: location_index(screenplay, scenes),
      estimates: estimates(screenplay)
    }
  end

  def scene_index(screenplay) do
    location_values = analyzer_values(Locations, screenplay, & &1.target.node_id)

    screenplay.ir.scenes
    |> List.wrap()
    |> Enum.with_index(1)
    |> Enum.map(fn {scene, ordinal} ->
      heading = Query.node(screenplay, scene.heading_id)
      parsed = Map.get(location_values, scene.heading_id, %{})

      %{
        id: scene.id,
        ordinal: ordinal,
        number: scene.number,
        heading_id: scene.heading_id,
        heading: heading && heading.text,
        location: empty_to_nil(parsed[:location]),
        time: parsed[:time],
        omitted?: scene.omitted?
      }
    end)
  end

  def character_index(screenplay, filter \\ nil) do
    filter = normalize_filter(filter)

    Characters
    |> analyzer_annotations(screenplay)
    |> Enum.map(fn annotation ->
      value = annotation.value
      cue_ids = annotation.dependencies || []

      scene_ids =
        cue_ids
        |> Enum.map(&Query.scene_for(screenplay, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.id)
        |> Enum.uniq()

      blocks =
        screenplay.ir.dialogue_blocks
        |> List.wrap()
        |> Enum.filter(&(&1.cue_id in cue_ids))

      %{
        name: value.name,
        cue_ids: cue_ids,
        cue_count: value.cue_count,
        scene_ids: scene_ids,
        scene_count: length(scene_ids),
        dialogue_block_ids: Enum.map(blocks, & &1.id),
        dialogue_block_count: length(blocks),
        analyzer_kind: annotation.kind,
        identity_note:
          "Literal cue summary from Fount.Analyzers.Characters; repeated cue spelling does not prove a cast entity relationship."
      }
    end)
    |> Enum.filter(fn character ->
      is_nil(filter) or String.contains?(String.downcase(character.name), filter)
    end)
    |> Enum.sort_by(&{-&1.cue_count, &1.name})
  end

  def dialogue_index(screenplay) do
    Dialogue
    |> analyzer_annotations(screenplay)
    |> Enum.map(fn annotation ->
      block = Query.block_for(screenplay, annotation.target.node_id)
      scene = Query.scene_for(screenplay, annotation.target.node_id)

      annotation.value
      |> Map.merge(%{
        id: block && block.id,
        cue_id: annotation.target.node_id,
        scene_id: scene && scene.id,
        body_ids: if(block, do: block.body_ids, else: []),
        analyzer_kind: annotation.kind
      })
    end)
  end

  def location_index(screenplay, scenes \\ nil) do
    scenes = scenes || scene_index(screenplay)
    scene_by_heading = Map.new(scenes, &{&1.heading_id, &1})

    Locations
    |> analyzer_annotations(screenplay)
    |> Enum.map(fn annotation ->
      scene = scene_by_heading[annotation.target.node_id]

      %{
        scene_id: scene && scene.id,
        heading_id: annotation.target.node_id,
        raw: annotation.value.raw,
        context: annotation.value.context,
        location: empty_to_nil(annotation.value.location) || "Unknown / unparsed",
        time: annotation.value.time,
        analyzer_kind: annotation.kind
      }
    end)
    |> Enum.group_by(& &1.location)
    |> Enum.map(fn {location, entries} ->
      %{
        location: location,
        scene_ids: entries |> Enum.map(& &1.scene_id) |> Enum.reject(&is_nil/1),
        scene_count: length(entries),
        entries: entries
      }
    end)
    |> Enum.sort_by(&{-&1.scene_count, &1.location})
  end

  @doc "Precise provider-free screenplay facts for the selected screenplay source."
  def facts(screenplay) do
    scenes = scene_index(screenplay)
    literal_characters = character_index(screenplay)

    confirmed_cast =
      screenplay.cast
      |> Map.values()
      |> Enum.map(fn character ->
        speaking_scenes = Query.scenes_with_character(screenplay, character.id)
        mentions = Query.character_mentions(screenplay, character.id)

        %{
          id: character.id,
          name: character.display_name,
          scene_count: length(speaking_scenes),
          cue_count: Enum.count(mentions, &(&1.role == :speaker_cue and &1.status == :confirmed))
        }
      end)
      |> Enum.sort_by(&{&1.name, &1.id})

    all_words =
      screenplay.ir.elements
      |> List.wrap()
      |> Enum.map_join(" ", &(&1.text || ""))
      |> word_count()

    dialogue_words =
      screenplay.ir.dialogue_blocks
      |> List.wrap()
      |> Enum.flat_map(&List.wrap(&1.body_ids))
      |> Enum.map(&Query.node(screenplay, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(" ", &(&1.text || ""))
      |> word_count()

    heading_counts =
      Enum.reduce(scenes, %{interior: 0, exterior: 0, other: 0, unknown: 0}, fn scene, acc ->
        Map.update!(acc, heading_context(scene.heading), &(&1 + 1))
      end)

    %{
      scene_count: length(scenes),
      confirmed_cast_count: length(confirmed_cast),
      confirmed_cast: confirmed_cast,
      literal_cue_group_count: length(literal_characters),
      literal_character_cues:
        Enum.map(literal_characters, &Map.take(&1, [:name, :scene_count, :cue_count])),
      heading_contexts: heading_counts,
      time_of_day_unknown_count: Enum.count(scenes, &blank?(&1.time)),
      dialogue_words: dialogue_words,
      screenplay_element_words: all_words,
      dialogue_word_share:
        if(all_words > 0, do: Float.round(dialogue_words * 100 / all_words, 1), else: nil),
      definitions: %{
        confirmed_cast:
          "Canonical screenplay cast identities only. A literal cue is not counted here until explicitly promoted or author-created.",
        literal_character_cues:
          "Literal parsed character-cue spellings in the selected source. Repeated spelling does not prove a person identity.",
        speaking_scenes: "Distinct scenes containing a confirmed literal cue for that character.",
        dialogue_word_share:
          "Dialogue-body words divided by words across all screenplay elements in this selected source.",
        heading_contexts:
          "Scene headings classified from their literal INT./EXT. prefix; mixed or unrecognized headings are Other/Unknown.",
        time_of_day_unknown:
          "Scene headings for which the existing location analyzer did not return a time value."
      }
    }
  end

  defp heading_context(heading) when is_binary(heading) do
    heading = heading |> String.trim() |> String.upcase()

    cond do
      heading == "" -> :unknown
      String.starts_with?(heading, ["INT./EXT.", "INT/EXT.", "I/E.", "I./E."]) -> :other
      String.starts_with?(heading, ["INT.", "INT "]) -> :interior
      String.starts_with?(heading, ["EXT.", "EXT "]) -> :exterior
      true -> :other
    end
  end

  defp heading_context(_), do: :unknown
  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  def estimates(screenplay) do
    elements = screenplay.ir.elements

    cond do
      is_nil(elements) ->
        %{
          pages: %{value: nil, label: "unknown — screenplay elements unavailable"},
          duration: %{value: nil, label: "unknown — screenplay elements unavailable"}
        }

      elements == [] ->
        %{
          pages: %{value: 0, label: "0 pages — derived reading approximation"},
          duration: %{value: 0, label: "0 minutes — derived reading approximation"}
        }

      true ->
        words = elements |> Enum.map_join(" ", &(&1.text || "")) |> word_count()
        pages = Float.round(words / @screenplay_words_per_page, 1)
        minutes = Float.round(words / @reading_words_per_minute, 1)

        %{
          pages: %{value: pages, label: "#{pages} pages — derived reading approximation"},
          duration: %{value: minutes, label: "#{minutes} minutes — derived reading approximation"}
        }
    end
  end

  defp analyzer_annotations(module, screenplay) do
    subject = %{
      id: screenplay.id,
      revision: screenplay.revision,
      ir: screenplay.ir,
      index: screenplay.index
    }

    case module.analyze(subject, []) do
      {:ok, annotations} -> annotations
      _ -> []
    end
  end

  defp analyzer_values(module, screenplay, key_fun) do
    module
    |> analyzer_annotations(screenplay)
    |> Map.new(fn annotation -> {key_fun.(annotation), annotation.value} end)
  end

  defp word_count(text), do: text |> String.split(~r/\s+/u, trim: true) |> length()

  defp normalize_filter(value) when is_binary(value) do
    value = value |> String.trim() |> String.downcase()
    if value == "", do: nil, else: value
  end

  defp normalize_filter(_), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
