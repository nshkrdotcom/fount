defmodule FountProbe.ContinuationProjectionTest do
  use ExUnit.Case, async: true
  alias FountProbe.Projection
  defp model do
    "INT. ROOM - DAY\n\nDan palms a key. [[Mara is the killer.]]\n\nDAN\nKeep looking.\n\nEXT. GATE - NIGHT\n\nMARA\nI did it.\n"
    |> Fount.parse!() |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)
  end
  test "a cue does not grant a character access to a private action" do
    m = model(); [_, last] = m.ir.scenes
    dan = Enum.find(Fount.Query.characters(m), &(&1.display_name == "DAN"))
    assert {:ok, state, evidence} = Projection.at(m, %{"scene_id" => last.id, "through_element_id" => nil}, "character_access", character_id: dan.id)
    text = Jason.encode!(state)
    assert text =~ "Keep looking."
    refute text =~ "palms a key"
    refute text =~ "killer"
    refute text =~ "I did it."
    refute state["complete_context"]
    assert Enum.all?(evidence, &(&1["revision_id"] == m.revision.id))
  end
  test "reader fragments retain exact offsets when hidden text is removed" do
    m = model(); assert {:ok, units} = Projection.select(m, %{"whole_screenplay" => true})
    refute Jason.encode!(units) =~ "killer"
    for unit <- units do
      e = Fount.Query.node(m, unit["target"]["id"])
      assert :ok = Fount.Writing.UTF8Span.verify(e.text, unit["target"]["span"], unit["excerpt"])
    end
  end
  test "new structured extraction cannot invent evidence" do
    assert {:error, _} = FountProbe.Extraction.validate(%{"records" => [%{"id" => "x", "kind" => "events", "claim" => "A ghost.", "subjects" => [], "evidence_ids" => ["invented"], "uncertainty" => "unknown"}], "summary" => "Ghost"}, [], ["events"])
  end
end
