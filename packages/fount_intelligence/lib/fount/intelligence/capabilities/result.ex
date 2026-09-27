defmodule Fount.Intelligence.Capabilities.Result do
  @moduledoc "Pure Phase-6 capability result. Source evidence, derived state, trajectories, diagnoses, and limitations stay separate."

  alias Fount.Screenplay.Model

  @enforce_keys [:family, :source_revision]
  defstruct [
    :family,
    :source_revision,
    :subject,
    status: "complete",
    claim_class: "derived_narrative_state",
    evidence: [],
    measurements: %{},
    derived_state: %{},
    trajectories: %{},
    diagnoses: [],
    uncertainty: [],
    next_investigations: [],
    limitations: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  def to_map(%__MODULE__{} = result), do: Model.plain(result)
end
