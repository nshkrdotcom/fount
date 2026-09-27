defmodule Fount.Intelligence.TestSupport.PhaseEightFixture do
  @moduledoc false

  alias Fount.Intelligence.TestSupport.PhaseSevenFixture

  def screenplay, do: PhaseSevenFixture.screenplay()
  def records(screenplay), do: PhaseSevenFixture.records(screenplay)
  def reader_events(screenplay), do: PhaseSevenFixture.reader_events(screenplay)

  def revised_screenplay do
    screenplay = screenplay()
    element = screenplay |> PhaseSevenFixture.actions() |> List.last()

    {:ok, revised} =
      Fount.Screenplay.apply(
        screenplay,
        Fount.Edit.replace_text(
          element.id,
          "Mara keeps the watch, slides the ledger to the investigator, and leaves Dan holding the old bus map."
        )
      )

    revised
  end

  def complete_entry(scene_id, supported, choices \\ %{}) do
    keys =
      ~w(
        practical_direction hope_direction fear_direction security_direction belonging_direction
        trust_direction status_direction control_direction certainty_direction moral_confidence_direction
        anticipated_gain anticipated_loss major_event reaction_consequence behavioral_consequence reversal
        reversal_prepared declared_feeling_without_behavioral_change value_action_inconsistency
        value_conflict conflict_axis choice_embodies_conflict consequence_complicates_conflict
        motif_reinforces_question contrast_reinforces_question ending_recontextualizes_question
        writer_intent_alignment contradictory_signal expectation_present expectation_satisfied
        expectation_subverted intentional_subversion_visible specialized_pressure conflict_with_writer_intent
        intended_effect_present protected_strength_preserved continuity_risk knowledge_risk causal_risk
        voice_drift action_readability_risk setup_payoff_break reader_state_regression
      )

    answers =
      Map.new(keys, fn key ->
        {key, answer_for(key, supported, choices)}
      end)

    %{
      "input_id" => "phase8:#{scene_id}",
      "scene_id" => scene_id,
      "status" => "complete",
      "answers" => answers,
      "observations" => [],
      "provenance" => %{"measurement_ids" => ["measurement:#{scene_id}"]}
    }
  end

  defp answer_for(key, supported, choices) do
    case Map.get(choices, key) do
      nil ->
        if key in supported,
          do: %{"status" => "supported", "probability" => 0.9},
          else: %{"status" => "not_supported", "probability" => 0.1}

      choice ->
        %{"status" => "supported", "choice" => choice, "probability" => 0.9}
    end
  end
end
