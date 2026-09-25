defmodule FountProbe.SceneCountScopeTest do
  use ExUnit.Case, async: true

  test "scene count follows the replaced selection instead of deleted scene IDs" do
    base =
      Fount.Screenplay.new(
        scenes: [
          %{heading: "INT. FIRST - DAY", elements: [%{type: :action, text: "One."}]},
          %{heading: "INT. SECOND - DAY", elements: [%{type: :action, text: "Two."}]},
          %{heading: "INT. THIRD - DAY", elements: [%{type: :action, text: "Three."}]}
        ]
      )

    [first, middle, last] = base.ir.scenes

    op = %{
      "kind" => "replace_sequence",
      "value" => %{
        "scene_ids" => [middle.id],
        "scenes" => [
          %{
            "local_id" => "new:middle_a",
            "heading" => "INT. NEW A - DAY",
            "elements" => [
              %{"local_id" => "new:action_a", "type" => "action", "text" => "A.", "attrs" => %{}}
            ]
          },
          %{
            "local_id" => "new:middle_b",
            "heading" => "INT. NEW B - DAY",
            "elements" => [
              %{"local_id" => "new:action_b", "type" => "action", "text" => "B.", "attrs" => %{}}
            ]
          }
        ]
      }
    }

    assert {:ok, result, _} = Fount.Screenplay.apply(base, [op])

    constraint = %{
      "id" => "selected-count",
      "kind" => "scene_count",
      "target" => %{"kind" => "screenplay", "id" => base.id},
      "spec" => %{
        "exact" => 2,
        "selection" => %{"targets" => [%{"kind" => "scene", "id" => middle.id}]}
      },
      "severity" => "required"
    }

    assert [%{"status" => "pass", "measurements" => %{"scene_count" => 2}}] =
             FountProbe.Constraints.deterministic(base, result, [constraint])

    assert Enum.map([first, last], & &1.id) == [
             hd(result.ir.scenes).id,
             List.last(result.ir.scenes).id
           ]
  end
end
