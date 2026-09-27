defmodule Fount.Intelligence.TestSupport.StoryWorldFixture do
  @moduledoc false

  alias Fount.Observe.{Distribution, EvidenceRef, MeasurementResult, Observation, TargetRef}
  alias Fount.Screenplay

  def screenplay do
    Screenplay.new(
      id: "2e0c716b-93b4-50fb-96e4-588fdb11a2a0",
      scenes: [
        %{
          heading: "INT. SERVICE CORRIDOR - NIGHT",
          elements: [%{type: :action, text: "Mara pockets the brass key."}]
        },
        %{
          heading: "INT. SERVICE CORRIDOR - YEARS EARLIER",
          elements: [%{type: :action, text: "Mara sees the key behind glass."}]
        },
        %{
          heading: "EXT. LOADING DOCK - DAWN",
          elements: [%{type: :action, text: "Mara drops the key beside Dan."}]
        }
      ]
    )
  end

  def frozen_observation(screenplay) do
    element = Enum.find(screenplay.ir.elements, &(&1.type == :action))

    target = %TargetRef{
      screenplay_id: screenplay.id,
      revision_id: screenplay.revision.id,
      kind: "element",
      id: element.id
    }

    evidence = %EvidenceRef{
      id: "evidence-frozen-1",
      screenplay_id: screenplay.id,
      revision_id: screenplay.revision.id,
      target: target,
      excerpt: element.text,
      excerpt_sha256: Fount.ID.hash(element.text),
      role: "input_context"
    }

    result = %MeasurementResult{
      id: "measurement-frozen-1",
      value: %{"visible" => true},
      distribution: %Distribution{kind: :noul, values: [{"true", 0.9}, {"false", 0.1}]},
      output_contract_id: "fixture.visibility",
      output_contract_sha256: "fixture-contract-sha",
      measurement_spec_sha256: "fixture-spec-sha",
      input_sha256: "fixture-input-sha",
      provider_fingerprint: %{"provider" => "fixture", "model" => "frozen"},
      semantic_execution_sha256: "fixture-execution-sha"
    }

    %Observation{
      id: "observation-frozen-1",
      kind: "fixture.visibility",
      target: target,
      result: result,
      sensor_id: "fixture",
      evidence: [evidence],
      metadata: %{}
    }
  end

  def scene_events(screenplay), do: Enum.map(screenplay.ir.scenes, &("scene:" <> &1.id))

  def scene_evidence(screenplay, index) do
    scene = Enum.at(screenplay.ir.scenes, index)
    element_id = scene.element_ids |> Enum.at(1)
    %{"element_id" => element_id}
  end

  def record(record_type, id, screenplay, scene_index, extra \\ %{}) do
    %{
      "record_type" => record_type,
      "id" => id,
      "evidence" => [scene_evidence(screenplay, scene_index)]
    }
    |> Map.merge(extra)
  end
end
