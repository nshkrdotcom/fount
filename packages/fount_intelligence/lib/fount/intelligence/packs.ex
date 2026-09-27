defmodule Fount.Intelligence.Packs do
  @moduledoc "Phase-8 safe genre-pack authoring, validation, preview, install and composition APIs."

  alias Fount.Intelligence.Packs.{Catalog, GenrePack}

  @core_assets [
    %{
      "id" => "genre.mystery",
      "description" => "Mystery emphasis for question lifecycle, clue visibility, candidate explanations, reveal fairness and explanation load.",
      "purpose" => "Inspect mystery-specific information design without requiring culprit concealment or conventional reveal timing.",
      "trust" => "core",
      "source" => %{"label" => "Fount core Phase 8", "revision" => "1", "owner" => "fount"},
      "lenses" => ~w(audience.reader_experience setup_payoff.motifs knowledge.epistemic_trace),
      "capability_families" => ~w(audience_reader_experience setup_payoff_motifs theme_meaning),
      "playbooks" => ~w(suspense_audit setup_payoff submission_read),
      "diagnostic_salience" => %{"clue_fairness" => 0.9, "premature_inference" => 0.9, "explanation_load" => 0.7},
      "writer_intent_prompts" => ["Which questions should remain open?", "Which inference is the reader allowed to make early?"],
      "intent" => %{"subversions" => [], "opt_out" => ["culprit concealment", "late reveal"]},
      "resource_policy_request" => %{"max_targets" => 300, "max_states" => 300, "max_provider_requests" => 300, "max_wall_ms" => 120_000}
    },
    %{
      "id" => "genre.thriller",
      "description" => "Thriller emphasis for threat knowledge, pursuit/control, time pressure, narrowing options, suspense and reversals.",
      "purpose" => "Inspect pressure mechanics without treating speed or constant escalation as universal requirements.",
      "trust" => "core",
      "source" => %{"label" => "Fount core Phase 8", "revision" => "1", "owner" => "fount"},
      "lenses" => ~w(audience.reader_experience sequence.movement agency.causality),
      "capability_families" => ~w(audience_reader_experience sequence_movement agency_causality),
      "playbooks" => ~w(suspense_audit sequence_momentum scene_doctor),
      "diagnostic_salience" => %{"threat_knowledge" => 0.9, "narrowing_options" => 0.8, "reversal_pressure" => 0.7},
      "writer_intent_prompts" => ["Whose control should narrow here?", "Which threat should the reader understand now?"],
      "intent" => %{"subversions" => [], "opt_out" => ["constant acceleration"]},
      "resource_policy_request" => %{"max_targets" => 300, "max_states" => 300, "max_provider_requests" => 300, "max_wall_ms" => 120_000}
    },
    %{
      "id" => "genre.horror",
      "description" => "Horror emphasis for threat visibility, vulnerability, isolation, rule learning, dread/shock and escalating cost.",
      "purpose" => "Inspect horror pressure and information without assuming the threat must be explained or fully visible.",
      "trust" => "core",
      "source" => %{"label" => "Fount core Phase 8", "revision" => "1", "owner" => "fount"},
      "lenses" => ~w(audience.reader_experience sequence.movement emotional.value_movement),
      "capability_families" => ~w(audience_reader_experience sequence_movement emotional_value_movement),
      "playbooks" => ~w(suspense_audit sequence_momentum character_trajectory),
      "diagnostic_salience" => %{"vulnerability" => 0.9, "rule_learning" => 0.8, "dread_pressure" => 0.8},
      "writer_intent_prompts" => ["What should remain unknowable?", "What rule, if any, should the reader learn?"],
      "intent" => %{"subversions" => [], "opt_out" => ["full threat explanation"]},
      "resource_policy_request" => %{"max_targets" => 300, "max_states" => 300, "max_provider_requests" => 300, "max_wall_ms" => 120_000}
    },
    %{
      "id" => "genre.romance",
      "description" => "Romance emphasis for attraction, intimacy, trust, vulnerability, obstacle, commitment and relationship reversals.",
      "purpose" => "Inspect relationship movement without requiring union, reconciliation or a conventional ending.",
      "trust" => "core",
      "source" => %{"label" => "Fount core Phase 8", "revision" => "1", "owner" => "fount"},
      "lenses" => ~w(relationship.dynamics dialogue.exchange emotional.value_movement),
      "capability_families" => ~w(relationship_dynamics dialogue_interaction emotional_value_movement),
      "playbooks" => ~w(relationship_pass dialogue_pass character_trajectory),
      "diagnostic_salience" => %{"vulnerability" => 0.9, "commitment" => 0.8, "earned_separation_or_union" => 0.7},
      "writer_intent_prompts" => ["What intimacy or trust change should this encounter produce?", "Is union, separation, or ambiguity the intended endpoint?"],
      "intent" => %{"subversions" => [], "opt_out" => ["mandatory union", "mandatory reconciliation"]},
      "resource_policy_request" => %{"max_targets" => 300, "max_states" => 300, "max_provider_requests" => 300, "max_wall_ms" => 120_000}
    },
    %{
      "id" => "genre.comedy",
      "description" => "Comedy emphasis for premise/expectation, setup/payoff, escalation/reversal, status, callback, rhythm and character comic engine.",
      "purpose" => "Inspect comic mechanisms without trying to produce a universal funniness score.",
      "trust" => "core",
      "source" => %{"label" => "Fount core Phase 8", "revision" => "1", "owner" => "fount"},
      "lenses" => ~w(setup_payoff.motifs dialogue.exchange relationship.dynamics),
      "capability_families" => ~w(setup_payoff_motifs dialogue_interaction relationship_dynamics),
      "playbooks" => ~w(setup_payoff dialogue_pass relationship_pass),
      "diagnostic_salience" => %{"callback" => 0.9, "status_reversal" => 0.8, "escalation" => 0.8},
      "writer_intent_prompts" => ["What expectation does the beat set before reversing it?", "Which status transaction powers the joke?"],
      "intent" => %{"subversions" => [], "opt_out" => ["constant joke density"]},
      "resource_policy_request" => %{"max_targets" => 300, "max_states" => 300, "max_provider_requests" => 300, "max_wall_ms" => 120_000}
    },
    %{
      "id" => "genre.action",
      "description" => "Action emphasis for objective/spatial clarity, cause/effect, constraint escalation, resource depletion, consequence and recovery.",
      "purpose" => "Inspect action readability and consequence without treating spectacle density as quality.",
      "trust" => "core",
      "source" => %{"label" => "Fount core Phase 8", "revision" => "1", "owner" => "fount"},
      "lenses" => ~w(scene.engine sequence.movement agency.causality),
      "capability_families" => ~w(scene_engine sequence_movement agency_causality),
      "playbooks" => ~w(scene_doctor sequence_momentum),
      "diagnostic_salience" => %{"spatial_clarity" => 0.9, "cause_effect" => 0.9, "resource_depletion" => 0.7},
      "writer_intent_prompts" => ["What can the reader physically track?", "Which consequence changes the next action choice?"],
      "intent" => %{"subversions" => [], "opt_out" => ["spectacle density"]},
      "resource_policy_request" => %{"max_targets" => 300, "max_states" => 300, "max_provider_requests" => 300, "max_wall_ms" => 120_000}
    }
  ]

  def core_assets, do: @core_assets
  def core_ids, do: Enum.map(@core_assets, & &1["id"])

  def core(id) when is_binary(id) do
    case Enum.find(@core_assets, &(&1["id"] == id)) do
      nil -> {:error, :unknown_core_genre_pack}
      asset -> GenrePack.validate(asset)
    end
  end

  def core(_), do: {:error, :unknown_core_genre_pack}

  def new_catalog, do: Catalog.new(@core_assets)
  def validate(asset, opts \\ []), do: GenrePack.validate(asset, opts)
  def preview(asset, opts \\ []), do: GenrePack.preview(asset, opts)
  def install(%Catalog{} = catalog, asset, opts \\ []), do: Catalog.install(catalog, asset, opts)
  def enable(%Catalog{} = catalog, id), do: Catalog.enable(catalog, id)
  def disable(%Catalog{} = catalog, id), do: Catalog.disable(catalog, id)
  def fetch(%Catalog{} = catalog, id), do: Catalog.fetch(catalog, id)
  def list(%Catalog{} = catalog), do: Catalog.list(catalog)
  def enabled(%Catalog{} = catalog), do: Catalog.enabled(catalog)

  def resolve(id, _opts) when is_binary(id), do: core(id)

  def resolve(%{"enabled" => false}, _opts), do: {:error, :genre_pack_not_enabled}

  def resolve(asset, opts) when is_map(asset) do
    expected_sha = asset["sha256"]
    raw = Map.drop(asset, ["enabled", "effective_resource_policy", "sha256"])

    with {:ok, validated} <- GenrePack.validate(raw, opts),
         true <- is_nil(expected_sha) or expected_sha == validated["sha256"] do
      {:ok, validated}
    else
      false -> {:error, :stale_genre_pack}
      error -> error
    end
  end

  def resolve(_, _), do: {:error, :invalid_genre_pack}
end
