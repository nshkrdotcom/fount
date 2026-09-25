defmodule FountProbe.Report do
  @moduledoc "Revision-scoped observations; completion describes scheduled coverage, not screenplay quality."
  defstruct [:id, :tool, :screenplay_id, :primary_revision_id, version: 1, source_revision_ids: [],
    status: "complete", request: %{}, profile: %{}, coverage: %{}, findings: [], data: %{},
    evidence: [], annotations: [], graph: %{}, provenance: %{}, errors: [], transient_models: []]

  def new(model, tool, request, attrs \\ %{}) do
    provenance = Map.get(attrs, :provenance, %{})
    hashes = question_hashes(provenance) |> Enum.uniq() |> Enum.sort()
    definition = %{"tool" => tool, "version" => 1, "question_profile_sha256s" => hashes}
    profile = %{"id" => to_string(tool || "invalid_request") <> ":v1", "version" => 1,
      "sha256" => Fount.Writing.CanonicalJSON.hash(definition), "definition" => definition,
      "identity_scope" => if(hashes == [], do: "deterministic_tool_version_or_completion_trace", else: "effective_question_definitions")}
    struct(__MODULE__, Map.merge(%{id: Fount.ID.v4(), tool: tool, screenplay_id: model.id,
      primary_revision_id: model.revision.id, source_revision_ids: [model.revision.id], request: request, profile: profile}, attrs))
  end
  def to_map(report), do: report |> Map.from_struct() |> Map.delete(:transient_models) |> Fount.Screenplay.Model.plain()
  def persistence(report, session_id \\ nil) do
    payload = to_map(report)
    payload = Map.put(payload, "citations", citations(Map.take(payload, ~w(findings data annotations graph))))
    %{id: report.id, screenplay_id: report.screenplay_id, primary_revision_id: report.primary_revision_id,
      source_revision_ids: report.source_revision_ids, session_id: session_id, tool: report.tool,
      status: report.status, fingerprint: Fount.Writing.CanonicalJSON.hash(%{"request" => report.request, "profile" => report.profile}), payload: payload}
  end
  defp question_hashes(value) when is_map(value) do
    Enum.flat_map(value, fn
      {"question_profile_sha256", hash} when is_binary(hash) -> [hash]
      {_, nested} -> question_hashes(nested)
    end)
  end
  defp question_hashes(value) when is_list(value), do: Enum.flat_map(value, &question_hashes/1)
  defp question_hashes(_), do: []
  defp citations(value) when is_map(value) do
    Enum.flat_map(value, fn
      {"evidence_ids", ids} when is_list(ids) -> ids
      {"citations", ids} when is_list(ids) -> Enum.filter(ids, &is_binary/1)
      {_, nested} -> citations(nested)
    end) |> Enum.uniq()
  end
  defp citations(value) when is_list(value), do: value |> Enum.flat_map(&citations/1) |> Enum.uniq()
  defp citations(_), do: []
  def failure(model, tool, params, reason), do: new(model, tool || "invalid_request", params, %{status: "failed", errors: [%{"code" => "request_failed", "message" => inspect(reason, limit: 20)}]})
end
