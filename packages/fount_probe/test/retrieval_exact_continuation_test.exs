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
end
