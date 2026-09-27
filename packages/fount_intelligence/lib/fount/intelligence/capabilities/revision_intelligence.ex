defmodule Fount.Intelligence.Capabilities.RevisionIntelligence do
  @moduledoc "Pure Phase-8 before/after revision reasoning over frozen measurements, StoryWorlds, Reader state and exact diff metadata supplied by the shell."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  @keys ~w(intended_effect_present protected_strength_preserved continuity_risk knowledge_risk causal_risk voice_drift action_readability_risk setup_payoff_break reader_state_regression)a
  @risk_keys ~w(continuity_risk knowledge_risk causal_risk voice_drift action_readability_risk setup_payoff_break reader_state_regression)a

  def analyze(world, subject, entries, opts \\ []) do
    %Result{
      family: "revision_intelligence",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: status(entries),
      evidence: Support.measurement_evidence(entries),
      measurements: %{"keys" => Enum.map(@keys, &to_string/1), "entries" => entries},
      derived_state: %{
        "single_revision_snapshot" => aggregate(entries),
        "story_world_state_transition_ids" => world.state_transitions |> Map.keys() |> Enum.sort(),
        "causal_edge_ids" => world.causal.edges |> Map.keys() |> Enum.sort()
      },
      trajectories: %{"measurements" => Support.measurement_trajectory(entries, @keys)},
      diagnoses: [],
      uncertainty: uncertainty(entries),
      next_investigations: ["Use the explicit two-revision comparison API for target-effect, collateral, causal, reader, character and relationship diffs."],
      limitations: [
        "A single-revision run is only a snapshot. Revision claims require an explicit base and candidate comparison.",
        "No candidate is accepted, rejected, ranked, or promoted to canon by this family."
      ],
      metadata: %{"family_version" => 1, "comparison" => false, "intent" => Model.plain(Keyword.get(opts, :intent, %{}))}
    }
  end

  def compare(before_world, after_world, subject, before_entries, after_entries, opts \\ []) do
    before = aggregate(before_entries)
    after_state = aggregate(after_entries)
    transition_diff = object_diff(before_world.state_transitions, after_world.state_transitions)
    character_transition_diff = transition_diff_for(before_world.state_transitions, after_world.state_transitions, :character)
    relationship_transition_diff = transition_diff_for(before_world.state_transitions, after_world.state_transitions, :relationship)
    causal_diff = object_diff(before_world.causal.edges, after_world.causal.edges)
    story_time_diff = object_diff(before_world.story_time.constraints, after_world.story_time.constraints)
    reader_diff = reader_diff(Keyword.get(opts, :before_reader), Keyword.get(opts, :after_reader))
    measurement_diff = measurement_diff(before, after_state)
    structural_diff = Model.plain(Keyword.get(opts, :structural_diff, %{}))
    source_diff = Model.plain(Keyword.get(opts, :source_diff, []))
    strategies = Model.plain(Keyword.get(opts, :strategy_contrast))
    diagnoses = diagnoses(after_entries, measurement_diff, reader_diff, transition_diff, causal_diff)

    %Result{
      family: "revision_intelligence",
      source_revision: after_world.revision_id,
      subject: Model.plain(subject),
      status: comparison_status(before_entries, after_entries),
      evidence:
        Support.merge_evidence([
          Support.measurement_evidence(before_entries),
          Support.measurement_evidence(after_entries),
          world_evidence(before_world),
          world_evidence(after_world)
        ]),
      measurements: %{
        "keys" => Enum.map(@keys, &to_string/1),
        "before_entries" => before_entries,
        "after_entries" => after_entries,
        "aggregate_diff" => measurement_diff
      },
      derived_state: %{
        "lineage" => %{
          "before_revision_id" => before_world.revision_id,
          "after_revision_id" => after_world.revision_id,
          "concern" => Model.plain(Keyword.get(opts, :concern)),
          "strategy" => Model.plain(Keyword.get(opts, :strategy))
        },
        "exact_edits" => %{
          "structural_diff" => structural_diff,
          "source_diff" => source_diff
        },
        "target_effect" => target_effect(before, after_state, opts),
        "collateral_change" => collateral(after_state, opts),
        "protected_strengths" => protected_strengths(after_state, opts),
        "state_transition_diff" => transition_diff,
        "character_trajectory_diff" => character_transition_diff,
        "relationship_trajectory_diff" => relationship_transition_diff,
        "character_relationship_trajectory_diff" => %{
          "character" => character_transition_diff,
          "relationship" => relationship_transition_diff
        },
        "causal_ripple" => causal_diff,
        "story_time_continuity_diff" => story_time_diff,
        "reader_trajectory_diff" => reader_diff,
        "strategy_distinctness" => strategies,
        "presentation_vs_diegetic" => %{
          "presentation_effects" => reader_diff,
          "diegetic_state_effects" => transition_diff,
          "story_time_effects" => story_time_diff,
          "kept_separate" => true
        }
      },
      trajectories: %{
        "before" => Support.measurement_trajectory(before_entries, @keys),
        "after" => Support.measurement_trajectory(after_entries, @keys),
        "reader" => reader_diff,
        "story_world" => transition_diff
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(before_entries) ++ uncertainty(after_entries) ++ reader_uncertainty(reader_diff),
      next_investigations: next_investigations(diagnoses),
      limitations: [
        "The packet compares evidence; it does not decide whether the revision is better or choose a preferred candidate.",
        "Reader presentation effects are reported separately from diegetic state and story-time continuity changes.",
        "Protected-strength checks are model-estimated unless a protected item is backed by a deterministic StoryWorld/diff constraint.",
        "Missing records or reader events stay visible as unknown/partial rather than being reconstructed from later pages."
      ],
      metadata: %{
        "family_version" => 1,
        "comparison" => true,
        "before_revision_id" => before_world.revision_id,
        "after_revision_id" => after_world.revision_id,
        "intent" => Model.plain(Keyword.get(opts, :intent, %{}))
      }
    }
  end

  defp aggregate(entries) do
    Map.new(@keys, fn key ->
      statuses = Enum.map(entries, &Support.status(&1, key))

      {to_string(key),
       %{
         "supported" => Enum.count(statuses, &(&1 == "supported")),
         "not_supported" => Enum.count(statuses, &(&1 == "not_supported")),
         "uncertain" => Enum.count(statuses, &(&1 in ["uncertain", "insufficient_evidence", "unavailable"])),
         "total" => length(statuses)
       }}
    end)
  end

  defp measurement_diff(before, after_state) do
    Map.new(@keys, fn key ->
      name = to_string(key)
      left = before[name]
      right = after_state[name]

      {name,
       %{
         "before_supported" => left["supported"],
         "after_supported" => right["supported"],
         "supported_delta" => right["supported"] - left["supported"],
         "before_uncertain" => left["uncertain"],
         "after_uncertain" => right["uncertain"]
       }}
    end)
  end

  defp target_effect(before, after_state, opts) do
    before_count = before["intended_effect_present"]["supported"]
    after_count = after_state["intended_effect_present"]["supported"]

    %{
      "declared_intended_effect" => Model.plain(Keyword.get(opts, :intended_effect)),
      "before_supported_scenes" => before_count,
      "after_supported_scenes" => after_count,
      "supported_scene_delta" => after_count - before_count,
      "claim_class" => "model_estimated_interpretation"
    }
  end

  defp collateral(after_state, opts) do
    %{
      "declared_constraints" => Model.plain(Keyword.get(opts, :constraints, [])),
      "risk_support" => Map.new(@risk_keys, &{to_string(&1), after_state[to_string(&1)]["supported"]}),
      "quality_score" => nil
    }
  end

  defp protected_strengths(after_state, opts) do
    %{
      "declared" => Model.plain(Keyword.get(opts, :protected_strengths, [])),
      "preserved_supported_scenes" => after_state["protected_strength_preserved"]["supported"],
      "status" =>
        if(after_state["protected_strength_preserved"]["supported"] > 0,
          do: "evidence_of_preservation",
          else: "not_established"
        )
    }
  end

  defp reader_diff(nil, nil), do: %{"status" => "not_supplied", "presentation_effects" => []}

  defp reader_diff(before, after_reader) do
    left = reader_packet(before)
    right = reader_packet(after_reader)
    left_final = left["final_state"] || %{}
    right_final = right["final_state"] || %{}

    keys =
      (Map.keys(left_final) ++ Map.keys(right_final))
      |> Enum.uniq()
      |> Enum.sort()

    %{
      "status" => if(before && after_reader, do: "compared", else: "partial"),
      "before" => left,
      "after" => right,
      "track_deltas" =>
        Map.new(keys, fn key ->
          l = Map.get(left_final, key, %{})
          r = Map.get(right_final, key, %{})
          {key, map_key_delta(l, r)}
        end)
    }
  end

  defp reader_packet(%Fount.Intelligence.Reader{} = reader),
    do: Fount.Intelligence.Reader.inspection_packet(reader)

  defp reader_packet(_), do: %{"status" => "not_supplied", "final_state" => %{}}

  defp map_key_delta(left, right) when is_map(left) and is_map(right) do
    %{
      "added" => (Map.keys(right) -- Map.keys(left)) |> Enum.sort(),
      "removed" => (Map.keys(left) -- Map.keys(right)) |> Enum.sort(),
      "retained" => Map.keys(left) |> Enum.filter(&Map.has_key?(right, &1)) |> Enum.sort(),
      "changed" =>
        Map.keys(left)
        |> Enum.filter(&(Map.has_key?(right, &1) and CanonicalJSON.hash(Model.plain(left[&1])) != CanonicalJSON.hash(Model.plain(right[&1]))))
        |> Enum.sort()
    }
  end

  defp map_key_delta(_, _), do: %{"added" => [], "removed" => [], "retained" => [], "changed" => []}

  defp transition_diff_for(before, after_objects, kind) do
    before = Map.filter(before, fn {_id, transition} -> transition_kind(transition) == kind end)
    after_objects = Map.filter(after_objects, fn {_id, transition} -> transition_kind(transition) == kind end)
    object_diff(before, after_objects)
  end

  defp transition_kind(transition) do
    attribute = transition |> Map.get(:attribute, Map.get(transition, "attribute", "")) |> to_string()
    subject = Map.get(transition, :subject, Map.get(transition, "subject"))

    if String.starts_with?(attribute, "relationship.") or
         (is_map(subject) and (Map.has_key?(subject, "from") or Map.has_key?(subject, :from))) do
      :relationship
    else
      :character
    end
  end

  defp object_diff(before, after_objects) when is_map(before) and is_map(after_objects) do
    before_ids = Map.keys(before)
    after_ids = Map.keys(after_objects)
    shared = Enum.filter(before_ids, &Map.has_key?(after_objects, &1))

    changed =
      Enum.filter(shared, fn id ->
        CanonicalJSON.hash(Model.plain(before[id])) != CanonicalJSON.hash(Model.plain(after_objects[id]))
      end)
      |> Enum.sort()

    %{
      "added_ids" => (after_ids -- before_ids) |> Enum.sort(),
      "removed_ids" => (before_ids -- after_ids) |> Enum.sort(),
      "changed_ids" => changed,
      "retained_ids" => (shared -- changed) |> Enum.sort()
    }
  end

  defp world_evidence(world) do
    Support.merge_evidence([
      Support.evidence(Map.values(world.state_transitions)),
      Support.evidence(Map.values(world.causal.edges)),
      Support.evidence(Map.values(world.story_time.constraints))
    ])
  end

  defp diagnoses(after_entries, measurement_diff, reader_diff, transitions, causal) do
    support = measurement_ids(after_entries)

    []
    |> maybe_diag(
      measurement_diff["intended_effect_present"]["supported_delta"] <= 0 and
        Support.all_not_supported?(after_entries, :intended_effect_present),
      Support.diagnosis(
        "revision.target_effect_not_established",
        "The intended revision effect is not established in the candidate measurements.",
        "Candidate intended-effect measurements are unsupported and show no supported increase from the base.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      Enum.any?(@risk_keys, &Support.any_supported?(after_entries, &1)),
      Support.diagnosis(
        "revision.collateral_risk_candidate",
        "The candidate introduces at least one possible continuity, knowledge, causal, voice, readability, setup/payoff, or reader-state collateral risk.",
        "One or more dedicated collateral-risk measurements are supported.",
        support,
        uncertainty: "high"
      )
    )
    |> maybe_diag(
      causal["removed_ids"] != [] or causal["changed_ids"] != [],
      Support.diagnosis(
        "revision.causal_ripple_candidate",
        "The candidate changes or removes explicit causal links and may require downstream repair inspection.",
        "StoryWorld causal edge identity differs between base and candidate.",
        causal["removed_ids"] ++ causal["changed_ids"],
        uncertainty: "low"
      )
    )
    |> maybe_diag(
      transitions["removed_ids"] != [] or transitions["changed_ids"] != [],
      Support.diagnosis(
        "revision.state_trajectory_change",
        "Character, relationship, practical, or value state transitions changed between revisions.",
        "StoryWorld state-transition identity/content differs between base and candidate.",
        transitions["removed_ids"] ++ transitions["changed_ids"],
        uncertainty: "low"
      )
    )
    |> maybe_diag(
      reader_diff["status"] == "compared" and reader_track_changed?(reader_diff),
      Support.diagnosis(
        "revision.reader_presentation_change",
        "First-exposure Reader state changes between revisions.",
        "Supplied strict-forward Reader ledgers have added or removed track entries.",
        support,
        uncertainty: "low"
      )
    )
    |> Enum.sort_by(& &1["id"])
  end

  defp reader_track_changed?(reader_diff) do
    reader_diff["track_deltas"]
    |> Map.values()
    |> Enum.any?(fn delta ->
      delta["added"] != [] or delta["removed"] != [] or delta["changed"] != []
    end)
  end

  defp uncertainty(entries) do
    for entry <- entries,
        key <- @keys,
        Support.status(entry, key) in ["uncertain", "insufficient_evidence", "unavailable"] do
      %{"scene_id" => entry["scene_id"], "measurement" => to_string(key), "status" => Support.status(entry, key)}
    end
  end

  defp reader_uncertainty(%{"status" => "not_supplied"}),
    do: [%{"kind" => "reader_comparison_not_supplied", "status" => "unknown"}]

  defp reader_uncertainty(%{"status" => "partial"}),
    do: [%{"kind" => "reader_comparison_partial", "status" => "unknown"}]

  defp reader_uncertainty(_), do: []

  defp next_investigations(diagnoses) do
    Enum.map(diagnoses, fn diagnosis ->
      case diagnosis["id"] do
        "revision.causal_ripple_candidate" ->
          "Trace every changed/removed causal edge to downstream accusations, choices, reveals, relationship consequences, and setup/payoff obligations before generating repairs."

        "revision.reader_presentation_change" ->
          "Compare the exact Reader checkpoints where questions, expectations, threats, comprehension risks, or reveals entered/left the ledger."

        "revision.state_trajectory_change" ->
          "Inspect changed state transitions separately in presentation order and story time so a flashback/reorder is not mistaken for a diegetic rewrite."

        _ ->
          "Inspect target-effect and collateral-risk evidence before choosing whether to revise, preserve, or deliberately accept the tradeoff."
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

  defp status(entries), do: if(Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")

  defp comparison_status(before_entries, after_entries) do
    if status(before_entries) == "complete" and status(after_entries) == "complete", do: "complete", else: "partial"
  end

  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
end
