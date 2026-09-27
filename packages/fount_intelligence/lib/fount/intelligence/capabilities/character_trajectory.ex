defmodule Fount.Intelligence.Capabilities.CharacterTrajectory do
  @moduledoc "Pure Phase-6 character trajectory reasoning with separate diegetic and reader-visible presentation views."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Intelligence.StoryWorld
  alias Fount.Screenplay.Model

  @keys ~w(active_goal belief_change knowledge_change tactic_change commitment_change relationship_change value_change adapts_after_failure choice_reveals_character repeated_defense arc_pattern)a
  @decision_kinds ~w(decision choice refusal commitment)
  @failure_kinds ~w(failure defeat setback rejection loss)

  def analyze(world, subject, measurement_entries, opts \\ []) do
    character = character(subject)
    goals = character_goals(world, character)
    assertions = character_assertions(world, character)
    commitments = character_commitments(world, character)
    transitions = character_transitions(world, character)
    interactions = character_interactions(world, character)
    events = character_events(world, character)
    decisions = Enum.filter(events, &(&1.kind in @decision_kinds))
    failures = Enum.filter(events, &(&1.kind in @failure_kinds))
    relationship_transitions = Enum.filter(transitions, &Support.relationship_transition?/1)
    trajectory = Support.story_order_links(world, transitions, & &1.event_id)
    presentation_measurements = Support.measurement_trajectory(measurement_entries, @keys)
    arc_hypotheses = arc_hypotheses(measurement_entries)
    diagnoses = diagnoses(character, measurement_entries, failures, transitions, opts)
    source_objects = goals ++ assertions ++ commitments ++ transitions ++ interactions ++ events

    %Result{
      family: "character_trajectory",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: result_status(measurement_entries),
      evidence: Support.merge_evidence([Support.evidence(source_objects), Support.measurement_evidence(measurement_entries)]),
      measurements: %{
        "keys" => Enum.map(@keys, &to_string/1),
        "entries" => measurement_entries
      },
      derived_state: %{
        "character" => Model.plain(character),
        "goals" => Support.plain_objects(goals),
        "belief_and_knowledge_assertions" => Support.plain_objects(assertions),
        "commitments" => Support.plain_objects(commitments),
        "state_transitions" => Support.plain_objects(transitions),
        "relationship_transitions" => Support.plain_objects(relationship_transitions),
        "decision_map" => decision_map(world, decisions),
        "goal_pursuit_map" => goal_pursuit_map(goals, interactions, measurement_entries),
        "arc_hypotheses" => arc_hypotheses
      },
      trajectories: %{
        "reader_visible_presentation" => presentation_measurements,
        "diegetic_state_changes" => trajectory,
        "presentation_vs_story_time" => trajectory,
        "non_linear_presentation" => trajectory["non_linear_presentation"]
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(measurement_entries, trajectory),
      next_investigations: next_investigations(diagnoses, trajectory),
      limitations: [
        "No transformation arc is required. Steadfast, tragic, corruption, revelation, cyclical, ensemble, deliberately static, mixed, and unclear patterns are all legal outcomes.",
        "Reader-visible trajectory follows screenplay presentation measurements; diegetic state change follows only explicit StoryWorld chronology when established.",
        "Unknown or ambiguous story-time relationships remain unknown rather than inheriting scene order.",
        "Arc-pattern choices are uncalibrated model estimates and remain hypotheses, not canonical character facts."
      ],
      metadata: %{"family_version" => 1, "options" => safe_options(opts)}
    }
  end

  defp character_goals(world, character) do
    world.goals
    |> Map.values()
    |> Enum.filter(&(is_nil(character) or Support.subject_equal?(&1.owner, character)))
    |> Enum.sort_by(& &1.id)
  end

  defp character_assertions(world, character) do
    world.assertions
    |> Map.values()
    |> Enum.filter(fn assertion ->
      is_nil(character) or Support.subject_equal?(assertion.epistemic_owner, character) or
        Support.character_in_value?(assertion.subject, character)
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp character_commitments(world, character) do
    world.commitments
    |> Map.values()
    |> Enum.filter(fn commitment ->
      is_nil(character) or Support.subject_equal?(commitment.from, character) or Support.subject_equal?(commitment.to, character)
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp character_transitions(world, character) do
    world.state_transitions
    |> Map.values()
    |> Enum.filter(&(is_nil(character) or Support.character_in_value?(&1.subject, character)))
    |> Enum.sort_by(&Support.transition_presentation_key(world, &1))
  end

  defp character_interactions(world, character) do
    world.interactions
    |> Map.values()
    |> Enum.filter(&(is_nil(character) or Support.character_in_value?(&1.participants, character)))
    |> Enum.sort_by(&Support.event_presentation_key(world, &1.event_id))
  end

  defp character_events(world, character) do
    world.events
    |> Map.values()
    |> Enum.filter(&(is_nil(character) or Support.event_has_character?(&1, character)))
    |> Enum.sort_by(&Support.event_presentation_key(world, &1.id))
  end

  defp decision_map(world, decisions) do
    Enum.map(decisions, fn event ->
      %{
        "decision" => Model.plain(event),
        "causal_descendant_ids" => StoryWorld.causal_descendants(world, event.id),
        "counterfactual_support" => Model.plain(StoryWorld.counterfactual_remove(world, [event.id]))
      }
    end)
  end

  defp goal_pursuit_map(goals, interactions, entries) do
    %{
      "goals" => Enum.map(goals, &%{"id" => &1.id, "description" => &1.description, "level" => &1.level, "status" => &1.status, "active_at" => Model.plain(&1.active_at)}),
      "interaction_objectives" =>
        Enum.map(interactions, &%{"interaction_id" => &1.id, "event_id" => &1.event_id, "objectives" => Model.plain(&1.objectives), "tactics" => Model.plain(&1.tactics)}),
      "presentation_measurements" =>
        Enum.map(entries, &%{"scene_id" => &1["scene_id"], "active_goal" => Support.answer(&1, :active_goal), "tactic_change" => Support.answer(&1, :tactic_change)})
    }
  end

  defp arc_hypotheses(entries) do
    entries
    |> Enum.flat_map(fn entry ->
      case Support.choice(entry, :arc_pattern) do
        nil -> []
        choice -> [%{"pattern" => choice, "scene_id" => entry["scene_id"], "answer" => Support.answer(entry, :arc_pattern)}]
      end
    end)
    |> Enum.group_by(& &1["pattern"])
    |> Enum.map(fn {pattern, items} ->
      %{
        "pattern" => pattern,
        "supporting_scene_ids" => items |> Enum.map(& &1["scene_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
        "support_count" => length(items),
        "status" => "hypothesis"
      }
    end)
    |> Enum.sort_by(&{-&1["support_count"], &1["pattern"]})
  end

  defp diagnoses(character, entries, failures, transitions, opts) do
    ids = measurement_ids(entries) ++ Enum.map(transitions, & &1.id)
    intent = Keyword.get(opts, :intent, %{})
    intended_change = intent_value(intent, "character_change")

    []
    |> maybe_diag(
      failures != [] and entries != [] and Support.all_not_supported?(entries, :adapts_after_failure),
      Support.diagnosis(
        "character.adaptation_gap_candidate",
        "The character may repeat a response after recorded failure without a visible adaptation.",
        "Failure/setback records exist while adaptation-after-failure measurements do not establish a changed response.",
        ids ++ Enum.map(failures, & &1.id),
        limitations: ["Repetition can be an intentional defense pattern or tragic design."]
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :repeated_defense),
      Support.diagnosis(
        "character.repeated_defense_pattern",
        "A recurring defensive response appears across the selected trajectory.",
        "At least one scene-level repeated-defense measurement is supported.",
        ids,
        limitations: ["A repeated defense can be a meaningful character pattern rather than a defect."]
      )
    )
    |> maybe_diag(
      intended_change in ["change", "transform", "adapt"] and transitions == [] and
        Support.all_not_supported?(entries, :belief_change) and Support.all_not_supported?(entries, :value_change),
      Support.diagnosis(
        "character.intent_change_gap",
        "The current evidence may not yet establish the character change named in writer intent.",
        "The request states a change intent while neither frozen state transitions nor measured belief/value change are established.",
        ids,
        uncertainty: "high"
      )
    )
    |> Enum.sort_by(& &1["id"])
    |> Enum.map(&Map.put(&1, "subject", Model.plain(character)))
  end

  defp uncertainty(entries, trajectory) do
    measurement =
      for entry <- entries,
          key <- @keys,
          Support.status(entry, key) in ["uncertain", "insufficient_evidence", "unavailable"] do
        %{"scene_id" => entry["scene_id"], "measurement" => to_string(key), "status" => Support.status(entry, key)}
      end

    chronology =
      trajectory["adjacent_story_time_relations"]
      |> Enum.filter(fn link ->
        relation = link["story_time_relation"]
        relation == "unknown" or match?(%{"status" => status} when status in ["ambiguous", "contradiction"], relation)
      end)
      |> Enum.map(&Map.put(&1, "kind", "story_time_uncertainty"))

    measurement ++ chronology
  end

  defp next_investigations(diagnoses, trajectory) do
    base =
      Enum.map(diagnoses, fn diagnosis ->
        case diagnosis["id"] do
          "character.adaptation_gap_candidate" -> "Compare the failure, next tactic, and next consequential decision before rewriting motivation."
          "character.repeated_defense_pattern" -> "Decide whether the repeated defense is meant to persist, escalate, fracture, or finally fail."
          "character.intent_change_gap" -> "Locate the intended transition point and test belief, value, commitment, and relationship evidence separately."
          _ -> "Inspect cited evidence and competing arc hypotheses before selecting a change."
        end
      end)

    if trajectory["non_linear_presentation"],
      do: Enum.uniq(base ++ ["Compare reader-visible presentation order against established story-time order before diagnosing an arc discontinuity."]),
      else: Enum.uniq(base)
  end

  defp character(%{"character" => character}), do: character
  defp character(%{"character_id" => character}), do: character
  defp character(character) when is_binary(character), do: character
  defp character(_), do: nil

  defp measurement_ids(entries) do
    entries
    |> Enum.flat_map(&get_in(&1, ["provenance", "measurement_ids"]) || [])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp intent_value(intent, key) when is_map(intent), do: Map.get(intent, key)
  defp intent_value(_, _), do: nil
  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
  defp result_status(entries), do: if(entries != [] and Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")
  defp safe_options(opts), do: %{"intent" => Model.plain(Keyword.get(opts, :intent, %{}))}
end
