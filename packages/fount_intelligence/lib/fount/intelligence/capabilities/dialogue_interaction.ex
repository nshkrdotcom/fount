defmodule Fount.Intelligence.Capabilities.DialogueInteraction do
  @moduledoc "Pure Phase-7 exchange reasoning over source-grounded dialogue-pair measurements and frozen interaction records."

  alias Fount.Intelligence.Capabilities.{Result, Support}
  alias Fount.Screenplay.Model

  @keys ~w(responds evades redirects attacks bargains reveals conceals subtext exposition exposition_dramatic_work tactic_shift status_shift knowledge_asymmetry repetition exchange_changes_state voice_distinction)a

  def analyze(world, subject, entries, opts \\ []) do
    pairs = Enum.map(entries, &pair_state(world, &1))
    diagnoses = diagnoses(pairs)
    interactions = interaction_records(world, entries)

    %Result{
      family: "dialogue_interaction",
      source_revision: world.revision_id,
      subject: Model.plain(subject),
      status: result_status(entries),
      evidence:
        Support.merge_evidence([
          Support.measurement_evidence(entries),
          Support.evidence(interactions)
        ]),
      measurements: %{
        "keys" => Enum.map(@keys, &to_string/1),
        "entries" => entries
      },
      derived_state: %{
        "turn_pair_observations" => pairs,
        "status_transactions" => transactions(pairs, "status_shift"),
        "exposition_evidence" => transactions(pairs, "exposition"),
        "redundancy_evidence" => transactions(pairs, "repetition"),
        "voice_features" => transactions(pairs, "voice_distinction"),
        "exchange_outcome" => exchange_outcome(pairs, interactions),
        "context_usage" => context_usage(entries)
      },
      trajectories: %{
        "exchange_order_tactic" => tactic_trajectory(pairs),
        "exchange_order_status" => transactions(pairs, "status_shift"),
        "exchange_order_knowledge_asymmetry" => transactions(pairs, "knowledge_asymmetry")
      },
      diagnoses: diagnoses,
      uncertainty: uncertainty(entries),
      next_investigations: next_investigations(diagnoses),
      limitations: [
        "Turn-pair measurements are model estimates over exact selected screenplay excerpts; dialogue diagnosis remains a writer-inspection hypothesis, not a rule that lines must be indirect, brief, or constantly changing.",
        "Typed dialogue context is optional and lens-validated. Missing facts, beliefs, prior turns, or relationship state remain missing rather than being inferred from Intelligence structs.",
        "Exposition is descriptive. Exposition that also creates conflict, tactic, concealment, status, choice, or relationship pressure is kept distinct from explanation-only candidates.",
        "Voice distinction is evidence about wording, rhythm, tactics, references, and conversational behavior in the supplied exchange, not a global character-quality score."
      ],
      metadata: %{
        "family_version" => 1,
        "turn_pair_count" => length(pairs),
        "interaction_record_count" => length(interactions),
        "options" => safe_options(opts)
      }
    }
  end

  defp pair_state(world, entry) do
    scene_id = entry["scene_id"]
    pair = entry["turn_pair"] || %{}

    interaction_ids =
      world.interactions
      |> Map.values()
      |> Enum.filter(&(&1.event_id in Support.event_ids_for_scene(world, scene_id)))
      |> Enum.map(& &1.id)
      |> Enum.sort()

    %{
      "scene_id" => scene_id,
      "pair_ordinal" => entry["pair_ordinal"],
      "turn_pair" => pair,
      "measurements" => Map.new(@keys, &{to_string(&1), Support.answer(entry, &1)}),
      "interaction_ids" => interaction_ids,
      "context_slots" => entry["context_slots"] || [],
      "measurement_ids" => get_in(entry, ["provenance", "measurement_ids"]) || []
    }
  end

  defp interaction_records(world, entries) do
    scene_ids = Support.measurement_scenes(entries)
    event_ids = Enum.flat_map(scene_ids, &Support.event_ids_for_scene(world, &1)) |> MapSet.new()

    world.interactions
    |> Map.values()
    |> Enum.filter(&MapSet.member?(event_ids, &1.event_id))
    |> Enum.sort_by(&Support.event_presentation_key(world, &1.event_id))
  end

  defp transactions(pairs, key) do
    Enum.flat_map(pairs, fn pair ->
      case get_in(pair, ["measurements", key]) do
        %{"status" => status} = answer when status in ["supported", "uncertain"] ->
          [
            %{
              "scene_id" => pair["scene_id"],
              "pair_ordinal" => pair["pair_ordinal"],
              "turn_pair" => pair["turn_pair"],
              "answer" => answer
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp tactic_trajectory(pairs) do
    Enum.map(pairs, fn pair ->
      %{
        "scene_id" => pair["scene_id"],
        "pair_ordinal" => pair["pair_ordinal"],
        "responds" => get_in(pair, ["measurements", "responds"]),
        "evades" => get_in(pair, ["measurements", "evades"]),
        "redirects" => get_in(pair, ["measurements", "redirects"]),
        "attacks" => get_in(pair, ["measurements", "attacks"]),
        "bargains" => get_in(pair, ["measurements", "bargains"]),
        "tactic_shift" => get_in(pair, ["measurements", "tactic_shift"])
      }
    end)
  end

  defp exchange_outcome(pairs, interactions) do
    %{
      "measured_state_change_pairs" =>
        pairs
        |> Enum.filter(&supported_in?(&1, "exchange_changes_state"))
        |> Enum.map(&pair_ref/1),
      "recorded_interactions" => Enum.map(interactions, &Model.plain/1)
    }
  end

  defp context_usage(entries) do
    %{
      "entries_with_typed_context" => Enum.count(entries, &((&1["context_slots"] || []) != [])),
      "slot_names" =>
        entries
        |> Enum.flat_map(&(&1["context_slots"] || []))
        |> Enum.uniq()
        |> Enum.sort()
    }
  end

  defp diagnoses(pairs) do
    support = pairs |> Enum.flat_map(& &1["measurement_ids"]) |> Enum.uniq() |> Enum.sort()

    repetitive = Enum.filter(pairs, &supported_in?(&1, "repetition"))
    static = Enum.filter(pairs, &(not supported_in?(&1, "exchange_changes_state")))

    exposition_only =
      Enum.filter(
        pairs,
        &(supported_in?(&1, "exposition") and not supported_in?(&1, "exposition_dramatic_work"))
      )

    indistinct = Enum.filter(pairs, &not_supported_in?(&1, "voice_distinction"))

    []
    |> maybe_diag(
      length(static) >= 2 and not Enum.any?(pairs, &supported_in?(&1, "tactic_shift")),
      Support.diagnosis(
        "dialogue.static_exchange_candidate",
        "The exchange may continue without changing tactic, knowledge, goal, relationship, status, leverage, pressure, commitment, or available action.",
        "At least two measured turn pairs lack supported state change and no tactic shift is supported in the supplied exchange.",
        support,
        limitations: [
          "Stillness, refusal, silence, ritual, deadlock, and comic repetition can be intentional; inspect desired scene behavior before revising."
        ]
      )
    )
    |> maybe_diag(
      length(repetitive) >= 2,
      Support.diagnosis(
        "dialogue.repeated_tactic_or_information_candidate",
        "Several turn pairs may repeat substantially the same information, tactic, or demand.",
        "Repetition measurement is supported in multiple turn pairs.",
        support,
        limitations: [
          "Repeated language can accumulate pressure, rhythm, intimacy, coercion, or comedy; repetition alone is not a defect."
        ]
      )
    )
    |> maybe_diag(
      exposition_only != [],
      Support.diagnosis(
        "dialogue.exposition_without_dramatic_work_candidate",
        "Some exposition may primarily explain rather than alter the dramatic exchange.",
        "Exposition is supported while dramatic-work measurement is not supported for one or more turn pairs.",
        support,
        uncertainty: "medium"
      )
    )
    |> maybe_diag(
      length(indistinct) >= 2,
      Support.diagnosis(
        "dialogue.voice_interchangeability_candidate",
        "Several measured turn pairs may offer limited evidence of voice distinction within the supplied material.",
        "Voice-distinction measurement is unsupported for multiple turn pairs.",
        support,
        uncertainty: "high",
        limitations: [
          "Shared vocabulary or stripped-down speech can be intentional; compare tactics, syntax, rhythm, references, and worldview rather than forcing catchphrases."
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
        "pair_ordinal" => entry["pair_ordinal"],
        "measurement" => to_string(key),
        "status" => Support.status(entry, key)
      }
    end
  end

  defp next_investigations(diagnoses) do
    diagnoses
    |> Enum.map(fn diagnosis ->
      case diagnosis["id"] do
        "dialogue.exposition_without_dramatic_work_candidate" ->
          "For each cited exposition turn, identify the speaker's immediate tactic, obstacle, leverage, concealment, or relationship need before rewriting information."

        "dialogue.voice_interchangeability_candidate" ->
          "Compare the speakers' tactics, sentence shapes, reference frames, status behavior, and what each refuses to say; do not solve voice with ornamental quirks alone."

        "dialogue.static_exchange_candidate" ->
          "Mark what changes after each turn pair—knowledge, goal, leverage, relationship, status, pressure, commitment, or available action—and decide where stillness is intentional."

        _ ->
          "Inspect the exact turn-pair evidence and compare response, tactic, leverage, knowledge, and consequence before revising lines."
      end
    end)
    |> Enum.uniq()
  end

  defp supported_in?(pair, key),
    do: match?(%{"status" => "supported"}, get_in(pair, ["measurements", key]))

  defp not_supported_in?(pair, key),
    do: match?(%{"status" => "not_supported"}, get_in(pair, ["measurements", key]))

  defp pair_ref(pair),
    do: %{"scene_id" => pair["scene_id"], "pair_ordinal" => pair["pair_ordinal"]}

  defp result_status(entries),
    do: if(Enum.all?(entries, &(&1["status"] == "complete")), do: "complete", else: "partial")

  defp safe_options(_opts), do: %{}
  defp maybe_diag(list, true, diagnosis), do: list ++ [diagnosis]
  defp maybe_diag(list, false, _diagnosis), do: list
end
