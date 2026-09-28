defmodule Fount.Intelligence.PhaseElevenNonlinearBenchmarkTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.{Reader, StoryWorld, Temporal}
  alias Fount.Intelligence.TestSupport.PhaseFourFixture, as: Fixture

  test "Phase-11 nonlinear benchmark keeps presentation order separate from story time" do
    scenario =
      :fount_intelligence
      |> Application.app_dir("priv/evaluation/nonlinear_story_time.synthetic.json")
      |> File.read!()
      |> Jason.decode!()

    assert scenario["expected_invariants"] == [
             "reader_reduces_in_presentation_order",
             "flashback_does_not_inherit_future_state",
             "unknown_story_time_stays_unknown_without_evidence",
             "causality_is_not_inferred_from_presentation_order"
           ]

    screenplay = Fixture.screenplay()
    world = Fixture.story_world(screenplay)
    assert {:ok, reader} = Reader.reduce(screenplay, Fixture.reader_events(screenplay))
    [scene_1, scene_2, scene_3, scene_4] = Fixture.scene_events(screenplay)

    assert Enum.map(reader.points, & &1["ordinal"]) ==
             Enum.to_list(0..(length(reader.points) - 1))

    assert %{status: :known, relations: ["before"]} =
             StoryWorld.story_time_relation(world, scene_3, scene_1)

    assert %{status: :known, relations: ["before"]} =
             StoryWorld.story_time_relation(world, scene_2, scene_4)

    story_view = Temporal.sequence_view(world, [scene_1, scene_2, scene_3], ordering: :story_time)
    assert story_view["semantics"] == "diegetic_story_time_partial"
    assert Enum.map(story_view["events"], & &1["id"]) == [scene_1, scene_2, scene_3]

    relation =
      Enum.find(story_view["relations"], fn item ->
        item["left"] == scene_1 and item["right"] == scene_3
      end)

    assert relation["relation"]["status"] == "known"
    assert relation["relation"]["relations"] == ["after"]
  end
end
