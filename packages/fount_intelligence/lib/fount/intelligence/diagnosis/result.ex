defmodule Fount.Intelligence.Diagnosis.Result do
  @moduledoc "Pure evidence-composed diagnosis result. Completion never means screenplay quality or human agreement."

  alias Fount.Intelligence.Diagnosis.{Concern, EvidenceNeed}

  @enforce_keys [:concern]
  defstruct [
    :concern,
    diagnoses: [],
    missing_evidence: [],
    abstentions: [],
    protected_strengths: [],
    next_investigations: [],
    evidence: [],
    limitations: []
  ]

  @type t :: %__MODULE__{}

  def to_map(%__MODULE__{} = result) do
    %{
      "concern" => Concern.to_map(result.concern),
      "diagnoses" => result.diagnoses,
      "missing_evidence" => Enum.map(result.missing_evidence, &EvidenceNeed.to_map/1),
      "abstentions" => result.abstentions,
      "protected_strengths" => result.protected_strengths,
      "next_investigations" => result.next_investigations,
      "evidence" => result.evidence,
      "limitations" => result.limitations
    }
  end
end
