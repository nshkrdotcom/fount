defmodule Fount.Analyzers.CharacterEntities do
  @moduledoc "Cue-to-entity resolver with explicit alias groups; makes no speculative alias merges."
  @behaviour Fount.Analyzer

  alias Fount.Annotation
  alias Fount.Annotation.{Provenance, Target}

  @impl true
  def analyze(doc, opts) do
    alias_groups = Keyword.get(opts, :aliases, %{})

    cues = Fount.Query.elements(doc, :character)

    groups =
      Enum.group_by(cues, fn cue ->
        normalized = Fount.Index.normalize_character(cue.text)
        canonical_for(normalized, alias_groups)
      end)

    annotations =
      Enum.flat_map(groups, fn {canonical, group} ->
        entity_id = Fount.ID.v5(doc.id, ["entity:character:", canonical])
        cue_ids = Enum.map(group, & &1.id)
        aliases = group |> Enum.map(&Fount.Index.normalize_character(&1.text)) |> Enum.uniq() |> Enum.sort()

        entity = %Annotation{
          id: Fount.ID.v5(doc.id, ["annotation:character-entity:", canonical]),
          namespace: "fount.semantics",
          kind: :character_entity,
          target: %Target{node_id: hd(cue_ids)},
          value: %{entity_id: entity_id, canonical_name: canonical, aliases: aliases, cue_ids: cue_ids},
          confidence: 1.0,
          dependencies: cue_ids,
          provenance: provenance(doc)
        }

        mentions =
          Enum.map(group, fn cue ->
            %Annotation{
              id: Fount.ID.v5(doc.id, ["annotation:character-mention:", cue.id]),
              namespace: "fount.semantics",
              kind: :character_mention,
              target: %Target{node_id: cue.id, span: cue.source_span},
              value: %{entity_id: entity_id, text: cue.text, role: "speaker_cue"},
              confidence: 1.0,
              dependencies: [cue.id],
              provenance: provenance(doc)
            }
          end)

        [entity | mentions]
      end)

    {:ok, annotations}
  end

  defp canonical_for(name, groups) do
    Enum.find_value(groups, name, fn {canonical, aliases} ->
      normalized_aliases = Enum.map(List.wrap(aliases), &Fount.Index.normalize_character/1)

      if name == Fount.Index.normalize_character(to_string(canonical)) or name in normalized_aliases,
        do: Fount.Index.normalize_character(to_string(canonical))
    end)
  end

  defp provenance(doc) do
    %Provenance{
      producer: __MODULE__ |> Module.split() |> Enum.join("."),
      producer_version: Fount.version(),
      source_revision: doc.revision.id,
      created_at: DateTime.utc_now()
    }
  end
end
