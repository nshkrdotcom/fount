defmodule FountWorkshop.NoteConflictsTest do
  use ExUnit.Case, async: true

  alias FountWorkshop.Writing.NoteConflicts

  test "a scene note and an element note in that scene are marked for review" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{heading: "INT. OFFICE - DAY", elements: [%{type: :action, text: "The key falls."}]},
          %{heading: "EXT. ROAD - DAY", elements: [%{type: :action, text: "Mara leaves."}]}
        ]
      )

    [office, road] = model.ir.scenes
    action = Enum.find(model.ir.elements, &(&1.text == "The key falls."))

    notes = [
      %{
        "id" => "scene",
        "target" => %{"kind" => "scene", "id" => office.id},
        "value" => %{"instruction" => "Keep the key."}
      },
      %{
        "id" => "element",
        "target" => %{"kind" => "element", "id" => action.id},
        "value" => %{"instruction" => "Remove the key."}
      },
      %{
        "id" => "other",
        "target" => %{"kind" => "scene", "id" => road.id},
        "value" => %{"instruction" => "Cut the ferry."}
      }
    ]

    assert [%{"note_ids" => ["scene", "element"], "status" => "potential_conflict"}] =
             NoteConflicts.detect(model, notes)
  end
end
