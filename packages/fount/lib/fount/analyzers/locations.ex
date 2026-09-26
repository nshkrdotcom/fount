defmodule Fount.Analyzers.Locations do
  @moduledoc "Scene-heading location/time decomposition with source provenance."
  alias Fount.Annotation
  alias Fount.Annotation.Provenance
  alias Fount.Annotation.Target
  @behaviour Fount.Analyzer

  @impl true
  def analyze(doc, opts) do
    annotations =
      doc
      |> Fount.Query.elements(:scene_heading)
      |> Enum.map(fn element ->
        value = Fount.SceneHeading.parse(element.text, opts)

        %Annotation{
          id: Fount.ID.v5(doc.id, ["analysis:scene-heading:", element.id]),
          namespace: "fount.core",
          kind: :scene_heading_parts,
          target: %Target{node_id: element.id, span: element.source_span},
          value: value,
          confidence: 1.0,
          dependencies: [element.id],
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
