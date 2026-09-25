defmodule FountProbe.RetrievalExactContinuationTest do
  use ExUnit.Case, async: true

  test "inspect_all scans all eligible source but only returns literal matches" do
    m =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. OFFICE - DAY",
            elements: [
              %{type: :action, text: "The key falls."},
              %{type: :action, text: "Mara waits."}
            ]
          }
        ]
      )

    assert {:ok, r} =
             FountProbe.run(
               m,
               "search",
               %{"query" => "key", "exact_phrase" => true, "mode" => "inspect_all"},
               %{}
             )

    assert r.data["matching_count"] == 1
    assert Enum.all?(r.data["hits"], &String.contains?(&1["text"], "key"))
  end

  test "search filters validate identities, types, and flags before querying" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{heading: "INT. OFFICE - DAY", elements: [%{type: :action, text: "The key falls."}]},
          %{heading: "EXT. DOCK - NIGHT", elements: [%{type: :action, text: "The key floats."}]}
        ]
      )

    [office, _] = model.ir.scenes
    base = %{"query" => "key", "exact_phrase" => true}

    assert {:ok, report} =
             FountProbe.run(
               model,
               "search",
               Map.put(base, "filters", %{
                 "scene_ids" => [office.id],
                 "element_types" => ["action"]
               }),
               %{}
             )

    assert report.data["matching_count"] == 1

    for filters <- [
          %{"scene_ids" => [Fount.ID.v4()]},
          %{"character_ids" => [Fount.ID.v4()]},
          %{"element_types" => ["screenplay"]},
          %{"include_notes" => "yes"},
          %{"location" => " "}
        ] do
      assert {:error, _} = FountProbe.run(model, "search", Map.put(base, "filters", filters), %{})
    end
  end
end
