defmodule FountWorkshop.PropagationTargetsTest do
  use ExUnit.Case, async: true

  test "dependency inspection follows the changed scene and pinned setup" do
    request = %{
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [
        %{"target" => %{"kind" => "element", "id" => "key"}},
        %{
          "target" => %{"kind" => "screenplay", "id" => "script"},
          "spec" => %{"at" => %{"kind" => "scene", "id" => "records"}}
        }
      ],
      "options" => %{"destination" => %{"kind" => "replace_range", "scene_ids" => ["queue"]}}
    }

    assert FountWorkshop.Writing.Preparation.propagation_targets(request) == [
             %{"kind" => "element", "id" => "key"},
             %{"kind" => "scene", "id" => "records"},
             %{"kind" => "scene", "id" => "queue"}
           ]
  end
end
