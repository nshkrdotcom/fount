defmodule Fount.Observe.Registry do
  @moduledoc "Closed installed sensor, projection and lens identities. Asset data never resolves executable modules."
  @lenses ~w(knowledge.access_evidence action.visibility continuity.transitions causality.support dialogue.interaction knowledge.behavior_support knowledge.epistemic_trace retrieval.relevance strategy.distinctness dialogue.voice_distinction)
  @projections ~w(explicit_state page_reader audience_estimate character_access)
  def lenses, do: @lenses
  def projections, do: @projections
  def sensors, do: ["system_one", "sandbox"]
  def lens?(id), do: id in @lenses
  def projection?(id), do: id in @projections
  def sensor?(id), do: id in sensors()
  def adapter("system_one"), do: {:ok, Fount.Observe.Providers.SystemOne}
  def adapter("sandbox"), do: {:ok, Fount.Observe.Sandbox}
  def adapter(_), do: {:error, Fount.Observe.Error.at(:invalid_request, ["sensor"])}
  def projection_digest(id) when id in @projections do
    Fount.Writing.CanonicalJSON.hash(%{"id" => id, "input" => "explicit_canonical_json",
      "context" => "closed_observe_context", "revision_envelope" => "excluded_from_model_input"})
  end
end
