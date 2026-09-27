defmodule Fount.Intelligence.StoryWorldScopeCausalityTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.TestSupport.StoryWorldFixture, as: Fixture

  test "dream state cannot silently corrupt base state" do
    screenplay = Fixture.screenplay()
    observation = Fixture.frozen_observation(screenplay)
    [present, _flashback, later] = Fixture.scene_events(screenplay)

    records = [
      %{"record_type" => "scope", "id" => "dream-mara", "kind" => "dream", "parent_id" => "base"},
      Fixture.record("event", "dream-event", screenplay, 1, %{
        "scope_id" => "dream-mara",
        "kind" => "dream_image"
      }),
      Fixture.record("state_transition", "base-key", screenplay, 0, %{
        "subject" => "brass-key",
        "attribute" => "possessor",
        "to" => "Mara",
        "event_id" => present
      }),
      Fixture.record("state_transition", "dream-key", screenplay, 1, %{
        "scope_id" => "dream-mara",
        "subject" => "brass-key",
        "attribute" => "possessor",
        "to" => "Dan",
        "event_id" => "dream-event"
      }),
      Fixture.record("story_time_constraint", "present-before-later", screenplay, 2, %{
        "left" => present,
        "right" => later,
        "relations" => ["before"]
      })
    ]

    assert {:ok, world} = StoryWorld.compile(screenplay, [observation], records: records)

    assert {:known, %{value: "Mara"}} =
             StoryWorld.state_at(world, "brass-key", "possessor", later)

    assert {:known, %{value: "Dan"}} =
             StoryWorld.state_at(world, "brass-key", "possessor", "dream-event",
               scope: "dream-mara"
             )
  end

  test "causal direction remains independent from presentation and story-time direction" do
    screenplay = Fixture.screenplay()
    observation = Fixture.frozen_observation(screenplay)
    [present, _flashback, later] = Fixture.scene_events(screenplay)

    records = [
      Fixture.record("story_time_constraint", "present-before-later", screenplay, 0, %{
        "left" => present,
        "right" => later,
        "relations" => ["before"]
      }),
      Fixture.record("causal_relation", "later-causes-present", screenplay, 2, %{
        "causal_type" => "causes",
        "from" => later,
        "to" => present
      })
    ]

    assert {:ok, world} = StoryWorld.compile(screenplay, [observation], records: records)

    assert %{status: :known, relations: ["before"]} =
             StoryWorld.story_time_relation(world, present, later)

    assert StoryWorld.causal_descendants(world, later) == [present]
    assert StoryWorld.causal_ancestors(world, present) == [later]
  end
end
