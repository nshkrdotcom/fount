defmodule Fount.Intelligence.PhaseSixCapabilitiesTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Capabilities
  alias Fount.Intelligence.TestSupport.PhaseSixFixture

  test "scene engine preserves source state and surfaces entry/exit and consequence candidates" do
    screenplay = PhaseSixFixture.screenplay()
    world = PhaseSixFixture.story_world(screenplay)
    scene_id = hd(screenplay.ir.scenes).id

    entry = measurement(scene_id, %{
      objective: "supported",
      opposition: "supported",
      stakes: "supported",
      urgency: "supported",
      tactic: "supported",
      tactic_shift: "not_supported",
      reveal: "supported",
      decision: "uncertain",
      consequence: "not_supported",
      value_delta: "not_supported",
      relationship_delta: "supported",
      preamble_candidate: "not_supported",
      linger_candidate: "supported"
    })

    {:ok, result} = Capabilities.analyze("scene_engine", world, %{"scene_id" => scene_id}, [entry], [])
    [scene] = result.derived_state["scenes"]

    assert scene["source_state"]["objective_records"] != []
    assert scene["entry_exit_delta"]["state_transitions"] != []
    assert scene["turn_candidates"] != []
    assert is_map(scene["surrounding_sequence_contribution"])
    assert Enum.any?(result.diagnoses, &String.starts_with?(&1["id"], "scene.entry_exit_economy_candidate:"))
    assert Enum.all?(result.evidence, &is_map/1)
  end

  test "agency keeps explicit causality separate from presentation and reports causal reach" do
    screenplay = PhaseSixFixture.screenplay()
    world = PhaseSixFixture.story_world(screenplay)
    entries = Enum.map(screenplay.ir.scenes, &measurement(&1.id, %{initiating_choice: "supported", active_goal_pursuit: "supported", causal_support: "supported", motive_support: "supported", knowledge_support: "supported", relationship_pressure_support: "supported", alternate_support: "uncertain", reactive_only: "not_supported", delayed_consequence: "uncertain", removal_impact: "supported"}))

    {:ok, result} = Capabilities.analyze("agency_causality", world, %{"character" => "Mara"}, entries, intent: %{"agency" => "initiating"})

    assert result.derived_state["decision_records"] != []
    assert Enum.any?(result.derived_state["causal_reach"], &(&1["descendant_count"] > 0))
    assert result.derived_state["consequence_latency"] != []
    assert Enum.all?(result.derived_state["consequence_latency"], &Map.has_key?(&1, "story_time_relation"))
    assert is_boolean(result.trajectories["event_story_time"]["non_linear_presentation"])
  end

  test "character trajectory allows non-transformational arcs and exposes non-linear diegetic order" do
    screenplay = PhaseSixFixture.screenplay()
    world = PhaseSixFixture.story_world(screenplay)
    [s1, s2 | rest] = screenplay.ir.scenes

    entries =
      [
        character_measurement(s1.id, "steadfast"),
        character_measurement(s2.id, "deliberately_static")
      ] ++ Enum.map(rest, &character_measurement(&1.id, "mixed_or_unclear"))

    {:ok, result} = Capabilities.analyze("character_trajectory", world, %{"character" => "Mara"}, entries, [])

    assert Enum.any?(result.derived_state["arc_hypotheses"], &(&1["pattern"] == "steadfast"))
    assert Enum.any?(result.derived_state["arc_hypotheses"], &(&1["pattern"] == "deliberately_static"))
    assert result.trajectories["non_linear_presentation"]
    assert Enum.any?(result.limitations, &String.contains?(&1, "No transformation arc is required"))
  end

  test "relationship dynamics retains directionality and non-linear presentation" do
    screenplay = PhaseSixFixture.screenplay()
    world = PhaseSixFixture.story_world(screenplay)
    entries = Enum.map(screenplay.ir.scenes, &relationship_measurement/1)

    {:ok, result} = Capabilities.analyze("relationship_dynamics", world, %{"characters" => ["Mara", "Dan"]}, entries, [])

    assert result.derived_state["dimensions"]["trust"] != []
    assert Enum.any?(result.derived_state["directional_state"], &(&1["from"] == "Mara" and &1["to"] == "Dan"))
    assert Enum.any?(result.derived_state["directional_state"], &(&1["from"] == "Dan" and &1["to"] == "Mara"))
    assert result.trajectories["non_linear_presentation"]
  end


  test "relationship dynamics accepts a selected group without collapsing it to a pair" do
    screenplay = PhaseSixFixture.screenplay()
    world = PhaseSixFixture.story_world(screenplay)
    entries = Enum.map(screenplay.ir.scenes, &relationship_measurement/1)

    {:ok, result} =
      Capabilities.analyze(
        "relationship_dynamics",
        world,
        %{"characters" => ["Mara", "Dan", "Investigator"]},
        entries,
        []
      )

    assert result.derived_state["parties"] == ["Mara", "Dan", "Investigator"]
    assert result.derived_state["dimensions"]["trust"] != []
  end

  defp measurement(scene_id, statuses) do
    %{
      "input_id" => "fixture:#{scene_id}",
      "scene_id" => scene_id,
      "status" => "complete",
      "answers" => Map.new(statuses, fn {key, status} -> {to_string(key), %{"status" => status, "type" => "noul"}} end),
      "observations" => [],
      "provenance" => %{"measurement_ids" => ["measurement:#{scene_id}"]}
    }
  end

  defp character_measurement(scene_id, arc) do
    base = measurement(scene_id, %{active_goal: "supported", belief_change: "uncertain", knowledge_change: "supported", tactic_change: "supported", commitment_change: "uncertain", relationship_change: "supported", value_change: "supported", adapts_after_failure: "supported", choice_reveals_character: "supported", repeated_defense: "not_supported"})
    put_in(base, ["answers", "arc_pattern"], %{"status" => "supported", "type" => "choice", "choice" => arc})
  end

  defp relationship_measurement(scene) do
    measurement(scene.id, %{trust_change: "supported", intimacy_change: "uncertain", allegiance_change: "uncertain", leverage_change: "supported", status_change: "uncertain", dependency_change: "uncertain", attraction_change: "not_supported", resentment_change: "uncertain", obligation_change: "supported", concealment_change: "supported", knowledge_asymmetry_change: "supported", interaction_changes_relationship: "supported", repetitive_negotiation: "not_supported", betrayal_or_payoff_prepared: "supported"})
  end
end
