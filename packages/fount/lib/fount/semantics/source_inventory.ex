defmodule Fount.Semantics.SourceInventory do
  @moduledoc """
  Provider-free source facts for one exact screenplay revision.

  Literal cues and headings are occurrences, not confirmed people or production
  locations. Canonical cast identity is reported separately so an imported cue
  can never become an identity merely because the parser recognized Fountain
  syntax.
  """

  alias Fount.Query
  alias Fount.SceneHeading
  alias Fount.Screenplay
  alias Fount.Source.Span

  @schema_version "source_inventory_v1"

  @spec build(Screenplay.t()) :: map()
  def build(%Screenplay{} = screenplay) do
    scenes = screenplay.ir.scenes |> Enum.with_index(1) |> Map.new(fn {scene, n} -> {scene.id, n} end)

    cues =
      screenplay
      |> Query.elements(:character)
      |> Enum.map(&cue(screenplay, &1, scenes))

    headings =
      screenplay
      |> Query.elements(:scene_heading)
      |> Enum.map(&heading(screenplay, &1, scenes))

    %{
      schema_version: @schema_version,
      parser_version: Fount.version(),
      screenplay_id: screenplay.id,
      revision_id: screenplay.revision.id,
      character_cues: cues,
      scene_headings: headings,
      canonical_cast: canonical_cast(screenplay),
      counts: %{
        literal_character_cues: length(cues),
        literal_scene_headings: length(headings),
        canonical_cast: map_size(screenplay.cast)
      }
    }
  end

  def schema_version, do: @schema_version

  defp cue(screenplay, element, scenes) do
    scene = Query.scene_for(screenplay, element.id)
    block = Query.block_for(screenplay, element.id)

    %{
      local_id: "character:" <> element.id,
      kind: "character",
      occurrence_role: "speaker",
      element_id: element.id,
      dialogue_block_id: block && block.id,
      literal: element.text,
      raw: element.raw_text,
      extension: get_in(element.attrs || %{}, [:extension]),
      forced: Map.get(element.attrs || %{}, :forced?, false),
      dual: Map.get(element.attrs || %{}, :dual?, false),
      scene_id: scene && scene.id,
      scene_ordinal: scene && scenes[scene.id],
      source_span: plain_span(element.source_span),
      content_span: plain_span(element.content_span),
      evidence: evidence(element)
    }
  end

  defp heading(screenplay, element, scenes) do
    scene = Query.scene_for(screenplay, element.id)
    parts = SceneHeading.parse(element.text)

    %{
      local_id: "location:" <> element.id,
      kind: "location",
      occurrence_role: "location_heading",
      element_id: element.id,
      literal: element.text,
      raw: element.raw_text,
      scene_id: scene && scene.id,
      scene_ordinal: scene && scenes[scene.id],
      source_span: plain_span(element.source_span),
      content_span: plain_span(element.content_span),
      parts: parts,
      evidence: evidence(element)
    }
  end

  defp evidence(element) do
    %{
      element_id: element.id,
      quote: element.text,
      byte_start: element.content_span && element.content_span.byte_start,
      byte_end: element.content_span && element.content_span.byte_end
    }
  end

  defp canonical_cast(screenplay) do
    screenplay.cast
    |> Map.values()
    |> Enum.map(fn character ->
      mentions = Query.character_mentions(screenplay, character.id, include_candidates: true)
      imported = Enum.filter(mentions, &(&1.producer == "writer.import"))
      authored = Enum.filter(mentions, &(&1.producer == "writer"))

      origin =
        cond do
          authored != [] -> "author_confirmed"
          imported != [] and length(imported) == length(mentions) -> "legacy_literal"
          imported != [] -> "mixed_legacy"
          true -> "author_created"
        end

      %{
        core_character_id: character.id,
        display_name: character.display_name,
        aliases: Enum.map(character.aliases || [], &Map.take(&1, [:alias, :kind])),
        origin: origin,
        review_state: if(origin == "legacy_literal", do: "unreviewed", else: "confirmed"),
        cue_element_ids:
          mentions
          |> Enum.filter(&(&1.role == :speaker_cue and &1.status == :confirmed))
          |> Enum.map(& &1.element_id)
          |> Enum.uniq()
      }
    end)
    |> Enum.sort_by(&{&1.display_name, &1.core_character_id})
  end

  defp plain_span(nil), do: nil

  defp plain_span(%Span{} = span) do
    span
    |> Map.from_struct()
    |> Map.drop([:__struct__])
  end
end
