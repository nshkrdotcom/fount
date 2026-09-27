defmodule Fount.Intelligence.Diagnosis.EvidenceNeed do
  @moduledoc "Pure description of evidence the shell may acquire. It names logical measurements, never providers."

  alias Fount.Writing.CanonicalJSON

  @enforce_keys [:id, :measurement, :hypothesis_id, :reason]
  defstruct [
    :id,
    :measurement,
    :hypothesis_id,
    :reason,
    evidence_ids: [],
    context_requirements: [],
    optional: false
  ]

  @type t :: %__MODULE__{}

  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(attrs) when is_map(attrs) do
    measurement = get(attrs, "measurement")
    hypothesis_id = get(attrs, "hypothesis_id")
    reason = get(attrs, "reason")
    evidence_ids = get(attrs, "evidence_ids") || []
    context_requirements = get(attrs, "context_requirements") || []
    optional = get(attrs, "optional") || false

    with true <- text?(measurement),
         true <- text?(hypothesis_id),
         true <- text?(reason),
         true <- strings?(evidence_ids),
         true <- strings?(context_requirements),
         true <- is_boolean(optional) do
      identity = %{
        "measurement" => measurement,
        "hypothesis_id" => hypothesis_id,
        "reason" => reason,
        "evidence_ids" => evidence_ids,
        "context_requirements" => context_requirements,
        "optional" => optional
      }

      id = get(attrs, "id") || "need-" <> String.slice(CanonicalJSON.hash(identity), 0, 24)

      if text?(id) do
        {:ok,
         %__MODULE__{
           id: id,
           measurement: measurement,
           hypothesis_id: hypothesis_id,
           reason: reason,
           evidence_ids: Enum.uniq(evidence_ids),
           context_requirements: Enum.uniq(context_requirements),
           optional: optional
         }}
      else
        {:error, :invalid_evidence_need}
      end
    else
      _ -> {:error, :invalid_evidence_need}
    end
  rescue
    _ -> {:error, :invalid_evidence_need}
  end

  def new(_), do: {:error, :invalid_evidence_need}

  def to_map(%__MODULE__{} = need) do
    %{
      "id" => need.id,
      "measurement" => need.measurement,
      "hypothesis_id" => need.hypothesis_id,
      "reason" => need.reason,
      "evidence_ids" => need.evidence_ids,
      "context_requirements" => need.context_requirements,
      "optional" => need.optional
    }
  end

  defp get(map, "measurement"), do: Map.get(map, "measurement", Map.get(map, :measurement))
  defp get(map, "hypothesis_id"), do: Map.get(map, "hypothesis_id", Map.get(map, :hypothesis_id))
  defp get(map, "reason"), do: Map.get(map, "reason", Map.get(map, :reason))
  defp get(map, "evidence_ids"), do: Map.get(map, "evidence_ids", Map.get(map, :evidence_ids))

  defp get(map, "context_requirements"),
    do: Map.get(map, "context_requirements", Map.get(map, :context_requirements))

  defp get(map, "optional"), do: Map.get(map, "optional", Map.get(map, :optional))
  defp get(map, "id"), do: Map.get(map, "id", Map.get(map, :id))
  defp text?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp strings?(values), do: is_list(values) and Enum.all?(values, &text?/1)
end
