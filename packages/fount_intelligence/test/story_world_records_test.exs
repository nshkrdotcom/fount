defmodule Fount.Intelligence.StoryWorldRecordsTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.TestSupport.StoryWorldFixture, as: Fixture

  test "core record families retain evidence, uncertainty, epistemic ownership, and dependencies" do
    screenplay = Fixture.screenplay()
    observation = Fixture.frozen_observation(screenplay)
    [present, _flashback, later] = Fixture.scene_events(screenplay)

    records = [
      Fixture.record("entity", "key-entity", screenplay, 0, %{"kind" => "prop", "name" => "brass key"}),
      Fixture.record("event", "handoff-event", screenplay, 2, %{"kind" => "handoff", "label" => "Mara leaves the key"}),
      Fixture.record("interaction", "handoff-interaction", screenplay, 2, %{
        "event_id" => "handoff-event",
        "participants" => ["Mara", "Dan"],
        "objectives" => ["leave the key without explanation"],
        "changes" => %{"possession" => "offered"}
      }),
      Fixture.record("assertion", "mara-knows-key", screenplay, 0, %{
        "subject" => "brass-key",
        "predicate" => "location_known",
        "object" => true,
        "epistemic_owner" => "Mara",
        "story_time_refs" => [present],
        "alternatives" => ["Mara may only suspect the exact location"]
      }),
      Fixture.record("goal", "mara-goal", screenplay, 0, %{
        "owner" => "Mara",
        "description" => "move the key without being seen",
        "level" => "scene"
      }),
      Fixture.record("commitment", "dan-promise", screenplay, 2, %{
        "kind" => "promise",
        "from" => "Dan",
        "to" => "Mara",
        "terms" => "keep the key hidden"
      }),
      Fixture.record("beat", "corridor-beat", screenplay, 0, %{
        "scene_id" => hd(screenplay.ir.scenes).id,
        "summary" => "Mara takes the key",
        "objective" => "gain access",
        "outcome" => "key acquired"
      }),
      Fixture.record("motif", "key-motif", screenplay, 0, %{
        "kind" => "object",
        "label" => "brass key",
        "occurrences" => [present, later]
      }),
      Fixture.record("story_time_constraint", "present-before-later", screenplay, 0, %{
        "left" => present,
        "right" => later,
        "relations" => ["before"]
      }),
      Fixture.record("causal_relation", "taking-enables-handoff", screenplay, 2, %{
        "causal_type" => "enables",
        "from" => present,
        "to" => "handoff-event",
        "dependencies" => ["story:key-entity"]
      })
    ]

    assert {:ok, world} = StoryWorld.compile(screenplay, [observation], records: records)
    assert world.entities["key-entity"].name == "brass key"
    assert world.interactions["handoff-interaction"].changes == %{"possession" => "offered"}
    assert world.goals["mara-goal"].description == "move the key without being seen"
    assert world.commitments["dan-promise"].terms == "keep the key hidden"
    assert world.beats["corridor-beat"].outcome == "key acquired"
    assert world.motifs["key-motif"].occurrences == [present, later]

    assert [%{id: "mara-knows-key"}] = StoryWorld.knowledge_at(world, "Mara", later, predicate: "location_known")
    assert StoryWorld.causal_descendants(world, present) == ["handoff-event"]
    assert StoryWorld.evidence_for(world, "key-entity") != []
    assert "taking-enables-handoff" in StoryWorld.affected_by(world, ["story:key-entity"])
  end

  test "Phase-2 extraction record kinds remain ingestible as evidence-backed StoryWorld inputs" do
    screenplay = Fixture.screenplay()
    observation = Fixture.frozen_observation(screenplay)

    legacy = %{
      "id" => "legacy-event-1",
      "kind" => "events",
      "claim" => "Mara takes the key",
      "subjects" => ["Mara", "brass-key"],
      "uncertainty" => "low",
      "evidence" => [Fixture.scene_evidence(screenplay, 0)]
    }

    assert {:ok, world} = StoryWorld.compile(screenplay, [observation], records: [legacy])
    assert world.events["legacy-event-1"].label == "Mara takes the key"
  end
end
