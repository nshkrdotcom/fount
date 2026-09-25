defmodule FountProbe.TypedConstraintTargetsTest do
  use ExUnit.Case, async: true

  test "retain and remove checks honor the declared target kind" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "The key falls."}]}
        ]
      )

    [scene] = model.ir.scenes
    wrong_kind = %{"kind" => "element", "id" => scene.id}

    retained = %{
      "id" => "retain",
      "kind" => "retain_ids",
      "target" => %{"kind" => "screenplay", "id" => model.id},
      "spec" => %{"ids" => [wrong_kind]},
      "severity" => "required"
    }

    removed = %{retained | "id" => "remove", "kind" => "remove_ids"}

    assert [%{"status" => "fail"}, %{"status" => "pass"}] =
             FountProbe.Constraints.deterministic(model, model, [retained, removed])
  end
end
