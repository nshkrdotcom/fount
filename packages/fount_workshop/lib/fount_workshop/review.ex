defmodule FountWorkshop.Review do
  @moduledoc "Builds a writer review packet and applies an explicit candidate decision."

  alias Fount.{Persistence, Screenplay}
  alias FountWorkshop.Writing.ReviewGate

  def export(session_id, directory, services, opts \\ []), do: FountWorkshop.ReviewExport.export(session_id, directory, services, opts)

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

      {:ok,
       %{
         "candidate_id" => candidate_id,
         "base_revision_id" => base.revision.id,
         "result_revision_id" => draft.revision.id,
         "content_hash" => draft.revision.content_hash,
         "original_fountain" => original,
         "proposed_fountain" => proposed,
         "source_diff" => String.myers_difference(original, proposed),
         "structural_diff" => Screenplay.diff(base, draft),
         "change_groups" => candidate["change_groups"],
         "lineage" => candidate["lineage"],
         "provenance" => candidate["provenance"],
         "checks" => candidate["provenance"]["checks"] || [],
         "report_ids" => candidate["provenance"]["report_ids"] || []
       }}
    end
  end

  @doc "Accepts only after the writer supplies a review matching exact candidate content."
  def accept(repo, candidate_id, expected_revision, review) do
    with {:ok, candidate} <- Persistence.candidate(repo, candidate_id),
         :ok <-
           ReviewGate.validate(
             %{
               "id" => candidate_id,
               "base_revision_id" => candidate["base_revision_id"],
               "content_hash" => candidate["screenplay"].revision.content_hash,
               "structural_errors" => [],
               "checks" => candidate["provenance"]["checks"] || [],
               "report_ids" => candidate["provenance"]["report_ids"] || []
             },
             review,
             expected_revision
           ) do
      Persistence.accept_candidate(repo, candidate_id,
        expected_revision: expected_revision,
        actor: review["actor"],
        review: review
      )
    end
  end

  def reject(repo, candidate_id, actor),
    do: Persistence.reject_candidate(repo, candidate_id, actor: actor)
end