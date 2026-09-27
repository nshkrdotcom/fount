defmodule Fount.Intelligence.PhaseEightCapabilitiesTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Capabilities
  alias Fount.Intelligence.Packs
  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.TestSupport.PhaseEightFixture

  test "emotional/value movement keeps conditions multidimensional and connects visible consequence to story evidence" do
    screenplay = PhaseEightFixture.screenplay()
    {:ok, world} = StoryWorld.compile(screenplay, [], records: PhaseEightFixture.records(screenplay))
    [scene | _] = screenplay.ir.scenes

    entry =
      PhaseEightFixture.complete_entry(
        scene.id,
        ~w(anticipated_loss major_event reaction_consequence behavioral_consequence reversal),
        %{
          "practical_direction" => "worsens",
          "hope_direction" => "worsens",
          "fear_direction" => "worsens",
          "security_direction" => "worsens",
          "belonging_direction" => "unchanged",
          "trust_direction" => "worsens",
          "status_direction" => "unchanged",
          "control_direction" => "worsens",
          "certainty_direction" => "improves",
          "moral_confidence_direction" => "mixed"
        }
      )

    {:ok, result} =
      Capabilities.analyze(
        "emotional_value_movement",
        world,
        %{"character" => "Mara"},
        [entry],
        []
      )

    [point] = result.derived_state["condition_trajectory"]
    assert point["directions"]["certainty_direction"] == "improves"
    assert point["directions"]["moral_confidence_direction"] == "mixed"
    assert result.derived_state["event_reaction_relationships"] != []
    refute Map.has_key?(result.derived_state, "emotion_score")
  end

  test "theme produces hypotheses with counterevidence and no authoritative theme/depth score" do
    screenplay = PhaseEightFixture.screenplay()
    {:ok, world} = StoryWorld.compile(screenplay, [], records: PhaseEightFixture.records(screenplay))
    [scene_a, scene_b | _] = screenplay.ir.scenes

    entries = [
      PhaseEightFixture.complete_entry(
        scene_a.id,
        ~w(value_conflict choice_embodies_conflict consequence_complicates_conflict motif_reinforces_question),
        %{"conflict_axis" => "loyalty_vs_truth"}
      ),
      PhaseEightFixture.complete_entry(
        scene_b.id,
        ~w(value_conflict contradictory_signal),
        %{"conflict_axis" => "loyalty_vs_truth"}
      )
    ]

    {:ok, result} =
      Capabilities.analyze(
        "theme_meaning",
        world,
        %{"scope" => "selection"},
        entries,
        intent: %{"theme_question" => "What does loyalty cost when it protects a lie?"}
      )

    [hypothesis] = result.derived_state["thematic_hypotheses"]
    assert hypothesis["id"] == "theme.axis.loyalty_vs_truth"
    assert scene_b.id in hypothesis["counterevidence_scene_ids"]
    refute Map.has_key?(result.derived_state, "theme_score")
    refute Map.has_key?(result.derived_state, "depth_score")
  end

  test "genre pack interpretation honors explicit subversion instead of converting convention into a defect rule" do
    screenplay = PhaseEightFixture.screenplay()
    {:ok, world} = StoryWorld.compile(screenplay, [], records: PhaseEightFixture.records(screenplay))
    [scene | _] = screenplay.ir.scenes
    {:ok, core} = Packs.core("genre.mystery")

    pack = put_in(core, ["intent", "subversions"], ["Reveal the culprit at midpoint; keep the second half character-first."])

    entry =
      PhaseEightFixture.complete_entry(
        scene.id,
        ~w(expectation_present conflict_with_writer_intent expectation_subverted intentional_subversion_visible),
        %{}
      )

    {:ok, result} =
      Capabilities.analyze("genre_lens_packs", world, %{"genre_pack" => pack}, [entry], [])

    assert result.derived_state["subversion_alignment"]["diagnostic_defect_inference_suppressed"]
    refute Enum.any?(result.diagnoses, &(&1["id"] == "genre.intent_conflict_candidate"))
  end

  test "revision comparison separates reader presentation, diegetic state and story-time effects" do
    before_model = PhaseEightFixture.screenplay()
    after_model = PhaseEightFixture.revised_screenplay()

    {:ok, before_world} =
      StoryWorld.compile(before_model, [], records: PhaseEightFixture.records(before_model))

    {:ok, after_world} =
      StoryWorld.compile(after_model, [], records: PhaseEightFixture.records(after_model))

    before_scene = List.last(before_model.ir.scenes)
    after_scene = List.last(after_model.ir.scenes)

    before_entries = [PhaseEightFixture.complete_entry(before_scene.id, ~w(protected_strength_preserved), %{})]

    after_entries =
      [
        PhaseEightFixture.complete_entry(
          after_scene.id,
          ~w(intended_effect_present causal_risk voice_drift),
          %{}
        )
      ]

    {:ok, result} =
      Capabilities.compare_revision(
        before_world,
        after_world,
        %{"intended_effect" => "Mara chooses public accountability without losing the private history."},
        before_entries,
        after_entries,
        intended_effect: "Mara chooses public accountability without losing the private history.",
        protected_strengths: ["The watch remains emotionally meaningful"],
        structural_diff: Fount.Screenplay.diff(before_model, after_model),
        source_diff: String.myers_difference(Fount.Screenplay.to_fountain(before_model), Fount.Screenplay.to_fountain(after_model))
      )

    split = result.derived_state["presentation_vs_diegetic"]
    assert split["kept_separate"]
    assert Map.has_key?(split, "presentation_effects")
    assert Map.has_key?(split, "diegetic_state_effects")
    assert Map.has_key?(split, "story_time_effects")
    assert result.derived_state["target_effect"]["quality_score"] == nil or
             not Map.has_key?(result.derived_state["target_effect"], "quality_score")
  end
end
