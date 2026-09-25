defmodule FountProbe.KnowledgeRevealTest do
  use ExUnit.Case, async: true

  test "compares first supported point with an intended reveal only when the curve is complete" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara finds the key."},
              %{type: :action, text: "Dan opens the box."}
            ]
          }
        ]
      )

    [scene] = model.ir.scenes
    {:ok, [entry, first, second]} = FountProbe.Projection.points(model, scene.id)

    curves = %{
      "reader" => %{
        "status" => "complete",
        "first_crossing" => first,
        "curve" => [%{"point" => entry}, %{"point" => first}, %{"point" => second}]
      },
      "audience" => %{"status" => "incomplete", "first_crossing" => nil, "curve" => []}
    }

    result = FountProbe.KnowledgeTrace.assess_reveal(model, curves, second)
    assert result["reader"]["status"] == "observed_before_intended"
    assert result["audience"]["status"] == "unknown"

    assert FountProbe.KnowledgeTrace.assess_reveal(model, curves, first)["reader"]["status"] ==
             "at_intended"
  end

  test "unknown behavior IDs are rejected before running a probe" do
    model =
      Fount.Screenplay.new(
        scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Mara stops."}]}]
      )

    [scene] = model.ir.scenes
    {:ok, points} = FountProbe.Projection.points(model, scene.id)

    params = %{
      "proposition" => "Mara knows",
      "subjects" => [%{"kind" => "reader"}],
      "points" => [List.last(points)],
      "behavior_element_ids" => [Fount.ID.v4()]
    }

    assert {:error, :unknown_behavior_element} =
             FountProbe.Catalog.validate(model, "knowledge_trace", params)
  end
end
