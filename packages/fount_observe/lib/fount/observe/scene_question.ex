defmodule Fount.Observe.SceneQuestion do
  @moduledoc """
  Ask a concrete scene question and inspect the source passages supplied for the
  answer. A measurement is not coverage, a dramatic verdict or permission to edit.
  This small Phase 2 surface uses the same public Observe execution path as agents.
  """
  alias Fount.Observe.{Error, EvidenceRef, Projection, Provider}

  def ask(provider, model, target, questions, opts \\ []) do
    projection = Keyword.get(opts, :projection, "page_reader")
    projection_opts = Keyword.get(opts, :projection_opts, [])
    execution_opts = Keyword.drop(opts, [:projection, :projection_opts])
    with {:ok, point} <- Projection.resolve_point(model, target),
         {:ok, request} <- Projection.request(model, "scene_question", point, projection, projection_opts),
         {:ok, batch} <- Fount.Observe.evaluate(provider, [request], questions, execution_opts) do
      simulation = match?(%Provider{sensor_id: "sandbox"}, provider)
      prompts = Map.new(batch.measurement_spec["questions"], &{&1["key"], &1["instructions"]})
      findings = for entry <- batch.entries, observation <- entry.observations do
        %{"question" => prompts[observation.kind], "question_key" => observation.kind,
          "claim_class" => "model_estimated_interpretation", "simulation" => simulation,
          "value" => observation.result.value, "calibration" => observation.result.calibration,
          "evidence" => Enum.map(observation.evidence, &EvidenceRef.to_map/1),
          "measurement_id" => observation.result.id, "observation_id" => observation.id,
          "provider_fingerprint" => observation.result.provider_fingerprint,
          "cache_hit" => entry.cache_hit?}
      end
      {:ok, %{"status" => if(findings == [], do: "unavailable", else: "available"),
        "source_revision" => model.revision.id, "scope" => target, "projection" => projection,
        "findings" => findings, "errors" => Enum.map(batch.errors, &Error.to_map/1),
        "resource_usage" => batch.resource_usage, "strategies" => [],
        "limitations" => ["The passages are verified inputs, not proof of the model's reasoning.",
          "No dramatic verdict, human-calibrated response prediction, or canonical edit is made."] ++
          if(simulation, do: ["Fixed synthetic fixture answers test the workflow, not creative usefulness."], else: [])}}
    end
  end
end
