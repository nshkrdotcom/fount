defmodule FountProbe.ChangedContinuityTest do
  use ExUnit.Case, async: true

  test "changed targets select transitions for affected subjects at and after the change" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara puts the key down."},
              %{type: :action, text: "Dan takes the key."},
              %{type: :action, text: "Dan leaves with the key."}
            ]
          }
        ]
      )

    {:ok, units} = FountProbe.Projection.select(model, %{"whole_screenplay" => true})
    [first, middle, last] = Enum.filter(units, &(&1["type"] == "action"))

    record = fn id, unit, subject ->
      %{
        "id" => id,
        "scene_id" => unit["scene_id"],
        "subjects" => [subject],
        "evidence_ids" => [unit["evidence_id"]]
      }
    end

    a = record.("a", first, "key")
    b = record.("b", middle, "key")
    c = record.("c", last, "key")

    pairs = [
      {"key", a, b},
      {"key", b, c},
      {"unrelated", record.("u1", first, "unrelated"), record.("u2", last, "unrelated")}
    ]

    target = %{"kind" => "element", "id" => middle["target"]["id"]}

    {affected, coverage} =
      FountProbe.Continuity.affected_pairs(model, pairs, [a, b, c], units, [target])

    assert Enum.map(affected, fn {_, x, y} -> {x["id"], y["id"]} end) == [{"a", "b"}, {"b", "c"}]
    assert coverage["unmatched_changed_targets"] == []
  end
end
