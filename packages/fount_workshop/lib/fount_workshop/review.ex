defmodule FountWorkshop.Review do
  @moduledoc "Builds a writer review packet and applies an explicit candidate decision."
  alias Fount.Persistence
  alias Fount.Screenplay
  alias FountWorkshop.Comparison

  def export(session_id, directory, services, opts \\ []),
    do: FountWorkshop.ReviewExport.export(session_id, directory, services, opts)

  @doc "Loads actual base and candidate pages with source and structural changes."
  def packet(repo, candidate_id) do
    with {:ok, candidate} <- Persistence.candidate(repo, candidate_id),
         {:ok, base} <-
           Persistence.load_revision(
             repo,
             candidate["screenplay_id"],
             candidate["base_revision_id"]
           ) do
      draft = candidate["screenplay"]
      original = Screenplay.to_fountain(base)
      proposed = Screenplay.to_fountain(draft)

      packet = %{
        "screenplay_id" => candidate["screenplay_id"],
        "candidate_id" => candidate_id,
        "base_revision_id" => base.revision.id,
        "result_revision_id" => draft.revision.id,
        "content_hash" => draft.revision.content_hash,
        "original_fountain" => original,
        "proposed_fountain" => proposed,
        "source_diff" => String.myers_difference(original, proposed),
        "structural_diff" => Screenplay.diff(base, draft),
        "comparison" => Comparison.compare(base, candidate),
        "change_groups" => candidate["change_groups"],
        "lineage" => candidate["lineage"],
        "provenance" => candidate["provenance"],
        "checks" => candidate["provenance"]["checks"] || [],
        "required_checks" => candidate["required_checks"] || [],
        "check_set_fingerprint" => candidate["check_set_fingerprint"],
        "report_ids" => candidate["provenance"]["report_ids"] || []
      }

      {:ok, Map.merge(packet, intelligence_fields(candidate))}
    end
  end

  defp intelligence_fields(candidate) do
    lineage = get_in(candidate, ["provenance", "intelligence_lineage"]) || %{}
    provenance = candidate["provenance"]

    %{
      "writer_packet" => fallback(lineage["pre_analysis_packet"], %{}),
      "revision_packet" => fallback(provenance["revision_intelligence"], %{}),
      "strategy_lineage" => fallback(lineage["strategy_lineage"], %{}),
      "note_triage" => fallback(lineage["note_triage"], []),
      "resource_usage" => fallback(provenance["resource_usage"], %{}),
      "consequence_proposals" => fallback(lineage["consequence_proposals"], []),
      "causal_ripple" =>
        fallback(
          get_in(candidate, [
            "provenance",
            "revision_intelligence",
            "revision_comparison",
            "causal_ripple"
          ]),
          %{}
        ),
      "note_decisions" => fallback(lineage["note_decisions"], []),
      "phase14" => fallback(lineage["phase14"], %{})
    }
  end

  defp fallback(nil, default), do: default
  defp fallback(value, _default), do: value

  @doc "Accepts only with a typed stable approval and trusted host authority."
  def accept(repo, candidate_id, %Fount.Writing.Approval{} = approval, %Fount.Writing.Authority{} = authority),
    do: Persistence.accept_candidate(repo, candidate_id, approval: approval, authority: authority)

  def accept(_repo, _candidate_id, _legacy_expected_revision, _legacy_review),
    do: {:error, :authorized_approval_required}

  def reject(repo, candidate_id, actor),
    do: Persistence.reject_candidate(repo, candidate_id, actor: actor)
end