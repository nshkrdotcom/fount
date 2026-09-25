defmodule FountProbe.ContinuationProjectionTest do
  use ExUnit.Case, async: true
  alias FountProbe.Projection

  defp model do
    "INT. ROOM - DAY\n\nDan palms a key. [[Mara is the killer.]]\n\nDAN\nKeep looking.\n\nEXT. GATE - NIGHT\n\nMARA\nI did it.\n"
    |> Fount.parse!()
    |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)
  end

  test "a cue does not grant a character access to a private action" do
    m = model()
    [_, last] = m.ir.scenes
    dan = Enum.find(Fount.Query.characters(m), &(&1.display_name == "DAN"))

    assert {:ok, state, evidence} =
             Projection.at(
               m,
               %{"scene_id" => last.id, "through_element_id" => nil},
               "character_access",
               character_id: dan.id
             )

    text = Jason.encode!(state)
    assert text =~ "Keep looking."
    refute text =~ "palms a key"
    refute text =~ "killer"
    refute text =~ "I did it."
    refute state["complete_context"]
    assert Enum.all?(evidence, &(&1["revision_id"] == m.revision.id))
  end

  test "reader fragments retain exact offsets when hidden text is removed" do
    m = model()
    assert {:ok, units} = Projection.select(m, %{"whole_screenplay" => true})
    refute Jason.encode!(units) =~ "killer"

    for unit <- units do
      e = Fount.Query.node(m, unit["target"]["id"])
      assert :ok = Fount.Writing.UTF8Span.verify(e.text, unit["target"]["span"], unit["excerpt"])
    end
  end

  test "audience projection excludes interior prose unless an exact action fragment is approved" do
    m =
      Fount.parse!(
        "INT. ROOM - DAY\n\nMara privately remembers the hidden key.\n\nA door slams.\n\nDAN\nDid you hear that?\n"
      )
      |> Fount.Screenplay.from_document()

    scene = hd(m.ir.scenes)
    point = List.last(elem(Projection.points(m, scene.id), 1))
    {:ok, units} = Projection.select(m, %{"whole_screenplay" => true})
    door = Enum.find(units, &(&1["text"] == "A door slams."))

    assert {:ok, default, evidence} = Projection.at(m, point, "audience_estimate")
    refute Jason.encode!(default) =~ "hidden key"
    refute Jason.encode!(default) =~ "door slams"
    assert Jason.encode!(default) =~ "Did you hear that?"
    refute Enum.any?(evidence, &(&1["evidence_id"] == door["evidence_id"]))

    assert {:ok, approved, approved_evidence} =
             Projection.at(m, point, "audience_estimate",
               observable_evidence_ids: [door["evidence_id"]]
             )

    assert Jason.encode!(approved) =~ "A door slams."
    refute Jason.encode!(approved) =~ "hidden key"
    assert Enum.any?(approved_evidence, &(&1["evidence_id"] == door["evidence_id"]))
    refute approved["complete_context"]
  end

  test "new structured extraction cannot invent evidence" do
    assert {:error, _} =
             FountProbe.Extraction.validate(
               %{
                 "records" => [
                   %{
                     "id" => "x",
                     "kind" => "events",
                     "claim" => "A ghost.",
                     "subjects" => [],
                     "evidence_ids" => ["invented"],
                     "uncertainty" => "unknown"
                   }
                 ],
                 "summary" => "Ghost"
               },
               [],
               ["events"]
             )
  end
end
