defmodule Fount.Analyzers.Dialogue do
  @moduledoc "Deterministic dialogue-turn metrics built from dialogue blocks."
  alias Fount.Annotation
  alias Fount.Annotation.Provenance
  alias Fount.Annotation.Target
  @behaviour Fount.Analyzer

  @impl true
  def analyze(doc, _opts) do
    annotations =
      Enum.map(doc.ir.dialogue_blocks, fn block ->
        cue = Fount.Query.node(doc, block.cue_id)
        body = Enum.map(block.body_ids, &Fount.Query.node(doc, &1))
        dialogue = body |> Enum.filter(&(&1.type == :dialogue)) |> Enum.map_join("\n", & &1.text)

        value = %{
          character: cue && cue.text,
          words: word_count(dialogue),
          characters: String.length(dialogue),
          parentheticals: Enum.count(body, &(&1.type == :parenthetical)),
          dual?: not is_nil(block.dual_with),
          side: if(block.side, do: to_string(block.side), else: nil)
        }

        %Annotation{
          id: Fount.ID.v5(doc.id, ["analysis:dialogue:", block.id]),
          namespace: "fount.core",
          kind: :dialogue_turn_metrics,
          target: %Target{node_id: block.cue_id, span: block.source_span},
          value: value,
          confidence: 1.0,
          dependencies: [block.cue_id | block.body_ids],
          provenance: provenance(doc)
        }
      end)

    {:ok, annotations}
  end

  defp word_count(text), do: text |> String.split(~r/\s+/u, trim: true) |> length()

  defp provenance(doc) do
    %Provenance{
      producer: __MODULE__ |> Module.split() |> Enum.join("."),
      producer_version: Fount.version(),
      source_revision: doc.revision.id,
      created_at: DateTime.utc_now()
    }
  end
end
