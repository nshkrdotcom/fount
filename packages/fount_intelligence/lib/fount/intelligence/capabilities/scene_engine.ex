defmodule Fount.Intelligence.Capabilities.SceneEngine do
  @moduledoc "Pure Phase-6 scene-engine reasoning over a frozen StoryWorld plus acquired scene measurements."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Intelligence.StoryWorld
  alias Fount.Screenplay.Model

  @keys ~w(objective opposition stakes urgency tactic tactic_shift reveal decision consequence value_delta relationship_delta preamble_candidate linger_candidate)a

  def analyze(world, subject, measurement_entries, opts \\ []) do
    scene_ids = scene_ids(subject, measurement_entries)
    scenes = Enum.map(scene_ids, &scene_state(world, &1, measurement_entries))
    diagnoses = scenes |> Enum.flat_map(&diagnoses/1) |> Enum.sort_by(& &1["id"])
    objects = source_objects(world, scene_ids)

    %Result{
      family: "scene_engine",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: result_status(measurement_entries),
      evidence:
        Support.merge_evidence([
          Support.evidence(objects),
          Support.measurement_evidence(measurement_entries)
        ]),
      measurements: %{
        "keys" => Enum.map(@keys, &to_string/1),
        "entries" => measurement_entries
      },
      derived_state: %{"scenes" => scenes},
      trajectories: %{
        "presentation" =>
          Enum.map(scenes, &Map.take(&1, ~w(scene_id event_id entry_exit_delta handoff_pressure))),
        "story_time" => scene_story_links(world, scene_ids)
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(measurement_entries, scene_ids),
      next_investigations: next_investigations(diagnoses),
      limitations: [
        "Scene measurements are uncalibrated model estimates over supplied excerpts; they are not universal screenplay rules.",
        "Entry/exit economy is surfaced as a revision candidate, never an instruction to cut material.",
        "Causal descendants and state changes come only from the supplied frozen StoryWorld; absent records remain unknown.",
        "Presentation order is not treated as diegetic chronology."
      ],
      metadata: %{
        "family_version" => 1,
        "scene_count" => length(scene_ids),
        "options" => safe_options(opts)
      }
    }
  end

  defp scene_state(world, scene_id, entries) do
    event_id = Support.event_id_for_scene(scene_id)
    event_ids = Support.event_ids_for_scene(world, scene_id)
    relevant = Support.relevant_entries(entries, scene_id)

    beats =
      world.beats
      |> Map.values()
      |> Enum.filter(&(&1.scene_id == scene_id))
      |> Enum.sort_by(& &1.id)

    interactions =
      world.interactions
      |> Map.values()
      |> Enum.filter(&(&1.event_id == event_id))
      |> Enum.sort_by(& &1.id)

    transitions =
      world.state_transitions
      |> Map.values()
      |> Enum.filter(&(&1.event_id in event_ids))
      |> Enum.sort_by(& &1.id)

    goals =
      world.goals
      |> Map.values()
      |> Enum.filter(&Support.active_at?(&1.active_at, event_id))
      |> Enum.sort_by(& &1.id)

    outgoing = Support.outgoing_edges(world, event_ids)

    descendants =
      event_ids
      |> Enum.flat_map(&StoryWorld.causal_descendants(world, &1))
      |> Enum.uniq()
      |> Enum.sort()

    source_state = %{
      "objective_records" =>
        Enum.reject(Enum.map(beats, & &1.objective), &is_nil/1) ++
          Enum.map(goals, & &1.description),
      "tactic_records" =>
        Enum.flat_map(beats, &List.wrap(&1.tactic)) ++ Enum.flat_map(interactions, & &1.tactics),
      "information_changes" => Enum.map(beats, & &1.information_change) |> Enum.reject(&is_nil/1),
      "outcomes" => Enum.map(beats, & &1.outcome) |> Enum.reject(&is_nil/1),
      "state_transition_ids" => Support.source_ids(transitions),
      "causal_edge_ids" => Support.source_ids(outgoing),
      "causal_descendant_ids" => descendants,
      "interaction_ids" => Support.source_ids(interactions)
    }

    measurements = Map.new(@keys, &{to_string(&1), scene_answer(relevant, &1)})

    %{
      "scene_id" => scene_id,
      "event_id" => event_id,
      "event_ids" => event_ids,
      "measurements" => measurements,
      "source_state" => source_state,
      "entry_exit_delta" => entry_exit_delta(transitions, beats),
      "turn_candidates" => turn_candidates(relevant, beats),
      "surrounding_sequence_contribution" =>
        surrounding_sequence_contribution(world, event_ids, transitions, outgoing, descendants),
      "handoff_pressure" => handoff_pressure(relevant, descendants, transitions),
      "counterfactual_support" => Model.plain(StoryWorld.counterfactual_remove(world, event_ids)),
      "evidence_ids" =>
        Support.merge_evidence([
          Support.evidence(beats ++ interactions ++ transitions ++ goals ++ outgoing),
          Support.measurement_evidence(relevant)
        ])
        |> Enum.map(&(&1["id"] || &1["evidence_id"]))
        |> Enum.reject(&is_nil/1)
    }
  end

  defp scene_answer([], _key), do: nil
  defp scene_answer(entries, key), do: entries |> List.first() |> Support.answer(key)

  defp entry_exit_delta(transitions, beats) do
    %{
      "state_transitions" =>
        Enum.map(transitions, fn transition ->
          %{
            "id" => transition.id,
            "subject" => Model.plain(transition.subject),
            "attribute" => transition.attribute,
            "from" => Model.plain(transition.from),
            "to" => Model.plain(transition.to)
          }
        end),
      "value_deltas" => Enum.map(beats, & &1.value_delta) |> Enum.reject(&is_nil/1),
      "relationship_deltas" => Enum.map(beats, & &1.relationship_delta) |> Enum.reject(&is_nil/1)
    }
  end

  defp turn_candidates(entries, beats) do
    measured =
      for key <- [:tactic_shift, :reveal, :decision],
          answer = first_answer(entries, key),
          match?(%{"status" => status} when status in ["supported", "uncertain"], answer) do
        %{"source" => "measurement", "kind" => to_string(key), "answer" => answer}
      end

    recorded =
      beats
      |> Enum.flat_map(fn beat ->
        [
          if(not is_nil(beat.information_change),
            do: %{
              "source" => "story_world",
              "kind" => "information_change",
              "beat_id" => beat.id,
              "value" => Model.plain(beat.information_change)
            }
          ),
          if(not is_nil(beat.transition_reason),
            do: %{
              "source" => "story_world",
              "kind" => "transition_reason",
              "beat_id" => beat.id,
              "value" => Model.plain(beat.transition_reason)
            }
          )
        ]
      end)
      |> Enum.reject(&is_nil/1)

    measured ++ recorded
  end

  defp surrounding_sequence_contribution(world, event_ids, transitions, outgoing, descendants) do
    incoming = Support.incoming_edges(world, event_ids)

    %{
      "incoming_causal_edge_ids" => Support.source_ids(incoming),
      "outgoing_causal_edge_ids" => Support.source_ids(outgoing),
      "downstream_event_ids" => descendants,
      "recorded_state_change_count" => length(transitions),
      "counterfactual_support" => Model.plain(StoryWorld.counterfactual_remove(world, event_ids))
    }
  end

  defp handoff_pressure(entries, descendants, transitions) do
    %{
      "consequence_measurement" => first_answer(entries, :consequence),
      "has_recorded_downstream_causal_reach" => descendants != [],
      "has_recorded_local_state_change" => transitions != []
    }
  end

  defp first_answer([], _key), do: nil
  defp first_answer(entries, key), do: Support.answer(hd(entries), key)

  defp diagnoses(scene) do
    m = scene["measurements"]
    state = scene["source_state"]
    support = scene["evidence_ids"]

    []
    |> maybe_diag(
      unclear_objective?(m, state),
      Support.diagnosis(
        "scene.unclear_objective:#{scene["scene_id"]}",
        "The scene objective may be hard to read.",
        "Neither the measurement nor frozen objective/goal records establish a clear active objective.",
        support
      )
    )
    |> maybe_diag(
      unclear_consequence?(m, state),
      Support.diagnosis(
        "scene.weak_or_unclear_consequence:#{scene["scene_id"]}",
        "The scene may not establish a consequential exit change.",
        "No measured consequence, downstream causal reach, or recorded state transition is currently established.",
        support
      )
    )
    |> maybe_diag(
      repeated_tactic?(m),
      Support.diagnosis(
        "scene.repeated_tactic:#{scene["scene_id"]}",
        "The scene may hold the same tactic after resistance.",
        "A tactic is visible but a responsive tactic shift is not established.",
        support,
        limitations: [
          "Repetition may be intentional rhythm, pressure, comedy, or characterization."
        ]
      )
    )
    |> maybe_diag(
      static_state?(m, state),
      Support.diagnosis(
        "scene.static_state_candidate:#{scene["scene_id"]}",
        "The scene may leave tracked state largely unchanged.",
        "No value/relationship delta or frozen state transition is currently established.",
        support,
        limitations: ["Intentional stillness is not a defect by itself."]
      )
    )
    |> maybe_diag(
      entry_exit_candidate?(m),
      Support.diagnosis(
        "scene.entry_exit_economy_candidate:#{scene["scene_id"]}",
        "The scene boundary may admit a later entry or earlier exit.",
        "At least one source-grounded entry/exit economy measurement crossed the review threshold.",
        support,
        limitations: ["This identifies a candidate for inspection, not a recommendation to cut."]
      )
    )
    |> maybe_diag(
      unsupported_turn?(m, state),
      Support.diagnosis(
        "scene.unsupported_turn_candidate:#{scene["scene_id"]}",
        "A local turn may not yet have an established downstream consequence.",
        "A decision, tactic shift, or reveal is measured while neither consequence nor downstream causal reach is established.",
        support
      )
    )
    |> maybe_diag(
      redundant_candidate?(m, state),
      Support.diagnosis(
        "scene.locally_functional_but_redundant_candidate:#{scene["scene_id"]}",
        "The scene may work locally while contributing little recorded downstream dependency.",
        "Objective/tactic evidence is present, but the current StoryWorld records show no downstream causal reach or tracked state change.",
        support,
        uncertainty: "high",
        limitations: [
          "Missing StoryWorld records can create this pattern; use scene-lift or sequence evidence before revising."
        ]
      )
    )
  end

  defp unclear_objective?(m, state),
    do: weak?(m["objective"]) and state["objective_records"] == []

  defp unclear_consequence?(m, state),
    do:
      weak?(m["consequence"]) and state["causal_descendant_ids"] == [] and
        state["state_transition_ids"] == []

  defp repeated_tactic?(m), do: supported?(m["tactic"]) and weak?(m["tactic_shift"])

  defp static_state?(m, state),
    do:
      weak?(m["value_delta"]) and weak?(m["relationship_delta"]) and
        state["state_transition_ids"] == []

  defp entry_exit_candidate?(m),
    do: supported?(m["preamble_candidate"]) or supported?(m["linger_candidate"])

  defp unsupported_turn?(m, state) do
    turn? = supported?(m["decision"]) or supported?(m["tactic_shift"]) or supported?(m["reveal"])
    turn? and weak?(m["consequence"]) and state["causal_descendant_ids"] == []
  end

  defp redundant_candidate?(m, state),
    do:
      locally_functional?(m) and state["causal_descendant_ids"] == [] and
        state["state_transition_ids"] == []

  defp scene_story_links(world, scene_ids) do
    events =
      scene_ids
      |> Enum.map(&Support.event_id_for_scene/1)
      |> Enum.map(fn event_id -> Map.get(world.events, event_id) end)
      |> Enum.reject(&is_nil/1)

    Support.story_order_links(world, events, & &1.id)
  end

  defp source_objects(world, scene_ids) do
    event_ids =
      scene_ids |> Enum.flat_map(&Support.event_ids_for_scene(world, &1)) |> MapSet.new()

    Enum.filter(Map.values(world.beats), fn beat ->
      is_binary(beat.scene_id) and
        MapSet.member?(event_ids, Support.event_id_for_scene(beat.scene_id))
    end) ++
      Enum.filter(Map.values(world.interactions), &MapSet.member?(event_ids, &1.event_id)) ++
      Enum.filter(Map.values(world.state_transitions), &MapSet.member?(event_ids, &1.event_id)) ++
      Enum.filter(Map.values(world.goals), fn goal ->
        Enum.any?(event_ids, &Support.active_at?(goal.active_at, &1))
      end) ++
      Enum.filter(Support.causal_edges(world), fn edge ->
        MapSet.member?(event_ids, edge.from) or MapSet.member?(event_ids, edge.to)
      end)
  end

  defp uncertainty(entries, scene_ids) do
    for scene_id <- scene_ids,
        entry <- Support.relevant_entries(entries, scene_id),
        key <- @keys,
        Support.status(entry, key) in ["uncertain", "insufficient_evidence", "unavailable"] do
      %{
        "scene_id" => scene_id,
        "measurement" => to_string(key),
        "status" => Support.status(entry, key)
      }
    end
  end

  defp next_investigations(diagnoses) do
    diagnoses
    |> Enum.map(fn diagnosis ->
      case diagnosis["id"] do
        "scene.unclear_objective:" <> _ ->
          "Compare the scene objective against character goals active before and after the scene."

        "scene.weak_or_unclear_consequence:" <> _ ->
          "Trace scene-lift and downstream dependency effects before changing the exit."

        "scene.entry_exit_economy_candidate:" <> _ ->
          "Audition later-entry and earlier-exit variants while protecting required setup and payoff."

        _ ->
          "Inspect the cited source and counterevidence before selecting a rewrite strategy."
      end
    end)
    |> Enum.uniq()
  end

  defp scene_ids(%{"scene_id" => scene_id}, _entries) when is_binary(scene_id), do: [scene_id]
  defp scene_ids(scene_id, _entries) when is_binary(scene_id), do: [scene_id]
  defp scene_ids(_subject, entries), do: Support.measurement_scenes(entries)

  defp weak?(nil), do: true

  defp weak?(%{"status" => status}),
    do: status in ["not_supported", "insufficient_evidence", "uncertain", "error"]

  defp weak?(_), do: true
  defp supported?(%{"status" => "supported"}), do: true
  defp supported?(_), do: false
  defp locally_functional?(m), do: supported?(m["objective"]) and supported?(m["tactic"])
  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list

  defp result_status(entries),
    do:
      if(entries != [] and Enum.all?(entries, &(&1["status"] == "complete")),
        do: "complete",
        else: "partial"
      )

  defp safe_options(opts),
    do:
      opts
      |> Keyword.take([:scope_id])
      |> Map.new(fn {k, v} -> {to_string(k), Model.plain(v)} end)
end
