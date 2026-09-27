defmodule Fount.Intelligence.Reporting.WriterPacket do
  @moduledoc "Normative writer-facing Phase-5 result packet. Evidence, derived state, diagnosis, strategy, and candidate material remain separate."

  alias Fount.Writing.CanonicalJSON

  @contract %{
    "id" => "intelligence.writer_result_packet",
    "status" => ["complete", "partial", "failed"],
    "claim_classes" => [
      "canonical_fact",
      "derived_narrative_state",
      "model_estimated_interpretation",
      "human_calibrated_response_estimate"
    ],
    "separation" => ["evidence", "derived_state", "diagnoses", "strategies", "candidate"],
    "required_semantic_sections" => [
      "concern",
      "scope",
      "intent",
      "finding",
      "claim_class",
      "coverage",
      "evidence",
      "derived_state",
      "trajectory",
      "diagnoses",
      "abstentions",
      "counterevidence",
      "alternatives",
      "uncertainty",
      "missing_evidence",
      "protected_strengths",
      "next_investigations",
      "strategies",
      "revision_comparison",
      "resource_usage",
      "errors",
      "provenance",
      "limitations"
    ],
    "human_calibration_required_for" => "human_calibrated_response_estimate"
  }

  @enforce_keys [:id, :playbook, :source_revision, :concern]
  defstruct [
    :id,
    :playbook,
    :source_revision,
    :concern,
    :output_contract_id,
    :output_contract_sha256,
    status: "complete",
    scope: %{},
    intent: %{},
    finding: nil,
    claim_class: "model_estimated_interpretation",
    coverage: %{},
    evidence: [],
    derived_state: %{},
    trajectory: [],
    diagnoses: [],
    abstentions: [],
    counterevidence: [],
    alternatives: [],
    uncertainty: [],
    missing_evidence: [],
    protected_strengths: [],
    next_investigations: [],
    strategies: [],
    revision_comparison: nil,
    resource_usage: %{},
    errors: [],
    provenance: %{},
    limitations: [],
    candidate: nil
  ]

  @type t :: %__MODULE__{}

  def contract, do: @contract
  def contract_digest, do: CanonicalJSON.hash(@contract)

  def new(playbook, source_revision, concern, attrs \\ %{})
      when is_binary(playbook) and is_binary(source_revision) and is_map(concern) and is_map(attrs) do
    base = %{
      "playbook" => playbook,
      "source_revision" => source_revision,
      "concern" => concern,
      "coverage" => Map.get(attrs, :coverage, Map.get(attrs, "coverage", %{})),
      "diagnoses" => Map.get(attrs, :diagnoses, Map.get(attrs, "diagnoses", []))
    }

    id = "writer-packet-" <> String.slice(CanonicalJSON.hash(base), 0, 24)

    values =
      attrs
      |> stringify_keys()
      |> Map.put("id", id)
      |> Map.put("playbook", playbook)
      |> Map.put("source_revision", source_revision)
      |> Map.put("concern", concern)
      |> Map.put("output_contract_id", @contract["id"])
      |> Map.put("output_contract_sha256", contract_digest())

    {:ok, struct!(__MODULE__, atom_keys(values))}
  rescue
    _ -> {:error, :invalid_writer_packet}
  end

  def new(_, _, _, _), do: {:error, :invalid_writer_packet}

  def compatible?(%__MODULE__{} = packet),
    do:
      packet.output_contract_id == @contract["id"] and
        packet.output_contract_sha256 == contract_digest()

  def compatible?(_), do: false

  def to_map(%__MODULE__{} = packet) do
    packet
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), plain(value)} end)
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  @field_names %{
    "id" => :id,
    "playbook" => :playbook,
    "source_revision" => :source_revision,
    "concern" => :concern,
    "output_contract_id" => :output_contract_id,
    "output_contract_sha256" => :output_contract_sha256,
    "status" => :status,
    "scope" => :scope,
    "intent" => :intent,
    "finding" => :finding,
    "claim_class" => :claim_class,
    "coverage" => :coverage,
    "evidence" => :evidence,
    "derived_state" => :derived_state,
    "trajectory" => :trajectory,
    "diagnoses" => :diagnoses,
    "abstentions" => :abstentions,
    "counterevidence" => :counterevidence,
    "alternatives" => :alternatives,
    "uncertainty" => :uncertainty,
    "missing_evidence" => :missing_evidence,
    "protected_strengths" => :protected_strengths,
    "next_investigations" => :next_investigations,
    "strategies" => :strategies,
    "revision_comparison" => :revision_comparison,
    "resource_usage" => :resource_usage,
    "errors" => :errors,
    "provenance" => :provenance,
    "limitations" => :limitations,
    "candidate" => :candidate
  }

  defp atom_keys(map) do
    Map.new(map, fn {key, value} -> {Map.fetch!(@field_names, key), value} end)
  end

  defp plain(%{__struct__: module} = value) when module == __MODULE__, do: to_map(value)
  defp plain(%{__struct__: _}), do: raise(ArgumentError, "writer packet cannot contain runtime structs")
  defp plain(map) when is_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), plain(value)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(value), do: value
end
