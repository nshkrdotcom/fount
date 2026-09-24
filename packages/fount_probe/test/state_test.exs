defmodule FountProbe.StateTest do
  use ExUnit.Case, async: true
  alias Fount.{Query, Screenplay}
  alias FountProbe.State

  test "future scenes, notes and another speaker's scenes stay out of a perspective" do
    raw =
      "INT. ROOM - DAY\n\nA box waits. [[The murderer is Mara.]]\n\nDAN\nOpen it.\n\nEXT. ROAD - NIGHT\n\nMARA\nI killed him.\n"

    model = raw |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :literal_cues)
    [_first, second] = model.ir.scenes
    dan = Enum.find(Query.characters(model), &(&1.display_name == "DAN"))
    mara = Enum.find(Query.characters(model), &(&1.display_name == "MARA"))

    assert {:ok, audience} = State.audience_before(model, second.id)
    text = Jason.encode!(audience)
    assert text =~ "Open it."
    refute text =~ "I killed him."
    refute text =~ "murderer"
    assert {:ok, dan_view} = State.speaker_before(model, dan.id, second.id)
    assert length(dan_view["scenes"]) == 1
    assert {:ok, mara_view} = State.speaker_before(model, mara.id, second.id)
    assert mara_view["scenes"] == []
  end
end
