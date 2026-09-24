defmodule FountWorkshop.RecoverTest do
  use ExUnit.Case, async: true

  alias Fount.{Query, Screenplay}
  alias FountWorkshop.Recover

  test "restores historical text on the same element ID without touching the current draft" do
    source =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara pockets the brass key."}
            ]
          }
        ]
      )

    line = Enum.find(source.ir.elements, &(&1.type == :action))

    {:ok, current, _} =
      Screenplay.apply(source, [
        %{
          "kind" => "replace_text",
          "target" => %{"kind" => "element", "id" => line.id},
          "value" => "Mara leaves the key behind."
        }
      ])

    assert {:ok, proposal} = Recover.propose(current, source, line.id)
    assert Query.node(proposal.screenplay, line.id).text == line.text
    assert Query.node(current, line.id).text == "Mara leaves the key behind."
    assert proposal.source_revision_id == source.revision.id
    assert proposal.current_text == "Mara leaves the key behind."
  end

  test "restores a cut beat at its historical position with its original ID" do
    source =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara takes the key."},
              %{type: :action, text: "Dan sees her take it."},
              %{type: :action, text: "They leave together."}
            ]
          }
        ]
      )

    lost = Enum.find(source.ir.elements, &(&1.text == "Dan sees her take it."))

    {:ok, current, _} =
      Screenplay.apply(source, [
        %{
          "kind" => "delete_elements",
          "value" => %{"ids" => [lost.id]}
        }
      ])

    assert Query.node(current, lost.id) == nil

    assert {:ok, proposal} = Recover.propose(current, source, lost.id)
    restored = proposal.screenplay
    assert Query.node(restored, lost.id).text == lost.text
    assert Enum.map(restored.ir.elements, & &1.text) == Enum.map(source.ir.elements, & &1.text)
    assert Query.node(current, lost.id) == nil
  end
end
