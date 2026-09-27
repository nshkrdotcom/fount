defmodule Fount.Intelligence.Capabilities.RelationshipDynamics do
  @moduledoc "Pure Phase-6 relationship reasoning with directional state, interaction events, and separate presentation/story-time views."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Intelligence.StoryWorld
  alias Fount.Screenplay.Model

  @dimensions ~w(trust intimacy allegiance leverage status dependency attraction resentment obligation concealment knowledge_asymmetry)
  @keys ~w(trust_change intimacy_change allegiance_change leverage_change status_change dependency_change attraction_change resentment_change obligation_change concealment_change knowledge_asymmetry_change interaction_changes_relationship repetitive_negotiation betrayal_or_payoff_prepared)a

  def analyze(world, subject, measurement_entries, opts \\ []) do
    parties = parties(subject)
    transitions = relationship_transitions(world, parties)
    interactions = relationship_interactions(world, parties)
    commitments = relationship_commitments(world, parties)
    transition_trajectory = Support.story_order_links(world, transitions, & &1.event_id)
    interaction_trajectory = Support.story_order_links(world, interactions, & &1.event_id)
    dimensions = dimensions(transitions)
    diagnoses = diagnoses(parties, world, measurement_entries, transitions, interactions, commitments)
    source_objects = transitions ++ interactions ++ commitments ++ related_causal_edges(world, transitions, interactions, commitments)

    %Result{
      family: "relationship_dynamics",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: result_status(measurement_entries),
      evidence: Support.merge_evidence([Support.evidence(source_objects), Support.measurement_evidence(measurement_entries)]),
      measurements: %{
        "keys" => Enum.map(@keys, &to_string/1),
        "entries" => measurement_entries
      },
      derived_state: %{
        "parties" => Model.plain(parties),
        "dimensions" => dimensions,
        "directional_state" => directional_state(transitions),
        "interaction_events" => Support.plain_objects(interactions),
        "commitments_and_obligations" => Support.plain_objects(commitments),
        "transition_points" => transition_points(transitions),
        "asymmetric_state" => asymmetric_state(transitions)
      },
      trajectories: %{
        "reader_visible_presentation" => Support.measurement_trajectory(measurement_entries, @keys),
        "diegetic_relationship_changes" => transition_trajectory,
        "interaction_story_time" => interaction_trajectory,
        "non_linear_presentation" =>
          transition_trajectory["non_linear_presentation"] or interaction_trajectory["non_linear_presentation"]
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(measurement_entries, transition_trajectory),
      next_investigations: next_investigations(diagnoses, transition_trajectory),
      limitations: [
        "Relationship measurements are uncalibrated model estimates and do not define a preferred relationship direction.",
        "Directional state is preserved: A's trust/leverage toward B is not silently treated as B's state toward A.",
        "Presentation order and diegetic story time remain distinct; unknown chronology stays unknown.",
        "Stasis, reversal, betrayal, and payoff diagnoses are candidates for writer inspection, not prescriptions."
      ],
      metadata: %{"family_version" => 1, "options" => safe_options(opts)}
    }
  end

  defp relationship_transitions(world, parties) do
    world.state_transitions
    |> Map.values()
    |> Enum.filter(&(Support.relationship_transition?(&1) and relationship_subject_within?(&1.subject, parties)))
    |> Enum.sort_by(&Support.transition_presentation_key(world, &1))
  end

  defp relationship_interactions(world, parties) do
    world.interactions
    |> Map.values()
    |> Enum.filter(&interaction_within?(&1, parties))
    |> Enum.sort_by(&Support.event_presentation_key(world, &1.event_id))
  end

  defp relationship_commitments(world, parties) do
    world.commitments
    |> Map.values()
    |> Enum.filter(fn commitment ->
      parties == [] or
        (Enum.any?(parties, &Support.subject_equal?(commitment.from, &1)) and
           Enum.any?(parties, &Support.subject_equal?(commitment.to, &1)))
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp dimensions(transitions) do
    Map.new(@dimensions, fn dimension ->
      attribute = "relationship." <> dimension
      values = Enum.filter(transitions, &(&1.attribute == attribute))
      {dimension, Support.plain_objects(values)}
    end)
  end

  defp directional_state(transitions) do
    transitions
    |> Enum.group_by(fn transition ->
      {from, to} = relationship_direction(transition.subject)
      {from, to, transition.attribute}
    end)
    |> Enum.map(fn {{from, to, attribute}, values} ->
      last = List.last(values)
      %{
        "from" => from,
        "to" => to,
        "attribute" => attribute,
        "latest_recorded_value" => Model.plain(last.to),
        "transition_ids" => Enum.map(values, & &1.id)
      }
    end)
    |> Enum.sort_by(&{to_string(&1["from"]), to_string(&1["to"]), &1["attribute"]})
  end


  defp relationship_direction(subject) do
    case Model.plain(subject) do
      %{"from" => from, "to" => to} -> {from, to}
      [from, to | _] -> {from, to}
      _ -> {nil, nil}
    end
  end

  defp asymmetric_state(transitions) do
    transitions
    |> directional_state()
    |> Enum.group_by(& &1["attribute"])
    |> Enum.map(fn {attribute, states} ->
      %{
        "attribute" => attribute,
        "directions" => states,
        "asymmetric" =>
          states
          |> Enum.map(&Model.plain(&1["latest_recorded_value"]))
          |> Enum.uniq()
          |> length() > 1
      }
    end)
    |> Enum.sort_by(& &1["attribute"])
  end

  defp transition_points(transitions) do
    Enum.map(transitions, fn transition ->
      %{
        "id" => transition.id,
        "event_id" => transition.event_id,
        "dimension" => String.replace_prefix(transition.attribute, "relationship.", ""),
        "from" => Model.plain(transition.from),
        "to" => Model.plain(transition.to),
        "direction" => Model.plain(transition.subject)
      }
    end)
  end

  defp related_causal_edges(world, transitions, interactions, commitments) do
    ids =
      transitions
      |> Enum.map(& &1.event_id)
      |> Kernel.++(Enum.map(interactions, & &1.event_id))
      |> Kernel.++(Enum.map(commitments, & &1.id))
      |> MapSet.new()

    Enum.filter(Support.causal_edges(world), &(MapSet.member?(ids, &1.from) or MapSet.member?(ids, &1.to)))
  end

  defp diagnoses(parties, world, entries, transitions, interactions, commitments) do
    support_ids = measurement_ids(entries) ++ Enum.map(transitions, & &1.id) ++ Enum.map(interactions, & &1.id)
    payoff_edges = Enum.filter(related_causal_edges(world, transitions, interactions, commitments), &(&1.type == "pays_off"))
    change_measurements = Enum.map(@dimensions, &(&1 <> "_change"))
    measured_change = Enum.any?(change_measurements, &Support.any_supported?(entries, &1))

    []
    |> maybe_diag(
      length(interactions) >= 3 and transitions == [] and not measured_change and
        Support.all_not_supported?(entries, :interaction_changes_relationship),
      Support.diagnosis(
        "relationship.long_stasis_candidate",
        "Several consequential encounters may repeat relationship state without a recorded transition.",
        "At least three interaction records are present while neither frozen relationship transitions nor measured relationship change are established.",
        support_ids,
        limitations: ["Stable relationships can be intentional; compare against the writer's desired pressure and payoff. "]
      )
    )
    |> maybe_diag(
      reversal_candidate?(transitions) and weak_preparation?(entries),
      Support.diagnosis(
        "relationship.unsupported_reversal_candidate",
        "A recorded relationship reversal may have limited visible preparation in the measured material.",
        "A dimension reverses direction while preparation evidence does not cross the support threshold.",
        support_ids,
        uncertainty: "high",
        limitations: ["A surprise reversal can be intentional; inspect concealed information and reader knowledge before revising."]
      )
    )
    |> maybe_diag(
      repetitive_scene_count(entries) >= 2,
      Support.diagnosis(
        "relationship.repetitive_negotiation_candidate",
        "Multiple encounters may replay substantially the same negotiation or leverage pattern.",
        "Repetitive-negotiation measurements are supported in more than one scene.",
        support_ids,
        limitations: ["Repetition may accumulate comic, ritual, coercive, or suspense value."]
      )
    )
    |> maybe_diag(
      interactions != [] and transitions == [] and related_causal_edges(world, transitions, interactions, commitments) == [],
      Support.diagnosis(
        "relationship.consequence_missing_candidate",
        "The selected interactions may have limited recorded relationship consequence.",
        "Interaction records exist without a relationship transition or related causal edge in the frozen StoryWorld.",
        support_ids,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      payoff_edges != [] and Support.all_not_supported?(entries, :betrayal_or_payoff_prepared),
      Support.diagnosis(
        "relationship.betrayal_or_payoff_underprepared_candidate",
        "A recorded relationship payoff may not yet have visible preparation in the measured selection.",
        "A pays_off causal edge exists while preparation measurement remains unsupported.",
        support_ids ++ Enum.map(payoff_edges, & &1.id),
        uncertainty: "high"
      )
    )
    |> Enum.sort_by(& &1["id"])
    |> Enum.map(&Map.put(&1, "subject", Model.plain(parties)))
  end

  defp reversal_candidate?(transitions) do
    transitions
    |> Enum.group_by(fn transition -> {Model.plain(transition.subject), transition.attribute} end)
    |> Enum.any?(fn {_key, values} ->
      Enum.any?(values, fn later ->
        Enum.any?(values, fn earlier ->
          earlier.id != later.id and not is_nil(earlier.from) and not is_nil(earlier.to) and
            Support.subject_equal?(earlier.from, later.to) and Support.subject_equal?(earlier.to, later.from)
        end)
      end)
    end)
  end

  defp weak_preparation?([]), do: false
  defp weak_preparation?(entries), do: Support.all_not_supported?(entries, :betrayal_or_payoff_prepared)

  defp repetitive_scene_count(entries),
    do: Enum.count(entries, &Support.supported?(&1, :repetitive_negotiation))

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
          "relationship.long_stasis_candidate" -> "Compare each encounter's trust, leverage, obligation, concealment, and status deltas before rewriting dialogue."
          "relationship.unsupported_reversal_candidate" -> "Trace setup, concealed information, and causal preparation for the reversal in both presentation and story time."
          "relationship.repetitive_negotiation_candidate" -> "Compare tactic, leverage, information, and consequence across the repeated negotiations."
          _ -> "Inspect directional state and cited interaction evidence before selecting a relationship revision."
        end
      end)

    if trajectory["non_linear_presentation"],
      do: Enum.uniq(base ++ ["Compare relationship movement in reader-visible presentation order against established diegetic order."]),
      else: Enum.uniq(base)
  end

  defp parties(%{"characters" => characters}) when is_list(characters), do: unique_parties(characters)
  defp parties(%{"pair" => characters}) when is_list(characters), do: unique_parties(characters)
  defp parties({left, right}), do: unique_parties([left, right])
  defp parties(characters) when is_list(characters), do: unique_parties(characters)
  defp parties(_), do: []

  defp unique_parties(characters) do
    characters
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&Model.plain/1)
  end

  defp relationship_subject_within?(_subject, []), do: true

  defp relationship_subject_within?(subject, parties) do
    members =
      case Model.plain(subject) do
        %{"from" => from, "to" => to} -> [from, to]
        values when is_list(values) -> values
        _ -> []
      end
      |> Enum.reject(&is_nil/1)

    length(members) >= 2 and
      Enum.all?(members, fn member -> Enum.any?(parties, &Support.subject_equal?(member, &1)) end)
  end

  defp interaction_within?(_interaction, []), do: true

  defp interaction_within?(interaction, parties) do
    Enum.count(parties, &Support.character_in_value?(interaction.participants, &1)) >= 2
  end

  defp measurement_ids(entries) do
    entries
    |> Enum.flat_map(&get_in(&1, ["provenance", "measurement_ids"]) || [])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
  defp result_status(entries), do: if(entries != [] and Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")
  defp safe_options(opts), do: %{"intent" => Model.plain(Keyword.get(opts, :intent, %{}))}
end
