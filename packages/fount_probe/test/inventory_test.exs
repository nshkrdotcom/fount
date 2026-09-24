defmodule FountProbe.InventoryTest do
  use ExUnit.Case, async: true

  alias Fount.{Query, Screenplay}
  alias FountProbe.Inventory

  test "inventory reports exact visible scenes and cast cues without notes" do
    raw =
      "INT. ROOM - DAY\n\nMARA\nWait here.\n\nShe leaves. [[Private answer.]]\n\nEXT. ROAD - NIGHT\n\nA car passes.\n"

    model = raw |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :literal_cues)
    [first, second] = model.ir.scenes
    mara = Enum.find(Query.characters(model), &(&1.display_name == "MARA"))

    assert {:ok, report} = Inventory.inspect(model)
    assert report.inspected_scene_ids == [first.id, second.id]
    assert [room, road] = report.scenes
    assert room.heading == "INT. ROOM - DAY"
    assert room.speaker_ids == [mara.id]
    assert room.dialogue_words == 2
    refute Jason.encode!(room) =~ "Private answer"
    assert road.speaker_ids == []
    assert {:error, :unknown_scene} = Inventory.inspect(model, scene_ids: [Fount.ID.v4()])
  end
end
