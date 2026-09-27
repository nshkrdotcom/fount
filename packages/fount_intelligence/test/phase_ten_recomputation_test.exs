defmodule Fount.Intelligence.PhaseTenRecomputationTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.{Reader, Recomputation, StoryWorld}
  alias Fount.Intelligence.TestSupport.PhaseFourFixture, as: Fixture

  test "planner composes connected StoryWorld and presentation-suffix Reader frontiers" do
    screenplay = Fixture.screenplay()
    world = Fixture.story_world(screenplay)
    {:ok, reader} = Reader.reduce(screenplay, Fixture.reader_events(screenplay))

    plan = Recomputation.plan(world, reader, ["fixture:timeline", "reader:key-reveal"])

    assert plan["story_world"]["semantics"] == "story_time_connected_region"
    assert plan["reader"]["semantics"] == "presentation_suffix"
    assert plan["cache_policy"]["revision_edit_deletes_cache_rows"] == false
    assert plan["changed_dependencies"] == ["fixture:timeline", "reader:key-reveal"]
  end

  test "canonical keys distinguish target and evidence identity" do
    assert Recomputation.canonical_keys([
             %{"kind" => "scene", "id" => "scene-7"},
             %{"evidence_id" => "evidence-2"},
             "dependency:explicit"
           ]) == [
             "dependency:explicit",
             "evidence:evidence-2",
             "target:scene:scene-7"
           ]
  end

  test "invalid inputs do not synthesize a frontier" do
    assert {:error, :invalid_recomputation_request} = Recomputation.plan(%{}, %{}, [])
    assert [] == Recomputation.persisted_dependents(%{}, "screenplay", [])
    refute function_exported?(StoryWorld, :delete_measurement_results, 2)
  end
end
