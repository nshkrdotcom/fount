defmodule FountWorkshop.SequenceRebuildTest do
  use ExUnit.Case, async: true

  alias Fount.{Query, Screenplay}
  alias FountWorkshop.SequenceRebuild

  defp client(scenes) do
    Inference.Client.new!(
      adapter: Inference.Adapters.Mock,
      provider: :mock,
      adapter_opts: [
        response_text: Jason.encode!(%{"approach" => "Combine the handoff", "scenes" => scenes})
      ]
    )
  end

  test "five scenes become three while an unchanged scene and key setup keep their IDs" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. OFFICE - DAY",
            elements: [%{type: :action, text: "Mara opens the ledger."}]
          },
          %{
            heading: "EXT. SHED - DAY",
            elements: [%{type: :action, text: "Dan pockets the brass key."}]
          },
          %{heading: "INT. HALL - DAY", elements: [%{type: :action, text: "The alarm sounds."}]},
          %{
            heading: "EXT. YARD - DAY",
            elements: [%{type: :action, text: "Mara follows the truck."}]
          },
          %{
            heading: "INT. GATEHOUSE - DAY",
            elements: [%{type: :action, text: "The gate is locked."}]
          },
          %{heading: "EXT. FERRY - NIGHT", elements: [%{type: :action, text: "A ferry waits."}]}
        ]
      )

    [office, shed, hall, yard, gatehouse, ferry] = base.ir.scenes
    key_line = Enum.find(base.ir.elements, &(&1.text == "Dan pockets the brass key."))
    selected = [office.id, shed.id, hall.id, yard.id, gatehouse.id]

    scenes = [
      %{
        "heading" => "INT. OFFICE - DAY",
        "elements" => [
          %{"type" => "action", "text" => "Mara opens the ledger."},
          %{"type" => "action", "text" => "The alarm starts before she can read it."}
        ]
      },
      %{
        "heading" => "EXT. SHED - DAY",
        "elements" => [
          %{"type" => "action", "text" => "Dan pockets the brass key."},
          %{"type" => "action", "text" => "Mara sees him do it."}
        ]
      },
      %{
        "heading" => "INT. GATEHOUSE - DAY",
        "elements" => [
          %{"type" => "action", "text" => "The gate is locked. Dan has the key."}
        ]
      }
    ]

    assert {:ok, proposal} =
             SequenceRebuild.propose(
               base,
               selected,
               "Combine the pursuit and gate obstacle into three scenes.",
               client(scenes),
               target_scene_count: 3,
               required_texts: ["Dan pockets the brass key."]
             )

    result = proposal.screenplay
    assert length(result.ir.scenes) == 4
    assert Enum.map(result.ir.scenes, & &1.id) == [office.id, shed.id, gatehouse.id, ferry.id]
    assert Query.node(result, key_line.id).text == key_line.text
    assert Query.scene(result, ferry.id)
    refute Query.scene(result, hall.id)
    refute Query.scene(result, yard.id)
    assert base.ir.scenes |> length() == 6
  end

  test "a missing required passage cannot materialize" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara hides the key."}
            ]
          }
        ]
      )

    [scene] = base.ir.scenes

    replacement = [
      %{
        "heading" => "INT. ROOM - DAY",
        "elements" => [
          %{"type" => "action", "text" => "Mara leaves."}
        ]
      }
    ]

    assert {:error, {:completion_failed, {:invalid_completion, :missing_required_passage}, trace}} =
             SequenceRebuild.propose(base, [scene.id], "Cut the scene.", client(replacement),
               required_texts: ["Mara hides the key."]
             )

    assert length(trace) == 2
    assert Query.scene(base, scene.id)
  end

  test "orphan dialogue is rejected while completion can repair it" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara waits."}
            ]
          }
        ]
      )

    [scene] = base.ir.scenes

    malformed = [
      %{
        "heading" => "INT. ROOM - DAY",
        "elements" => [
          %{"type" => "dialogue", "text" => "Where is Dan?"}
        ]
      }
    ]

    assert {:error, {:completion_failed, {:invalid_completion, :invalid_scene_shape}, trace}} =
             SequenceRebuild.propose(base, [scene.id], "Add conflict.", client(malformed))

    assert length(trace) == 2
  end
end
