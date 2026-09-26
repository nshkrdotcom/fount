defmodule Fount.Analyzers.Characters do
  @moduledoc "Deterministic cue-based character index. Entity resolution remains a separate annotation problem."
  alias Fount.Annotation
  alias Fount.Annotation.Provenance
  alias Fount.Annotation.Target
  @behaviour Fount.Analyzer

  @impl true
  def analyze(doc, _opts) do
    annotations =
      doc
      |> Fount.Query.characters()
      |> Enum.map(fn character ->
        %Annotation{
          id: Fount.ID.v5(doc.id, ["analysis:character:", character.name]),
          namespace: "fount.core",
          kind: :character_cue_summary,
          target: %Target{node_id: hd(character.cue_ids)},
          value: character,
          confidence: 1.0,
          dependencies: character.cue_ids,
          provenance: provenance(doc)
        }
      end)

    {:ok, annotations}
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
