defmodule FountProbe.ContinuationVoiceTest do
  use ExUnit.Case, async: true
  test "blind preparation removes names and keeps training and test text disjoint" do
    scenes = for n <- 1..12, do: %{heading: "INT. ROOM - DAY", elements: [%{type: :character, text: if(rem(n, 2) == 0, do: "MARA", else: "DAN")}, %{type: :dialogue, text: "Mara, I brought the numbered parcel #{n} here today."}]}
    model = Fount.Screenplay.new(scenes: scenes) |> Fount.Screenplay.Model.resolve_cast(:literal_cues) |> Fount.Screenplay.Model.refresh()
    ids = Enum.map(Fount.Query.characters(model), & &1.id)
    assert {:ok, prepared} = FountProbe.Voice.prepare(model, %{"character_ids" => ids, "selection" => %{"whole_screenplay" => true}})
    assert Enum.all?(prepared.tests, fn t -> t.text not in Enum.flat_map(prepared.profiles, fn {_, p} -> p.samples end) end)
    refute Jason.encode!(Enum.map(prepared.tests, & &1.state)) =~ "MARA"
    refute Jason.encode!(Enum.map(prepared.tests, & &1.state)) =~ hd(ids)
  end
  test "missing answers do not enter the confusion denominator" do
    tests = [%{id: "t", actual: "voice_a"}]
    stats = FountProbe.Voice.aggregate(tests, [%{"input_id" => "t", "status" => "error", "answers" => %{}}], ["voice_a", "voice_b"])
    assert stats["counts"]["voice_a"]["evaluated"] == 0
    assert stats["soft"]["voice_a"]["voice_b"] == nil
  end
end
