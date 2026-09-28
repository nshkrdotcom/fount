defmodule Fount.Intelligence.Evaluation.Suite do
  @moduledoc "Capability/lens benchmark catalog and evaluation-suite validation."

  alias Fount.Intelligence.Capabilities
  alias Fount.Observe.Registry
  alias Fount.Writing.CanonicalJSON

  @family_lenses %{
    "scene_engine" => ["scene.engine"],
    "agency_causality" => ["agency.causality", "causality.support"],
    "character_trajectory" => ["character.trajectory"],
    "relationship_dynamics" => ["relationship.dynamics"],
    "audience_reader_experience" => ["audience.reader_experience", "knowledge.epistemic_trace"],
    "sequence_movement" => ["sequence.movement", "continuity.transitions"],
    "dialogue_interaction" => [
      "dialogue.interaction",
      "dialogue.exchange",
      "dialogue.voice_distinction"
    ],
    "setup_payoff_motifs" => ["setup_payoff.motifs", "causality.support"],
    "emotional_value_movement" => ["emotional.value_movement"],
    "theme_meaning" => ["theme.meaning"],
    "genre_lens_packs" => ["genre.lens_pack"],
    "revision_intelligence" => [
      "revision.intelligence",
      "diagnosis.concern_relevance",
      "diagnosis.evidence_support"
    ]
  }

  @spec catalog() :: [map()]
  def catalog do
    Capabilities.families()
    |> Enum.map(fn family ->
      %{
        "capability_family" => family,
        "lens_ids" => Map.fetch!(@family_lenses, family),
        "required_evaluation" =>
          [
            "current_contract_fixture",
            "synthetic_regression",
            "failure_and_abstention",
            "resource_accounting"
          ] ++ nonlinear_requirement(family),
        "human_evidence" => "optional_unless_actual_study_is_recorded"
      }
    end)
  end

  @spec validate_catalog() :: :ok | {:error, atom()}
  def validate_catalog do
    families = Capabilities.families()
    catalog = catalog()

    valid =
      Enum.map(catalog, & &1["capability_family"]) == families and
        Enum.all?(catalog, fn row ->
          row["lens_ids"] != [] and Enum.all?(row["lens_ids"], &Registry.lens?/1)
        end)

    if valid, do: :ok, else: {:error, :invalid_evaluation_catalog}
  end

  @spec validate_suite(map()) :: {:ok, map()} | {:error, atom()}
  def validate_suite(suite) when is_map(suite) do
    with true <- nonblank?(suite["id"]),
         true <- is_list(suite["capability_families"]) and suite["capability_families"] != [],
         true <- Enum.all?(suite["capability_families"], &Capabilities.member?/1),
         true <- is_list(suite["lens_ids"]) and Enum.all?(suite["lens_ids"], &Registry.lens?/1),
         true <- is_list(suite["slices"]) and Enum.all?(suite["slices"], &nonblank?/1),
         true <- is_list(suite["fixture_refs"]) and Enum.all?(suite["fixture_refs"], &nonblank?/1),
         true <- suite["support_validity"] == true,
         true <-
           suite["writer_usefulness"] in ["separate_optional_study", "separate_recorded_study"],
         {:ok, _} <- CanonicalJSON.encode(suite) do
      {:ok, Map.put(suite, "suite_sha256", CanonicalJSON.hash(suite))}
    else
      _ -> {:error, :invalid_evaluation_suite}
    end
  rescue
    _ -> {:error, :invalid_evaluation_suite}
  end

  def validate_suite(_), do: {:error, :invalid_evaluation_suite}

  defp nonlinear_requirement(family)
       when family in ~w(audience_reader_experience sequence_movement setup_payoff_motifs revision_intelligence),
       do: ["nonlinear_presentation_story_time"]

  defp nonlinear_requirement(_), do: []

  defp nonblank?(value),
    do: is_binary(value) and String.trim(value) != "" and String.valid?(value)
end
