defmodule Fount.Intelligence.ReaderStoryWorldDifferentialTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.{Reader, StoryWorld, Temporal}
  alias Fount.Intelligence.TestSupport.PhaseFourFixture, as: Fixture

  test "reader-visible character knowledge can differ from diegetic character knowledge" do
    screenplay = Fixture.screenplay()
    world = Fixture.story_world(screenplay)
    {:ok, reader} = Reader.reduce(screenplay, Fixture.reader_events(screenplay))
    [scene_1, scene_2, scene_3, _scene_4] = Fixture.scene_events(screenplay)
    [_action_1, action_2 | _] = Fixture.actions(screenplay)

    assert {:ok, differential} =
             Reader.knowledge_differential(reader, world, "Mara", action_2.id, scene_2)

    assert differential["different"] == true
    assert differential["reader_model"] != []
    assert differential["diegetic_knowledge"] != []

    assert %{status: :known, relations: ["before"]} =
             StoryWorld.story_time_relation(world, scene_3, scene_1)

    story_view = Temporal.sequence_view(world, [scene_1, scene_2, scene_3], ordering: :story_time)
    assert story_view["semantics"] == "diegetic_story_time_partial"
  end

  test "reader relationship trajectory is presentation-relative and directed" do
    screenplay = Fixture.screenplay()
    [action_1, _action_2, _action_3, action_4] = Fixture.actions(screenplay)

    relationship_events = [
      Fixture.event("reader-rel-1", "relationship", "set", action_1, screenplay,
        key: "mara-dan",
        data: %{"from" => "Mara", "to" => "Dan", "dimensions" => %{"trust" => "guarded"}}
      ),
      Fixture.event("reader-rel-2", "relationship", "change", action_4, screenplay,
        key: "mara-dan",
        data: %{"from" => "Mara", "to" => "Dan", "dimensions" => %{"trust" => "tentative"}}
      )
    ]

    assert {:ok, reader} = Reader.reduce(screenplay, relationship_events)
    trajectory = Reader.trajectory(reader, :relationships, "mara-dan")

    assert trajectory["semantics"] == "presentation_relative"
    assert Enum.any?(trajectory["points"], &(&1["value"]["dimensions"]["trust"] == "guarded"))
    assert List.last(trajectory["points"])["value"]["dimensions"]["trust"] == "tentative"
  end
end
