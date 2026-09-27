defmodule Fount.Intelligence.StoryWorldTemporalTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.TestSupport.StoryWorldFixture, as: Fixture

  setup do
    screenplay = Fixture.screenplay()
    observation = Fixture.frozen_observation(screenplay)
    [present, flashback, later] = Fixture.scene_events(screenplay)

    %{
      screenplay: screenplay,
      observation: observation,
      present: present,
      flashback: flashback,
      later: later
    }
  end

  test "flashback does not inherit later-presented state and event-qualified death/possession stay temporal",
       ctx do
    records = [
      Fixture.record("story_time_constraint", "flashback-before-present", ctx.screenplay, 1, %{
        "left" => ctx.flashback,
        "right" => ctx.present,
        "relations" => ["before"]
      }),
      Fixture.record("story_time_constraint", "present-before-later", ctx.screenplay, 0, %{
        "left" => ctx.present,
        "right" => ctx.later,
        "relations" => ["before"]
      }),
      Fixture.record("state_transition", "key-taken", ctx.screenplay, 0, %{
        "subject" => "brass-key",
        "attribute" => "possessor",
        "from" => nil,
        "to" => "Mara",
        "event_id" => ctx.present
      }),
      Fixture.record("state_transition", "mara-alive", ctx.screenplay, 0, %{
        "subject" => "Mara",
        "attribute" => "life_status",
        "from" => nil,
        "to" => "alive",
        "event_id" => ctx.present
      }),
      Fixture.record("state_transition", "mara-dies", ctx.screenplay, 2, %{
        "subject" => "Mara",
        "attribute" => "life_status",
        "from" => "alive",
        "to" => "dead",
        "event_id" => ctx.later
      })
    ]

    assert {:ok, world} = StoryWorld.compile(ctx.screenplay, [ctx.observation], records: records)
    assert :unknown == StoryWorld.state_at(world, "brass-key", "possessor", ctx.flashback)
    assert :unknown == StoryWorld.state_at(world, "Mara", "life_status", ctx.flashback)

    assert {:known, %{value: "Mara"}} =
             StoryWorld.state_at(world, "brass-key", "possessor", ctx.present)

    assert {:known, %{value: "alive"}} =
             StoryWorld.state_at(world, "Mara", "life_status", ctx.present)

    assert {:known, %{value: "dead"}} =
             StoryWorld.state_at(world, "Mara", "life_status", ctx.later)
  end

  test "overlap, ambiguity, and unknown chronology do not manufacture a total order", ctx do
    records = [
      Fixture.record("story_time_constraint", "overlap", ctx.screenplay, 0, %{
        "left" => ctx.present,
        "right" => ctx.flashback,
        "relations" => ["overlaps"]
      }),
      Fixture.record("story_time_constraint", "ambiguous", ctx.screenplay, 2, %{
        "left" => ctx.present,
        "right" => ctx.later,
        "relations" => ["before", "overlaps"]
      })
    ]

    assert {:ok, world} = StoryWorld.compile(ctx.screenplay, [ctx.observation], records: records)

    assert %{status: :known, relations: ["overlaps"]} =
             StoryWorld.story_time_relation(world, ctx.present, ctx.flashback)

    assert %{status: :ambiguous, relations: ["before", "overlaps"]} =
             StoryWorld.story_time_relation(world, ctx.present, ctx.later)

    assert :unknown == StoryWorld.story_time_relation(world, ctx.flashback, ctx.later)
  end

  test "contradictory temporal evidence is reported with its source evidence", ctx do
    records = [
      Fixture.record("story_time_constraint", "c-before", ctx.screenplay, 0, %{
        "left" => ctx.present,
        "right" => ctx.later,
        "relations" => ["before"]
      }),
      Fixture.record("story_time_constraint", "c-after", ctx.screenplay, 2, %{
        "left" => ctx.present,
        "right" => ctx.later,
        "relations" => ["after"]
      })
    ]

    assert {:ok, world} = StoryWorld.compile(ctx.screenplay, [ctx.observation], records: records)
    conflict = Enum.find(world.conflicts, &(&1.kind == "temporal_contradiction"))
    assert conflict
    assert Enum.sort(conflict.involved_ids) |> Enum.member?("c-before")
    assert Enum.sort(conflict.involved_ids) |> Enum.member?("c-after")
    assert length(conflict.evidence) == 2

    assert %{status: :contradiction, relations: []} =
             StoryWorld.story_time_relation(world, ctx.present, ctx.later)
  end

  test "strict precedence cycles retain the supporting constraint IDs", ctx do
    records = [
      Fixture.record("story_time_constraint", "cycle-a", ctx.screenplay, 0, %{
        "left" => ctx.present,
        "right" => ctx.flashback,
        "relations" => ["before"]
      }),
      Fixture.record("story_time_constraint", "cycle-b", ctx.screenplay, 1, %{
        "left" => ctx.flashback,
        "right" => ctx.later,
        "relations" => ["before"]
      }),
      Fixture.record("story_time_constraint", "cycle-c", ctx.screenplay, 2, %{
        "left" => ctx.later,
        "right" => ctx.present,
        "relations" => ["before"]
      })
    ]

    assert {:ok, world} = StoryWorld.compile(ctx.screenplay, [ctx.observation], records: records)

    assert Enum.any?(world.conflicts, fn conflict ->
             Enum.all?(["cycle-a", "cycle-b", "cycle-c"], &(&1 in conflict.involved_ids))
           end)

    assert %{status: :contradiction, constraint_ids: ids} =
             StoryWorld.story_time_relation(world, ctx.present, ctx.flashback)

    assert Enum.all?(["cycle-a", "cycle-b", "cycle-c"], &(&1 in ids))
  end
end
