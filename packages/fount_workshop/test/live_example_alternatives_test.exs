defmodule FountWorkshop.LiveExampleAlternativesTest do
  use ExUnit.Case, async: true

  test "insertion passage selection explicitly includes its required setup group" do
    candidate = %{
      "id" => "candidate-1",
      "change_groups" => [
        %{
          "id" => "setup",
          "depends_on" => [],
          "addresses_notes" => [],
          "operations" => [%{"kind" => "replace_text"}]
        },
        %{
          "id" => "exit",
          "depends_on" => ["setup"],
          "addresses_notes" => [],
          "operations" => [%{"kind" => "insert_elements"}]
        }
      ]
    }

    assert FountWorkshop.LiveExample.alternative_pick(candidate, nil) == %{
             "candidate_id" => "candidate-1",
             "group_ids" => ["setup", "exit"]
           }
  end

  test "a full scene replacement has no selectively combinable passage" do
    candidate = %{
      "id" => "candidate-2",
      "change_groups" => [
        %{
          "id" => "whole_scene",
          "depends_on" => [],
          "addresses_notes" => [],
          "operations" => [%{"kind" => "replace_scene_body"}]
        }
      ]
    }

    assert FountWorkshop.LiveExample.alternative_pick(candidate, nil) ==
             {:error, :alternative_has_no_selectable_passage}
  end
end
