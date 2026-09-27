defmodule Fount.Intelligence.TemporalViewsTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Temporal
  alias Fount.Intelligence.TestSupport.PhaseFourFixture, as: Fixture

  setup do
    screenplay = Fixture.screenplay()
    world = Fixture.story_world(screenplay)
    {:ok, screenplay: screenplay, world: world, events: Fixture.scene_events(screenplay)}
  end

  test "non-linear presentation never manufactures diegetic chronology", %{world: world, events: events} do
    [scene_1, _scene_2, scene_3, _scene_4] = events

    presentation = Temporal.sequence_view(world, [scene_1, scene_3], ordering: :presentation)
    story_time = Temporal.sequence_view(world, [scene_1, scene_3], ordering: :story_time)

    assert presentation["semantics"] == "presentation_relative"
    assert Enum.map(presentation["events"], & &1["id"]) == [scene_1, scene_3]
    assert story_time["semantics"] == "diegetic_story_time_partial"

    assert [%{"relation" => relation}] = story_time["relations"]
    assert relation["status"] == "known"
    assert relation["relations"] == ["after"]
  end

  test "relationship state stays directed and supports asymmetry", %{world: world, events: events} do
    [scene_1, _scene_2, _scene_3, _scene_4] = events

    mara_to_dan = Temporal.relationship_state(world, "Mara", "Dan", scene_1)
    dan_to_mara = Temporal.relationship_state(world, "Dan", "Mara", scene_1)

    assert mara_to_dan["attributes"]["relationship.trust"]["value"] == "guarded"
    refute Map.has_key?(mara_to_dan["attributes"], "relationship.leverage")
    assert dan_to_mara["attributes"]["relationship.leverage"]["value"] == "high"
    refute Map.has_key?(dan_to_mara["attributes"], "relationship.trust")
  end

  test "character state includes event-qualified resources and epistemic partitions", %{world: world, events: events} do
    [_scene_1, scene_2, _scene_3, scene_4] = events

    state = Temporal.character_state(world, "Mara", scene_4)

    assert state["semantics"] == "diegetic_story_time_qualified"
    assert state["resources"]["attributes"]["possession.key"]["value"] == true
    assert state["resources"]["attributes"]["access.archive"]["value"] == true
    assert Enum.any?(state["knowledge"]["knows"], &(&1["id"] == "mara-knows-key-origin"))

    access_at_open = Temporal.resource_state(world, "Mara", scene_2)
    assert access_at_open["attributes"]["access.archive"]["value"] == true
  end

  test "setup/payoff ledger keeps open and paid lifecycle visible", %{world: world} do
    ledger = Temporal.setup_payoff_ledger(world)
    promise = Enum.find(ledger["entries"], &(&1["setup_id"] == "promise-key"))

    assert promise["setup_kind"] == "promise"
    assert promise["lifecycle"] == "paid_off"
    assert Enum.any?(promise["payoffs"], &(&1["type"] == "pays_off"))
  end

  test "story-time recomputation expands through the connected temporal region, not presentation suffix", %{
    world: world,
    events: events
  } do
    [_scene_1, scene_2, scene_3, scene_4] = events
    region = Temporal.recomputation_region(world, ["fixture:timeline"])

    assert region["semantics"] == "story_time_connected_region"
    assert scene_2 in region["story_time_node_ids"]
    assert scene_3 in region["story_time_node_ids"]
    assert scene_4 in region["story_time_node_ids"]
  end
end
