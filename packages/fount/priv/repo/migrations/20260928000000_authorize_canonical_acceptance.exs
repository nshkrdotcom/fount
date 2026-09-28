defmodule Fount.Repo.Migrations.AuthorizeCanonicalAcceptance do
  use Ecto.Migration

  def up do
    alter table(:writing_candidates) do
      add :required_checks, :map, null: false, default: fragment("'[]'::jsonb")
      add :check_set_fingerprint, :text
      add :approval_id, :uuid
    end

    alter table(:acceptances) do
      add :acceptance_kind, :text
      add :approval_id, :uuid
      add :approval_hash, :text
      add :approval, :map
      add :approver_type, :text
      add :approver_id, :text
      add :reviewer_type, :text
      add :reviewer_id, :text
      add :review_hash, :text
      add :check_set_fingerprint, :text
      add :report_ids, :map
      add :run_id, :uuid
      add :run_policy_version, :integer
      add :run_policy_fingerprint, :text
    end

    execute """
    UPDATE acceptances
       SET acceptance_kind = CASE WHEN base_revision_id IS NULL THEN 'genesis' ELSE 'historical' END
    """

    execute "ALTER TABLE acceptances ALTER COLUMN acceptance_kind SET NOT NULL"
    execute "ALTER TABLE acceptances ADD CONSTRAINT acceptance_kind_valid CHECK (acceptance_kind IN ('genesis','approved','historical'))"
    execute "ALTER TABLE acceptances ADD CONSTRAINT approval_principal_type_valid CHECK (approver_type IS NULL OR approver_type IN ('human','agent','service'))"
    execute "ALTER TABLE acceptances ADD CONSTRAINT review_principal_type_valid CHECK (reviewer_type IS NULL OR reviewer_type IN ('human','agent','service'))"
    execute "ALTER TABLE acceptances ADD CONSTRAINT run_approval_provenance_all_or_none CHECK ((run_id IS NULL AND run_policy_version IS NULL AND run_policy_fingerprint IS NULL) OR (run_id IS NOT NULL AND run_policy_version IS NOT NULL AND run_policy_version > 0 AND run_policy_fingerprint IS NOT NULL))"
    execute """
    ALTER TABLE acceptances ADD CONSTRAINT approved_acceptance_complete CHECK (
      acceptance_kind <> 'approved' OR (
        base_revision_id IS NOT NULL AND candidate_id IS NOT NULL AND approval_id IS NOT NULL AND
        approval_hash IS NOT NULL AND approval IS NOT NULL AND approver_type IS NOT NULL AND
        approver_id IS NOT NULL AND reviewer_type IS NOT NULL AND reviewer_id IS NOT NULL AND
        review_hash IS NOT NULL AND check_set_fingerprint IS NOT NULL AND report_ids IS NOT NULL
      )
    )
    """
    execute "ALTER TABLE acceptances ADD CONSTRAINT nonapproved_has_no_approval_id CHECK (acceptance_kind = 'approved' OR approval_id IS NULL)"
    execute "CREATE UNIQUE INDEX acceptance_approval_once ON acceptances(approval_id)"
    execute "CREATE UNIQUE INDEX candidate_approval_once ON writing_candidates(approval_id)"
    execute "CREATE UNIQUE INDEX writing_candidate_result_identity ON writing_candidates(screenplay_id,id,result_revision_id)"
    execute "ALTER TABLE acceptances ADD CONSTRAINT acceptance_candidate_result_identity FOREIGN KEY (screenplay_id,candidate_id,result_revision_id) REFERENCES writing_candidates(screenplay_id,id,result_revision_id) DEFERRABLE INITIALLY DEFERRED"
    execute "ALTER TABLE writing_candidates ADD CONSTRAINT writing_candidate_approval_identity FOREIGN KEY (approval_id) REFERENCES acceptances(approval_id) DEFERRABLE INITIALLY DEFERRED"
  end

  def down do
    execute "ALTER TABLE writing_candidates DROP CONSTRAINT writing_candidate_approval_identity"
    execute "ALTER TABLE acceptances DROP CONSTRAINT acceptance_candidate_result_identity"
    execute "DROP INDEX writing_candidate_result_identity"
    execute "DROP INDEX candidate_approval_once"
    execute "DROP INDEX acceptance_approval_once"
    execute "ALTER TABLE acceptances DROP CONSTRAINT nonapproved_has_no_approval_id"
    execute "ALTER TABLE acceptances DROP CONSTRAINT approved_acceptance_complete"
    execute "ALTER TABLE acceptances DROP CONSTRAINT run_approval_provenance_all_or_none"
    execute "ALTER TABLE acceptances DROP CONSTRAINT review_principal_type_valid"
    execute "ALTER TABLE acceptances DROP CONSTRAINT approval_principal_type_valid"
    execute "ALTER TABLE acceptances DROP CONSTRAINT acceptance_kind_valid"

    alter table(:acceptances) do
      remove :run_policy_fingerprint
      remove :run_policy_version
      remove :run_id
      remove :report_ids
      remove :check_set_fingerprint
      remove :review_hash
      remove :reviewer_id
      remove :reviewer_type
      remove :approver_id
      remove :approver_type
      remove :approval
      remove :approval_hash
      remove :approval_id
      remove :acceptance_kind
    end

    alter table(:writing_candidates) do
      remove :approval_id
      remove :check_set_fingerprint
      remove :required_checks
    end
  end
end
