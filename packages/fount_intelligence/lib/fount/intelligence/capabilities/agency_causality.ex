defmodule Fount.Intelligence.Capabilities.AgencyCausality do
  @moduledoc "Pure Phase-6 agency/causality reasoning. Causality is never inferred from presentation order."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Intelligence.StoryWorld
  alias Fount.Screenplay.Model

  @keys ~w(initiating_choice active_goal_pursuit causal_support motive_support knowledge_support relationship_pressure_support alternate_support reactive_only delayed_consequence removal_impact)a
  @decision_kinds ~w(decision choice refusal commitment)
  @action_kinds ~w(action attempt intervention pursuit)
  @consequence_kinds ~w(consequence outcome fallout payoff)

  def analyze(world, subject, measurement_entries, opts \\ []) do
    character = character(subject)
    events = character_events(world, character)
    decisions = Enum.filter(events, &(&1.kind in @decision_kinds))
    actions = Enum.filter(events, &(&1.kind in @action_kinds))
    consequences = Enum.filter(events, &(&1.kind in @consequence_kinds))
    goals = character_goals(world, character)
    chains = build_chains(world, decisions, actions, consequences)
    reach = Enum.map(decisions, &Support.causal_reach(world, &1.id))
    alternates = Support.alternate_support(world)
    counterfactuals = Enum.map(decisions, &Model.plain(StoryWorld.counterfactual_remove(world, [&1.id])))
    consequence_latency = consequence_latency(world, events, chains, measurement_entries)
    diagnoses = diagnoses(character, measurement_entries, decisions, chains, alternates, opts)
    source_objects = events ++ goals ++ character_commitments(world, character) ++ causal_objects(world, events)

    %Result{
      family: "agency_causality",
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
        "goal_records" => Support.plain_objects(goals),
        "decision_records" => Support.plain_objects(decisions),
        "action_records" => Support.plain_objects(actions),
        "consequence_records" => Support.plain_objects(consequences),
        "decision_action_consequence_chains" => chains,
        "causal_reach" => reach,
        "alternate_support" => alternates,
        "counterfactual_support" => counterfactuals,
        "consequence_latency" => consequence_latency
      },
      trajectories: %{
        "presentation_measurements" => Support.measurement_trajectory(measurement_entries, @keys),
        "event_story_time" => Support.story_order_links(world, events, & &1.id),
        "consequence_latency" => consequence_latency
      },
      diagnoses: diagnoses,
      uncertainty: measurement_uncertainty(measurement_entries),
      next_investigations: next_investigations(diagnoses),
      limitations: [
        "Agency measurements are uncalibrated model estimates, not judgments that a protagonist must be maximally active.",
        "Only explicit StoryWorld causal edges create decision/action/consequence chains; scene order never creates causality.",
        "Counterfactual removal reports dependency/support changes and does not simulate rewritten pages.",
        "Agency-intent mismatch is emitted only when the caller supplies an explicit intended agency mode."
      ],
      metadata: %{"family_version" => 1, "options" => safe_options(opts)}
    }
  end

  defp build_chains(world, decisions, actions, consequences) do
    action_ids = MapSet.new(Enum.map(actions, & &1.id))
    consequence_ids = MapSet.new(Enum.map(consequences, & &1.id))

    Enum.map(decisions, fn decision ->
      descendants = StoryWorld.causal_descendants(world, decision.id)
      action_hits = Enum.filter(descendants, &MapSet.member?(action_ids, &1))
      consequence_hits = Enum.filter(descendants, &MapSet.member?(consequence_ids, &1))

      %{
        "decision_id" => decision.id,
        "action_ids" => action_hits,
        "consequence_ids" => consequence_hits,
        "all_descendant_ids" => descendants
      }
    end)
  end

  defp consequence_latency(world, events, chains, entries) do
    positions =
      events
      |> Enum.sort_by(&Support.event_presentation_key(world, &1.id))
      |> Enum.with_index()
      |> Map.new(fn {event, index} -> {event.id, index} end)

    measured_scene_ids =
      entries
      |> Enum.filter(&Support.supported?(&1, :delayed_consequence))
      |> Enum.map(& &1["scene_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    chains
    |> Enum.flat_map(fn chain ->
      Enum.map(chain["consequence_ids"], fn consequence_id ->
        decision_id = chain["decision_id"]
        left = positions[decision_id]
        right = positions[consequence_id]

        %{
          "decision_id" => decision_id,
          "consequence_id" => consequence_id,
          "story_time_relation" => Model.plain(StoryWorld.story_time_relation(world, decision_id, consequence_id)),
          "presentation_event_distance" =>
            if(is_integer(left) and is_integer(right), do: right - left, else: nil),
          "delayed_consequence_measurement_scene_ids" => measured_scene_ids
        }
      end)
    end)
  end

  defp character_events(world, nil), do: Map.values(world.events) |> Enum.sort_by(& &1.id)

  defp character_events(world, character) do
    world.events
    |> Map.values()
    |> Enum.filter(&Support.event_has_character?(&1, character))
    |> Enum.sort_by(&Support.event_presentation_key(world, &1.id))
  end

  defp character_goals(world, nil), do: Map.values(world.goals) |> Enum.sort_by(& &1.id)

  defp character_goals(world, character) do
    world.goals
    |> Map.values()
    |> Enum.filter(&Support.subject_equal?(&1.owner, character))
    |> Enum.sort_by(& &1.id)
  end

  defp character_commitments(world, nil), do: Map.values(world.commitments)

  defp character_commitments(world, character) do
    world.commitments
    |> Map.values()
    |> Enum.filter(&(Support.subject_equal?(&1.from, character) or Support.subject_equal?(&1.to, character)))
  end

  defp causal_objects(world, events) do
    event_ids = MapSet.new(Enum.map(events, & &1.id))
    Enum.filter(Support.causal_edges(world), &(MapSet.member?(event_ids, &1.from) or MapSet.member?(event_ids, &1.to)))
  end

  defp diagnoses(character, entries, decisions, chains, alternates, opts) do
    support_ids = measurement_ids(entries) ++ Enum.map(decisions, & &1.id)
    intended = opts |> Keyword.get(:intent, %{}) |> intent_value("agency")

    []
    |> maybe_diag(
      entries != [] and Support.all_not_supported?(entries, :initiating_choice) and Support.any_supported?(entries, :reactive_only),
      Support.diagnosis(
        "agency.reactive_pattern",
        "The selected character may spend the sampled material reacting rather than initiating new goal-directed choices.",
        "Reactive-only evidence appears while initiating-choice evidence does not cross the support threshold.",
        support_ids,
        limitations: ["A reactive pattern can be fully intentional; compare against the writer's intended agency mode."]
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :initiating_choice) and Support.all_not_supported?(entries, :causal_support),
      Support.diagnosis(
        "agency.unsupported_causal_jump",
        "A consequential choice may not yet have visible causal support for its downstream effect.",
        "Initiating-choice evidence is present while causal-support evidence is absent in the measured material.",
        support_ids
      )
    )
    |> maybe_diag(
      entries != [] and Support.all_not_supported?(entries, :active_goal_pursuit) and
        Support.all_not_supported?(entries, :motive_support),
      Support.diagnosis(
        "agency.motivation_gap_candidate",
        "A consequential action may need clearer motivational support.",
        "Neither active-goal pursuit nor motive support is established by the current measurements.",
        support_ids,
        uncertainty: "high",
        limitations: ["Subtext, withholding, or deliberate opacity may make motivation intentionally indirect."]
      )
    )
    |> maybe_diag(
      alternates != [] and Support.any_supported?(entries, :alternate_support),
      Support.diagnosis(
        "agency.redundant_support_candidate",
        "At least one downstream event may have independent causal support beyond the selected action.",
        "The causal graph contains multiple support paths and the alternate-support measurement is positive.",
        support_ids ++ Enum.flat_map(alternates, & &1["edge_ids"]),
        limitations: ["Redundant support can improve robustness, inevitability, or thematic layering."]
      )
    )
    |> maybe_diag(
      Support.any_supported?(entries, :delayed_consequence),
      Support.diagnosis(
        "agency.delayed_consequence",
        "A prior choice appears to receive a delayed consequence in the selected material.",
        "The delayed-consequence measurement is supported; inspect whether the delay strengthens or obscures causality.",
        support_ids,
        limitations: ["Delay is descriptive, not inherently a defect."]
      )
    )
    |> maybe_diag(
      intended == "initiating" and Support.any_supported?(entries, :reactive_only),
      Support.diagnosis(
        "agency.intent_mismatch",
        "Measured agency may diverge from the writer's stated initiating-agency intent.",
        "The request explicitly asks for initiating agency while reactive-only evidence is present.",
        support_ids,
        counterevidence: Enum.flat_map(chains, & &1["all_descendant_ids"]),
        uncertainty: "medium"
      )
    )
    |> Enum.sort_by(& &1["id"])
    |> Enum.map(&Map.put(&1, "subject", Model.plain(character)))
  end

  defp measurement_uncertainty(entries) do
    for entry <- entries,
        key <- @keys,
        Support.status(entry, key) in ["uncertain", "insufficient_evidence", "unavailable"] do
      %{"scene_id" => entry["scene_id"], "measurement" => to_string(key), "status" => Support.status(entry, key)}
    end
  end

  defp next_investigations(diagnoses) do
    diagnoses
    |> Enum.map(fn diagnosis ->
      case diagnosis["id"] do
        "agency.reactive_pattern" -> "Map the character's choices against active goals and ask which downstream events disappear if those choices are removed."
        "agency.unsupported_causal_jump" -> "Trace decision -> action -> consequence evidence and inspect missing intermediate support."
        "agency.motivation_gap_candidate" -> "Compare motive, knowledge, relationship pressure, and commitment evidence before proposing exposition."
        _ -> "Inspect causal ancestors, descendants, and alternate support before selecting a revision strategy."
      end
    end)
    |> Enum.uniq()
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

  defp intent_value(intent, "agency") when is_map(intent), do: Map.get(intent, "agency") || Map.get(intent, :agency)
  defp intent_value(_, _), do: nil
  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
  defp result_status(entries), do: if(entries != [] and Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")
  defp safe_options(opts), do: %{"intent" => Model.plain(Keyword.get(opts, :intent, %{}))}
end
