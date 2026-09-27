defmodule Fount.Intelligence.StoryWorldReferenceTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.TestSupport.StoryWorldFixture, as: Fixture
  alias Fount.Screenplay.Model

  test "compile and reference rendering are deterministic for the same canonical revision and frozen observations" do
    screenplay = Fixture.screenplay()
    observation = Fixture.frozen_observation(screenplay)
    [present, _flashback, later] = Fixture.scene_events(screenplay)

    records = [
      Fixture.record("assertion", "key-important", screenplay, 0, %{
        "subject" => "brass-key",
        "predicate" => "story_function",
        "object" => "access",
        "story_time_refs" => [present]
      }),
      Fixture.record("story_time_constraint", "present-before-later", screenplay, 0, %{
        "left" => present,
        "right" => later,
        "relations" => ["before"]
      })
    ]

    assert {:ok, first} = StoryWorld.compile(screenplay, [observation], records: records)
    assert {:ok, second} = StoryWorld.compile(screenplay, [observation], records: records)
    assert Model.plain(first) == Model.plain(second)
    assert StoryWorld.render_json(first) == StoryWorld.render_json(second)
    assert StoryWorld.render_markdown(first) == StoryWorld.render_markdown(second)

    packet =
      StoryWorld.inspection_packet(first,
        protected_strengths: ["keep the key reveal understated"]
      )

    assert packet["claim_class"] == "derived_narrative_state"
    assert packet["diagnoses"] == []
    assert packet["strategies"] == []
    assert packet["protected_strengths"] == ["keep the key reveal understated"]
    assert Enum.any?(packet["evidence"], &(&1["excerpt"] == "Mara pockets the brass key."))
  end

  test "stale or source-mismatched frozen evidence is rejected" do
    screenplay = Fixture.screenplay()
    observation = Fixture.frozen_observation(screenplay)
    bad_evidence = %{hd(observation.evidence) | excerpt: "This is not the screenplay text."}
    observation = %{observation | evidence: [bad_evidence]}

    assert {:error, {:stale_or_invalid_observation, "observation-frozen-1"}} =
             StoryWorld.compile(screenplay, [observation])
  end

  test "counterfactual primitive reports dependency impact without generating replacement pages" do
    screenplay = Fixture.screenplay()
    observation = Fixture.frozen_observation(screenplay)
    [present, _flashback, later] = Fixture.scene_events(screenplay)

    records = [
      Fixture.record("state_transition", "key-taken", screenplay, 0, %{
        "subject" => "brass-key",
        "attribute" => "possessor",
        "to" => "Mara",
        "event_id" => present
      }),
      Fixture.record("story_time_constraint", "present-before-later", screenplay, 2, %{
        "left" => present,
        "right" => later,
        "relations" => ["before"],
        "dependencies" => ["story:key-taken"]
      })
    ]

    assert {:ok, world} = StoryWorld.compile(screenplay, [observation], records: records)
    packet = StoryWorld.counterfactual_remove(world, ["key-taken"])
    assert "present-before-later" in packet.affected_ids
    assert Enum.any?(packet.limitations, &String.contains?(&1, "not generated replacement pages"))
  end
end
