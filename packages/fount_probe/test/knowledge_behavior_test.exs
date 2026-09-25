defmodule FountProbe.KnowledgeBehaviorTest do
  use ExUnit.Case, async: true

  test "behavior question receives the selected action and only prior evidence" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "The box is locked."},
              %{type: :action, text: "Mara uses the hidden key."}
            ]
          }
        ]
      )

    behavior = List.last(model.ir.elements)

    assert {:ok, [input], []} =
             FountProbe.KnowledgeTrace.Behavior.prepare(
               model,
               [behavior.id],
               [%{"kind" => "reader"}],
               "Mara knows where the key is",
               %{},
               []
             )

    state = input["state"]
    assert state["selected_behavior"]["excerpt"] == behavior.text
    refute Enum.any?(state["prior_state"]["material"], &(&1["text"] == behavior.text))
    assert Enum.any?(state["prior_state"]["material"], &(&1["text"] == "The box is locked."))
  end
end
