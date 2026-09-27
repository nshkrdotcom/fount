defmodule Fount.Intelligence.PhaseSevenCapabilitiesTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.{Capabilities, Reader}
  alias Fount.Intelligence.TestSupport.PhaseSevenFixture

  test "audience family exposes strict-forward reader ledgers without later-page leakage" do
    screenplay = PhaseSevenFixture.screenplay()
    world = PhaseSevenFixture.story_world(screenplay)
    {:ok, reader} = Reader.reduce(screenplay, PhaseSevenFixture.reader_events(screenplay))
    [scene | _] = screenplay.ir.scenes

    entries = [entry(scene.id, [:open_question, :expectation, :forward_pull])]

    {:ok, result} =
      Capabilities.analyze(
        "audience_reader_experience",
        world,
        %{"scope" => "selection"},
        entries,
        reader: reader
      )

    assert result.trajectories["semantics"] == "presentation_relative_forward_only"
    assert result.derived_state["question_ledger"] != %{}
    assert result.metadata["reader_event_count"] > 0
    assert Enum.all?(result.trajectories["reader_checkpoints"], &is_map/1)
  end

  test "sequence family reports presentation and story-time views separately" do
    screenplay = PhaseSevenFixture.screenplay()
    world = PhaseSevenFixture.story_world(screenplay)
    scenes = Enum.take(screenplay.ir.scenes, 4)

    entries =
      Enum.map(scenes, fn scene ->
        entry(scene.id, [:objective_active, :objective_progress, :knowledge_change, :handoff_pressure])
      end)

    {:ok, result} =
      Capabilities.analyze(
        "sequence_movement",
        world,
        %{"scene_ids" => Enum.map(scenes, & &1.id)},
        entries,
        []
      )

    assert result.trajectories["presentation"]["semantics"] == "presentation_relative"
    assert result.trajectories["story_time"]["semantics"] == "diegetic_story_time_partial"
    assert result.derived_state["movement_density"]["scene_count"] == 4
    assert is_map(result.derived_state["escalation_dimensions"])
  end

  test "dialogue family keeps turn-pair, tactic, status, exposition and context evidence distinct" do
    screenplay = PhaseSevenFixture.screenplay()
    world = PhaseSevenFixture.story_world(screenplay)
    scene = Enum.at(screenplay.ir.scenes, 2)

    entries = [
      entry(scene.id, [:responds, :evades, :exposition, :tactic_shift, :status_shift, :exchange_changes_state, :voice_distinction])
      |> Map.put("pair_ordinal", 1)
      |> Map.put("turn_pair", %{
        "previous" => %{"speaker" => "MARA", "text" => "What does D.R. open?"},
        "current" => %{"speaker" => "DAN", "text" => "Nothing you want."}
      })
      |> Map.put("context_slots", ["speaker_beliefs"])
    ]

    {:ok, result} =
      Capabilities.analyze(
        "dialogue_interaction",
        world,
        %{"characters" => ["Mara", "Dan"]},
        entries,
        []
      )

    assert length(result.derived_state["turn_pair_observations"]) == 1
    assert result.derived_state["context_usage"]["slot_names"] == ["speaker_beliefs"]
    assert length(result.trajectories["exchange_order_tactic"]) == 1
    assert length(result.derived_state["status_transactions"]) == 1
  end

  test "setup/payoff family flags presentation/story-time divergence for later-presented flashback payoff" do
    screenplay = PhaseSevenFixture.screenplay()
    world = PhaseSevenFixture.story_world(screenplay)
    scene = hd(screenplay.ir.scenes)

    {:ok, result} =
      Capabilities.analyze(
        "setup_payoff_motifs",
        world,
        %{"scope" => "whole_screenplay"},
        [entry(scene.id, [:setup_signal, :payoff, :transformation, :motif_callback])],
        []
      )

    payoffs =
      result.derived_state["setup_payoff_lifecycle"]
      |> Enum.flat_map(&(&1["payoffs"] || []))

    assert Enum.any?(payoffs, & &1["presentation_story_time_diverge"])
    assert Enum.any?(result.derived_state["motif_occurrences"], &(&1["callback_candidate"] == true))
  end

  defp entry(scene_id, supported_keys) do
    supported = MapSet.new(Enum.map(supported_keys, &Atom.to_string/1))

    answers =
      Map.new(
        ~w(open_question expectation visible_threat valued_uncertainty curiosity_gap surprise_candidate comprehension_risk intentional_ambiguity reveal_changes_inference forward_pull objective_active objective_progress constraint_escalation stakes_escalation knowledge_change relationship_change choice_change tactic_shift reversal local_outcome repeated_function handoff_pressure responds evades redirects attacks bargains reveals conceals subtext exposition exposition_dramatic_work status_shift knowledge_asymmetry repetition exchange_changes_state voice_distinction setup_signal reinforcement transformation payoff subversion abandonment unsupported_payoff orphaned_setup motif_callback motif_function_change over_signaled revision_break_candidate),
        fn key ->
          status = if MapSet.member?(supported, key), do: "supported", else: "not_supported"
          {key, %{"status" => status, "probability" => if(status == "supported", do: 0.9, else: 0.1)}}
        end
      )

    %{
      "input_id" => "fixture:#{scene_id}",
      "scene_id" => scene_id,
      "status" => "complete",
      "answers" => answers,
      "observations" => [],
      "provenance" => %{"measurement_ids" => ["measurement:#{scene_id}"]}
    }
  end
end
