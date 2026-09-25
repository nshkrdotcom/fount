defmodule FountProbe.SameSceneDependenciesTest do
  use ExUnit.Case, async: true

  test "an evidenced setup can precede a use within the same scene" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. SHED - DAY",
            elements: [
              %{type: :action, text: "Mara places a brass key under the mat."},
              %{type: :action, text: "Dan finds the key and unlocks the gate."}
            ]
          }
        ]
      )

    assert {:ok, units} = FountProbe.Projection.select(model, %{"whole_screenplay" => true})
    [setup, use] = Enum.filter(units, &(&1["type"] == "action"))
    [scene] = model.ir.scenes

    records = [
      %{"id" => "setup", "scene_id" => scene.id, "evidence_ids" => [setup["evidence_id"]]},
      %{"id" => "use", "scene_id" => scene.id, "evidence_ids" => [use["evidence_id"]]}
    ]

    assert [{first, second}] =
             FountProbe.Dependencies.ordered_pairs(model, records, units, ["use"])

    assert first["id"] == "setup"
    assert second["id"] == "use"
    assert [] == FountProbe.Dependencies.ordered_pairs(model, records, units, ["setup"])
  end
end
