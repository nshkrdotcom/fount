defmodule Fount.Intelligence.Reporting.Report do
  @moduledoc "Revision-scoped analytical report. Completion describes inspected coverage, never screenplay quality or human agreement."
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON
  @contract %{"id" => "intelligence.report", "identity" => ~w(id playbook screenplay_id primary_revision_id source_revision_ids),
    "status" => ~w(complete partial failed), "records" => ~w(request definition coverage findings data evidence annotations graph provenance errors),
    "evidence" => "exact_revision_element_utf8_span_excerpt", "claim_basis" => "text_measurement_or_uncalibrated_interpretation"}
  defstruct [:id, :playbook, :screenplay_id, :primary_revision_id, :output_contract_id, :output_contract_sha256,
    source_revision_ids: [], status: "complete", request: %{}, definition: %{}, coverage: %{},
    findings: [], data: %{}, evidence: [], annotations: [], graph: %{}, provenance: %{}, errors: [], transient_models: []]
  @type t :: %__MODULE__{}

  def contract, do: @contract
  def contract_digest, do: CanonicalJSON.hash(@contract)
  def compatible?(payload) when is_map(payload),
    do: payload["output_contract_id"] == @contract["id"] and payload["output_contract_sha256"] == contract_digest()
  def compatible?(_), do: false

  def new(model, playbook, request, attrs \\ %{}) do
    struct(__MODULE__, Map.merge(%{id: Fount.ID.v4(), playbook: playbook,
      screenplay_id: model.id, primary_revision_id: model.revision.id,
      source_revision_ids: [model.revision.id], request: request,
      output_contract_id: @contract["id"], output_contract_sha256: contract_digest()}, attrs))
    |> bind_definition()
  end

  def relabel(%__MODULE__{} = report, playbook, request),
    do: bind_definition(%{report | playbook: playbook, request: request})

  def to_map(%__MODULE__{} = report), do: report |> Map.from_struct() |> Map.delete(:transient_models) |> Model.plain()

  def persistence(%__MODULE__{} = report, session_id \\ nil) do
    payload = to_map(report)
    payload = Map.put(payload, "citations", citations(Map.take(payload, ~w(findings data annotations graph))))
    %{id: report.id, screenplay_id: report.screenplay_id, primary_revision_id: report.primary_revision_id,
      source_revision_ids: report.source_revision_ids, session_id: session_id,
      # Fount's generic storage column is intentionally not an analytical wire contract.
      tool: report.playbook, status: report.status,
      fingerprint: CanonicalJSON.hash(%{"request" => report.request, "definition" => report.definition}), payload: payload}
  end

  def failure(model, playbook, params, reason) do
    new(model, playbook || "invalid_request", if(is_map(params), do: params, else: %{}),
      %{status: "failed", errors: [%{"code" => "request_failed", "reason" => safe_reason(reason)}]})
  end

  def citations(value) when is_map(value) do
    Enum.flat_map(value, fn
      {key, ids} when key in ["evidence_ids", "citations"] and is_list(ids) -> Enum.filter(ids, &is_binary/1)
      {_, nested} -> citations(nested)
    end) |> Enum.uniq()
  end
  def citations(value) when is_list(value), do: value |> Enum.flat_map(&citations/1) |> Enum.uniq()
  def citations(_), do: []

  defp bind_definition(report) do
    definition = %{"playbook" => report.playbook, "output_contract_sha256" => contract_digest(),
      "measurement_spec_sha256s" => question_hashes(report.provenance) |> Enum.uniq() |> Enum.sort()}
    %{report | definition: Map.put(definition, "sha256", CanonicalJSON.hash(definition))}
  end
  defp question_hashes(value) when is_map(value) do
    Enum.flat_map(value, fn
      {"measurement_spec_sha256", hash} when is_binary(hash) -> [hash]
      {_, nested} -> question_hashes(nested)
    end)
  end
  defp question_hashes(value) when is_list(value), do: Enum.flat_map(value, &question_hashes/1)
  defp question_hashes(_), do: []
  defp safe_reason(reason) when is_atom(reason), do: to_string(reason)
  defp safe_reason({reason, _}) when is_atom(reason), do: to_string(reason)
  defp safe_reason(_), do: "analysis_unavailable"
end
