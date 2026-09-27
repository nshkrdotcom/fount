defmodule Fount.Intelligence.Capabilities.EmotionalValueMovement do
  @moduledoc "Pure Phase-8 emotional/value-condition reasoning without claiming universal human emotion."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Screenplay.Model

  @direction_keys ~w(practical_direction hope_direction fear_direction security_direction belonging_direction trust_direction status_direction control_direction certainty_direction moral_confidence_direction)a
  @signal_keys ~w(anticipated_gain anticipated_loss major_event reaction_consequence behavioral_consequence reversal reversal_prepared declared_feeling_without_behavioral_change value_action_inconsistency)a
  @keys @direction_keys ++ @signal_keys

  def analyze(world, subject, entries, opts \\ []) do
    trajectory = Enum.map(entries, &trajectory_point/1)
    transitions = relevant_transitions(world, subject)
    diagnoses = diagnoses(entries)

    %Result{
      family: "emotional_value_movement",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: status(entries),
      evidence:
        Support.merge_evidence([
          Support.measurement_evidence(entries),
          Support.evidence(transitions)
        ]),
      measurements: %{
        "keys" => Enum.map(@keys, &to_string/1),
        "entries" => entries
      },
      derived_state: %{
        "condition_trajectory" => trajectory,
        "story_world_state_transitions" => Support.plain_objects(transitions),
        "event_reaction_relationships" => reaction_links(world, entries),
        "value_state_deltas" => value_deltas(trajectory)
      },
      trajectories: %{
        "measurements" => Support.measurement_trajectory(entries, @keys),
        "character_conditions" => trajectory,
        "semantics" => "presentation_relative_measurements_plus_explicit_story_world_state"
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(entries),
      next_investigations: next_investigations(diagnoses),
      limitations: [
        "Condition labels describe screenplay-supported state change; they do not claim a universal human emotion or diagnose a person.",
        "Measurement answers are model-estimated interpretations over supplied excerpts unless separately calibrated against rights-cleared human reading data.",
        "A stable emotional condition can be dramatically intentional. Repetition is surfaced as an investigation candidate, never as an automatic defect.",
        "StoryWorld transitions are included only when caller-supplied records support them; absent state remains unknown."
      ],
      metadata: %{
        "family_version" => 1,
        "intent" => Model.plain(Keyword.get(opts, :intent, %{})),
        "condition_dimensions" => Enum.map(@direction_keys, &to_string/1)
      }
    }
  end

  defp trajectory_point(entry) do
    directions = Map.new(@direction_keys, &{to_string(&1), Support.choice(entry, &1)})

    %{
      "scene_id" => entry["scene_id"],
      "directions" => directions,
      "anticipated_gain" => Support.status(entry, :anticipated_gain),
      "anticipated_loss" => Support.status(entry, :anticipated_loss),
      "reaction_consequence" => Support.status(entry, :reaction_consequence),
      "behavioral_consequence" => Support.status(entry, :behavioral_consequence),
      "reversal" => Support.status(entry, :reversal),
      "measurement_ids" => get_in(entry, ["provenance", "measurement_ids"]) || []
    }
  end

  defp relevant_transitions(world, subject) do
    character = character(subject)

    world.state_transitions
    |> Map.values()
    |> Enum.filter(fn transition ->
      is_nil(character) or Support.character_in_value?(transition.subject, character)
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp character(%{"character" => value}), do: value
  defp character(%{"character_id" => value}), do: value
  defp character(value) when is_binary(value), do: value
  defp character(_), do: nil

  defp reaction_links(world, entries) do
    entries
    |> Enum.filter(fn entry ->
      Support.supported?(entry, :reaction_consequence) or
        Support.supported?(entry, :behavioral_consequence)
    end)
    |> Enum.map(fn entry ->
      event_ids = Support.event_ids_for_scene(world, entry["scene_id"])

      %{
        "scene_id" => entry["scene_id"],
        "event_ids" => event_ids,
        "causal_outgoing" =>
          world
          |> Support.outgoing_edges(event_ids)
          |> Enum.map(&Model.plain/1),
        "reaction_consequence" => Support.status(entry, :reaction_consequence),
        "behavioral_consequence" => Support.status(entry, :behavioral_consequence)
      }
    end)
  end

  defp value_deltas(trajectory) do
    Enum.map(trajectory, fn point ->
      %{
        "scene_id" => point["scene_id"],
        "changed_dimensions" =>
          point["directions"]
          |> Enum.filter(fn {_key, value} -> value in ["improves", "worsens", "mixed"] end)
          |> Map.new()
      }
    end)
  end

  defp diagnoses(entries) do
    support = measurement_ids(entries)

    []
    |> maybe_diag(
      Enum.any?(entries, fn entry ->
        Support.supported?(entry, :major_event) and
          Support.not_supported?(entry, :reaction_consequence) and
          Support.not_supported?(entry, :behavioral_consequence)
      end),
      Support.diagnosis(
        "emotional.major_event_without_visible_consequence_candidate",
        "A major event may not produce a visible emotional or behavioral consequence in the selected material.",
        "A major-event signal is supported while both reaction and behavioral-consequence signals are unsupported.",
        support,
        limitations: [
          "Delayed, concealed, or intentionally withheld reaction can be dramatically useful."
        ]
      )
    )
    |> maybe_diag(
      Enum.any?(entries, fn entry ->
        Support.supported?(entry, :reversal) and Support.not_supported?(entry, :reversal_prepared)
      end),
      Support.diagnosis(
        "emotional.reversal_preparation_candidate",
        "An emotional or value reversal may arrive without visible preparation in the supplied scope.",
        "Reversal is supported while preparation is unsupported in at least one measured scene.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :declared_feeling_without_behavioral_change),
      Support.diagnosis(
        "emotional.declared_feeling_without_behavior_candidate",
        "Declared feeling may be carrying work that is not yet reflected in behavior, choice, or consequence.",
        "The dedicated declaration-without-behavior measurement is supported.",
        support,
        limitations: [
          "Verbal self-description can itself be action, deception, avoidance, or characterization."
        ]
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :value_action_inconsistency),
      Support.diagnosis(
        "emotional.value_action_inconsistency_candidate",
        "A stated or established value may not line up with a later action in the supplied material.",
        "The value/action inconsistency measurement is supported.",
        support,
        uncertainty: "high",
        limitations: [
          "Contradiction, hypocrisy, ambivalence, and self-deception can be intentional character behavior."
        ]
      )
    )
    |> Enum.sort_by(& &1["id"])
  end

  defp uncertainty(entries) do
    for entry <- entries,
        key <- @keys,
        Support.status(entry, key) in ["uncertain", "insufficient_evidence", "unavailable"] do
      %{
        "scene_id" => entry["scene_id"],
        "measurement" => to_string(key),
        "status" => Support.status(entry, key)
      }
    end
  end

  defp next_investigations(diagnoses) do
    Enum.map(diagnoses, fn diagnosis ->
      case diagnosis["id"] do
        "emotional.major_event_without_visible_consequence_candidate" ->
          "Trace the next visible choice, tactic, relationship move, practical behavior, or delayed reaction after the cited event before deciding the reaction is missing."

        "emotional.reversal_preparation_candidate" ->
          "Inspect earlier behavior and state transitions for pressure, contradiction, or choice that could prepare the reversal without over-explaining it."

        "emotional.value_action_inconsistency_candidate" ->
          "Compare the character's established value, available knowledge, pressure, and chosen action; decide whether the contradiction is intentional or unsupported."

        _ ->
          "Compare explicit behavior and consequences with dialogue that names the character's emotional condition."
      end
    end)
    |> Enum.uniq()
  end

  defp measurement_ids(entries) do
    entries
    |> Enum.flat_map(&(get_in(&1, ["provenance", "measurement_ids"]) || []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp status(entries),
    do: if(Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")

  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
end
