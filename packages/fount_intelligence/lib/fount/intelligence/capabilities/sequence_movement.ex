defmodule Fount.Intelligence.Capabilities.SequenceMovement do
  @moduledoc "Pure Phase-7 sequence movement reasoning with explicit presentation and partial story-time views."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Intelligence.Temporal
  alias Fount.Screenplay.Model

  @keys ~w(objective_active objective_progress constraint_escalation stakes_escalation knowledge_change relationship_change choice_change tactic_shift reversal local_outcome repeated_function handoff_pressure)a
  @movement_keys ~w(objective_progress constraint_escalation stakes_escalation knowledge_change relationship_change choice_change tactic_shift reversal local_outcome)a

  def analyze(world, subject, entries, opts \\ []) do
    scene_ids = scene_ids(subject, entries)
    event_ids = Enum.flat_map(scene_ids, &Support.event_ids_for_scene(world, &1)) |> Enum.uniq()
    presentation = Temporal.sequence_view(world, event_ids, ordering: :presentation)
    story_time = Temporal.sequence_view(world, event_ids, ordering: :story_time)
    vector = Enum.map(scene_ids, &scene_vector(world, &1, entries))
    diagnoses = diagnoses(vector)

    %Result{
      family: "sequence_movement",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: result_status(entries),
      evidence:
        Support.merge_evidence([
          Support.measurement_evidence(entries),
          Support.evidence(sequence_objects(world, scene_ids, event_ids))
        ]),
      measurements: %{
        "keys" => Enum.map(@keys, &to_string/1),
        "entries" => entries
      },
      derived_state: %{
        "sequence_state_vector" => vector,
        "movement_density" => movement_density(vector),
        "escalation_dimensions" => escalation_dimensions(vector),
        "reversals" => Enum.filter(vector, &supported_in?(&1, "reversal")),
        "local_outcome" => List.last(vector),
        "next_sequence_handoff" => List.last(vector) |> handoff()
      },
      trajectories: %{
        "presentation" => presentation,
        "story_time" => story_time,
        "measurement" => Support.measurement_trajectory(entries, @keys)
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(entries, story_time),
      next_investigations: next_investigations(diagnoses, story_time),
      limitations: [
        "Sequence movement is decomposed into objective, constraint, stakes, knowledge, relationship, choice, tactic, reversal, outcome, and handoff evidence rather than a universal momentum score.",
        "Presentation order and partial diegetic story time are reported separately; screenplay adjacency never manufactures chronology.",
        "Repeated function and stillness are revision candidates only. Intentional repetition, ritual, dread, comedy, contemplation, or delay can be dramatically useful.",
        "StoryWorld state is frozen caller-supplied derived data; absent events, transitions, beats, and commitments remain unknown."
      ],
      metadata: %{
        "family_version" => 1,
        "scene_count" => length(scene_ids),
        "event_count" => length(event_ids),
        "options" => safe_options(opts)
      }
    }
  end

  defp scene_vector(world, scene_id, entries) do
    relevant = Support.relevant_entries(entries, scene_id)
    event_ids = Support.event_ids_for_scene(world, scene_id)

    beats =
      world.beats
      |> Map.values()
      |> Enum.filter(&(&1.scene_id == scene_id))
      |> Enum.sort_by(& &1.id)

    transitions =
      world.state_transitions
      |> Map.values()
      |> Enum.filter(&(&1.event_id in event_ids))
      |> Enum.sort_by(& &1.id)

    interactions =
      world.interactions
      |> Map.values()
      |> Enum.filter(&(&1.event_id in event_ids))
      |> Enum.sort_by(& &1.id)

    answers = Map.new(@keys, &{to_string(&1), first_answer(relevant, &1)})

    %{
      "scene_id" => scene_id,
      "event_ids" => event_ids,
      "measurements" => answers,
      "measurement_ids" =>
        relevant
        |> Enum.flat_map(&(get_in(&1, ["provenance", "measurement_ids"]) || []))
        |> Enum.uniq()
        |> Enum.sort(),
      "recorded" => %{
        "beat_ids" => Support.source_ids(beats),
        "state_transition_ids" => Support.source_ids(transitions),
        "interaction_ids" => Support.source_ids(interactions),
        "objectives" => Enum.map(beats, &Model.plain(&1.objective)) |> Enum.reject(&is_nil/1),
        "outcomes" => Enum.map(beats, &Model.plain(&1.outcome)) |> Enum.reject(&is_nil/1),
        "information_changes" =>
          Enum.map(beats, &Model.plain(&1.information_change)) |> Enum.reject(&is_nil/1),
        "relationship_deltas" =>
          Enum.map(beats, &Model.plain(&1.relationship_delta)) |> Enum.reject(&is_nil/1),
        "value_deltas" => Enum.map(beats, &Model.plain(&1.value_delta)) |> Enum.reject(&is_nil/1)
      },
      "movement_components" => movement_components(relevant, beats, transitions, interactions),
      "handoff" => %{
        "measurement" => first_answer(relevant, :handoff_pressure),
        "downstream_event_ids" =>
          event_ids |> Enum.flat_map(&Fount.Intelligence.StoryWorld.causal_descendants(world, &1)) |> Enum.uniq() |> Enum.sort()
      }
    }
  end

  defp movement_components(entries, beats, transitions, interactions) do
    measured = Enum.filter(@movement_keys, &Support.any_supported?(entries, &1)) |> Enum.map(&to_string/1)

    recorded =
      []
      |> maybe_component(transitions != [], "recorded_state_change")
      |> maybe_component(Enum.any?(beats, &(not is_nil(&1.outcome))), "recorded_outcome")
      |> maybe_component(Enum.any?(beats, &(not is_nil(&1.information_change))), "recorded_information_change")
      |> maybe_component(Enum.any?(beats, &(not is_nil(&1.relationship_delta))), "recorded_relationship_change")
      |> maybe_component(Enum.any?(interactions, &(&1.tactics != [])), "recorded_interaction_tactics")

    Enum.uniq(measured ++ recorded)
  end

  defp movement_density(vector) do
    moving = Enum.count(vector, &(&1["movement_components"] != []))

    %{
      "scene_count" => length(vector),
      "scenes_with_recorded_or_measured_change" => moving,
      "scenes_without_recorded_or_measured_change" => max(length(vector) - moving, 0),
      "descriptive_fraction" => if(vector == [], do: nil, else: moving / length(vector))
    }
  end

  defp escalation_dimensions(vector) do
    for key <- ~w(constraint_escalation stakes_escalation knowledge_change relationship_change choice_change tactic_shift),
        scenes = Enum.filter(vector, &supported_in?(&1, key)),
        scenes != [],
        into: %{} do
      {key, Enum.map(scenes, & &1["scene_id"])}
    end
  end

  defp diagnoses(vector) do
    support = Enum.flat_map(vector, &measurement_ids_for_vector/1) |> Enum.uniq() |> Enum.sort()
    repeated = Enum.filter(vector, &supported_in?(&1, "repeated_function"))
    no_move = Enum.filter(vector, &(&1["movement_components"] == []))
    final = List.last(vector)

    []
    |> maybe_diag(
      length(repeated) >= 2,
      Support.diagnosis(
        "sequence.repeated_function_candidate",
        "Several scenes may repeat substantially the same dramatic function without a new consequence.",
        "Repeated-function measurement is supported in at least two selected scenes.",
        support,
        limitations: ["Repetition can be intentional; compare objective, cost, strategy, information, relationship, and consequence before cutting or compressing anything."]
      )
    )
    |> maybe_diag(
      length(vector) >= 2 and length(no_move) >= 2,
      Support.diagnosis(
        "sequence.state_stasis_candidate",
        "A run of selected scenes may show limited recorded or measured movement.",
        "At least two selected scenes have neither supported movement measurements nor frozen StoryWorld state/beat changes.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      not is_nil(final) and not supported_in?(final, "handoff_pressure") and
        get_in(final, ["handoff", "downstream_event_ids"]) == [],
      Support.diagnosis(
        "sequence.weak_handoff_candidate",
        "The selected sequence may end without a legible downstream task, consequence, question, threat, or choice.",
        "The final selected scene lacks measured handoff pressure and has no recorded causal descendants in the supplied StoryWorld.",
        support,
        uncertainty: "high"
      )
    )
    |> Enum.sort_by(& &1["id"])
  end

  defp uncertainty(entries, story_time) do
    measured =
      for entry <- entries,
          key <- @keys,
          Support.status(entry, key) in ["uncertain", "insufficient_evidence", "unavailable"] do
        %{"scene_id" => entry["scene_id"], "measurement" => to_string(key), "status" => Support.status(entry, key)}
      end

    chronology =
      case story_time do
        %{"relations" => relations} ->
          Enum.filter(relations, fn item ->
            relation = item["relation"]
            relation == "unknown" or match?(%{"status" => status} when status in ["ambiguous", "contradiction"], relation)
          end)
          |> Enum.map(&Map.put(&1, "kind", "story_time_uncertainty"))

        _ ->
          []
      end

    measured ++ chronology
  end

  defp next_investigations(diagnoses, story_time) do
    base =
      Enum.map(diagnoses, fn diagnosis ->
        case diagnosis["id"] do
          "sequence.repeated_function_candidate" ->
            "Compare each selected scene's objective, tactic, cost, information, relationship delta, choice, outcome, and handoff before combining or removing scenes."

          "sequence.weak_handoff_candidate" ->
            "Inspect the last scene exit and next scene entry for a consequence, choice, threat, question, or task that should bridge them."

          _ ->
            "Compare the sequence state vector scene by scene and identify which dimension should change, remain still, or reverse by intent."
        end
      end)

    if story_time_has_non_linear?(story_time),
      do: Enum.uniq(base ++ ["Compare movement in reader-visible presentation order with known diegetic relations so a flashback or intercut is not diagnosed as chronological stasis."]),
      else: Enum.uniq(base)
  end

  defp story_time_has_non_linear?(%{"relations" => relations}) do
    Enum.any?(relations, fn item ->
      match?(%{"status" => "known", "relations" => rels} when is_list(rels), item["relation"]) and
        "after" in item["relation"]["relations"]
    end)
  end

  defp story_time_has_non_linear?(_), do: false

  defp sequence_objects(world, scene_ids, event_ids) do
    beats = world.beats |> Map.values() |> Enum.filter(&(&1.scene_id in scene_ids))
    transitions = world.state_transitions |> Map.values() |> Enum.filter(&(&1.event_id in event_ids))
    interactions = world.interactions |> Map.values() |> Enum.filter(&(&1.event_id in event_ids))
    beats ++ transitions ++ interactions
  end

  defp scene_ids(%{"scene_ids" => scene_ids}, _entries) when is_list(scene_ids), do: clean_scene_ids(scene_ids)
  defp scene_ids(%{"scenes" => scene_ids}, _entries) when is_list(scene_ids), do: clean_scene_ids(scene_ids)
  defp scene_ids(_subject, entries), do: Support.measurement_scenes(entries)
  defp clean_scene_ids(ids), do: ids |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.uniq()

  defp first_answer([], _key), do: nil
  defp first_answer(entries, key), do: Support.answer(hd(entries), key)

  defp supported_in?(vector, key),
    do: match?(%{"status" => "supported"}, get_in(vector, ["measurements", key]))

  defp handoff(nil), do: nil
  defp handoff(vector), do: vector["handoff"]

  defp measurement_ids_for_vector(vector), do: vector["measurement_ids"] || []
  defp maybe_component(list, true, component), do: list ++ [component]
  defp maybe_component(list, false, _component), do: list
  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list

  defp result_status(entries),
    do: if(Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")

  defp safe_options(_opts), do: %{}
end
