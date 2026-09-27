defmodule Fount.Observe.Registry do
  @moduledoc "Closed installed sensor, projection and lens identities. Asset data never resolves executable modules."
  alias Fount.Observe.Error
  alias Fount.Writing.CanonicalJSON

  @lenses ~w(knowledge.access_evidence action.visibility continuity.transitions causality.support dialogue.interaction knowledge.behavior_support knowledge.epistemic_trace retrieval.relevance strategy.distinctness dialogue.voice_distinction diagnosis.concern_relevance diagnosis.evidence_support scene.engine agency.causality character.trajectory relationship.dynamics audience.reader_experience sequence.movement dialogue.exchange setup_payoff.motifs emotional.value_movement theme.meaning genre.lens_pack revision.intelligence)
  @projections ~w(explicit_state page_reader audience_estimate character_access)
  def lenses, do: @lenses
  def projections, do: @projections
  def sensors, do: ["system_one", "sandbox"]
  def lens?(id), do: id in @lenses
  def projection?(id), do: id in @projections
  def sensor?(id), do: id in sensors()
  def adapter("system_one"), do: {:ok, Fount.Observe.Providers.SystemOne}
  def adapter("sandbox"), do: {:ok, Fount.Observe.Sandbox}
  def adapter(_), do: {:error, Error.at(:invalid_request, ["sensor"])}

  def projection_contract(id) when id in @projections do
    policy =
      case id do
        "explicit_state" -> "exact_caller_json_no_heuristic_removal"
        "page_reader" -> "performed_page_fragments_through_legal_cutoff_no_hidden_notes"
        "audience_estimate" -> "spoken_dialogue_and_explicit_observable_fragments_only"
        "character_access" -> "own_behavior_and_declared_or_evidenced_access_not_presence"
      end

    %{
      "id" => id,
      "policy" => policy,
      "context" => "closed_typed_semantic_slots",
      "provenance" => "revision_targets_spans_and_evidence_pointers_not_provider_input"
    }
  end

  def projection_contract(_), do: {:error, Error.new(:invalid_projection)}

  def projection_digest(id) when id in @projections,
    do: id |> projection_contract() |> CanonicalJSON.hash()
end