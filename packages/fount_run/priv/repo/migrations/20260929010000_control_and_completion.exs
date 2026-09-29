defmodule FountRun.Repo.Migrations.ControlAndCompletion do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE fount_run_plans ADD COLUMN command_key text"
    execute "ALTER TABLE fount_run_plans ADD COLUMN command_fingerprint text"
    execute "ALTER TABLE fount_run_plans ADD CONSTRAINT fount_run_plan_command_shape CHECK ((command_key IS NULL AND command_fingerprint IS NULL) OR (command_key <> '' AND char_length(command_fingerprint)=64))"
    execute "CREATE UNIQUE INDEX fount_run_plan_command_once ON fount_run_plans(run_id,command_key) WHERE command_key IS NOT NULL"

    execute "ALTER TABLE fount_run_policies ADD COLUMN command_key text"
    execute "ALTER TABLE fount_run_policies ADD COLUMN command_fingerprint text"
    execute "ALTER TABLE fount_run_policies ADD CONSTRAINT fount_run_policy_command_shape CHECK ((command_key IS NULL AND command_fingerprint IS NULL) OR (command_key <> '' AND char_length(command_fingerprint)=64))"
    execute "CREATE UNIQUE INDEX fount_run_policy_command_once ON fount_run_policies(run_id,command_key) WHERE command_key IS NOT NULL"

    execute "ALTER TABLE fount_run_approval_attempts ADD COLUMN parent_attempt_id uuid"
    execute "ALTER TABLE fount_run_approval_attempts ADD COLUMN callback_response jsonb"
    execute "ALTER TABLE fount_run_approval_attempts ADD COLUMN callback_response_hash text CHECK (callback_response_hash IS NULL OR char_length(callback_response_hash)=64)"
    execute "ALTER TABLE fount_run_approval_attempts ADD CONSTRAINT fount_run_approval_callback_response_shape CHECK ((callback_response IS NULL AND callback_response_hash IS NULL) OR (callback_response IS NOT NULL AND callback_response_hash IS NOT NULL))"
    execute "ALTER TABLE fount_run_approval_attempts ADD CONSTRAINT fount_run_approval_parent_fk FOREIGN KEY (parent_attempt_id) REFERENCES fount_run_approval_attempts(id) DEFERRABLE INITIALLY DEFERRED"
    execute "ALTER TABLE fount_run_approval_attempts ADD CONSTRAINT fount_run_approval_parent_not_self CHECK (parent_attempt_id IS NULL OR parent_attempt_id <> id)"

    execute "DROP TRIGGER fount_run_approval_immutable ON fount_run_approval_attempts"
    execute "DROP FUNCTION fount_run_guard_approval_immutable()"

    execute ~S"""
CREATE FUNCTION fount_run_guard_approval_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF ROW(NEW.run_id,NEW.screenplay_id,NEW.step_id,NEW.decision_id,NEW.parent_attempt_id,NEW.plan_version,NEW.plan_fingerprint,NEW.policy_version,NEW.policy_fingerprint,NEW.candidate_id,NEW.base_revision_id,NEW.content_hash,NEW.check_set_fingerprint,NEW.packet,NEW.packet_artifact_ref,NEW.reviewer_type,NEW.reviewer_id,NEW.approver_type,NEW.approver_id,NEW.callback_operation_id,NEW.fencing_token) IS DISTINCT FROM ROW(OLD.run_id,OLD.screenplay_id,OLD.step_id,OLD.decision_id,OLD.parent_attempt_id,OLD.plan_version,OLD.plan_fingerprint,OLD.policy_version,OLD.policy_fingerprint,OLD.candidate_id,OLD.base_revision_id,OLD.content_hash,OLD.check_set_fingerprint,OLD.packet,OLD.packet_artifact_ref,OLD.reviewer_type,OLD.reviewer_id,OLD.approver_type,OLD.approver_id,OLD.callback_operation_id,OLD.fencing_token) THEN
    RAISE EXCEPTION 'approval attempt identity is immutable';
  END IF;
  IF OLD.callback_response IS NOT NULL AND (NEW.callback_response IS DISTINCT FROM OLD.callback_response OR NEW.callback_response_hash IS DISTINCT FROM OLD.callback_response_hash) THEN
    RAISE EXCEPTION 'callback response evidence is immutable';
  END IF;
  IF OLD.received_review IS NOT NULL AND (NEW.received_review IS DISTINCT FROM OLD.received_review OR NEW.review_hash IS DISTINCT FROM OLD.review_hash OR NEW.recommendation IS DISTINCT FROM OLD.recommendation) THEN
    RAISE EXCEPTION 'received approval review is immutable';
  END IF;
  IF OLD.approval_id IS NOT NULL AND (NEW.approval_id IS DISTINCT FROM OLD.approval_id OR NEW.approval_payload IS DISTINCT FROM OLD.approval_payload OR NEW.approval_hash IS DISTINCT FROM OLD.approval_hash) THEN
    RAISE EXCEPTION 'constructed approval payload is immutable';
  END IF;
  IF OLD.outcome IN ('accepted','rejected','invalid','fenced','failed') AND ROW(NEW.outcome,NEW.outcome_reason,NEW.acceptance_id,NEW.finished_at) IS DISTINCT FROM ROW(OLD.outcome,OLD.outcome_reason,OLD.acceptance_id,OLD.finished_at) THEN
    RAISE EXCEPTION 'terminal approval outcome is immutable';
  END IF;
  RETURN NEW;
END
$$
"""

    execute "CREATE TRIGGER fount_run_approval_immutable BEFORE UPDATE ON fount_run_approval_attempts FOR EACH ROW EXECUTE FUNCTION fount_run_guard_approval_immutable()"
  end

  def down do
    execute "DROP TRIGGER fount_run_approval_immutable ON fount_run_approval_attempts"
    execute "DROP FUNCTION fount_run_guard_approval_immutable()"

    execute "ALTER TABLE fount_run_approval_attempts DROP CONSTRAINT IF EXISTS fount_run_approval_callback_response_shape"
    execute "ALTER TABLE fount_run_approval_attempts DROP COLUMN IF EXISTS callback_response_hash"
    execute "ALTER TABLE fount_run_approval_attempts DROP COLUMN IF EXISTS callback_response"
    execute "ALTER TABLE fount_run_approval_attempts DROP CONSTRAINT IF EXISTS fount_run_approval_parent_not_self"
    execute "ALTER TABLE fount_run_approval_attempts DROP CONSTRAINT IF EXISTS fount_run_approval_parent_fk"
    execute "ALTER TABLE fount_run_approval_attempts DROP COLUMN IF EXISTS parent_attempt_id"

    execute "DROP INDEX IF EXISTS fount_run_policy_command_once"
    execute "ALTER TABLE fount_run_policies DROP CONSTRAINT IF EXISTS fount_run_policy_command_shape"
    execute "ALTER TABLE fount_run_policies DROP COLUMN IF EXISTS command_fingerprint"
    execute "ALTER TABLE fount_run_policies DROP COLUMN IF EXISTS command_key"

    execute "DROP INDEX IF EXISTS fount_run_plan_command_once"
    execute "ALTER TABLE fount_run_plans DROP CONSTRAINT IF EXISTS fount_run_plan_command_shape"
    execute "ALTER TABLE fount_run_plans DROP COLUMN IF EXISTS command_fingerprint"
    execute "ALTER TABLE fount_run_plans DROP COLUMN IF EXISTS command_key"

    execute ~S"""
CREATE FUNCTION fount_run_guard_approval_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF ROW(NEW.run_id,NEW.screenplay_id,NEW.step_id,NEW.decision_id,NEW.plan_version,NEW.plan_fingerprint,NEW.policy_version,NEW.policy_fingerprint,NEW.candidate_id,NEW.base_revision_id,NEW.content_hash,NEW.check_set_fingerprint,NEW.packet,NEW.packet_artifact_ref,NEW.reviewer_type,NEW.reviewer_id,NEW.approver_type,NEW.approver_id,NEW.callback_operation_id,NEW.fencing_token) IS DISTINCT FROM ROW(OLD.run_id,OLD.screenplay_id,OLD.step_id,OLD.decision_id,OLD.plan_version,OLD.plan_fingerprint,OLD.policy_version,OLD.policy_fingerprint,OLD.candidate_id,OLD.base_revision_id,OLD.content_hash,OLD.check_set_fingerprint,OLD.packet,OLD.packet_artifact_ref,OLD.reviewer_type,OLD.reviewer_id,OLD.approver_type,OLD.approver_id,OLD.callback_operation_id,OLD.fencing_token) THEN
    RAISE EXCEPTION 'approval attempt identity is immutable';
  END IF;
  IF OLD.received_review IS NOT NULL AND (NEW.received_review IS DISTINCT FROM OLD.received_review OR NEW.review_hash IS DISTINCT FROM OLD.review_hash OR NEW.recommendation IS DISTINCT FROM OLD.recommendation) THEN
    RAISE EXCEPTION 'received approval review is immutable';
  END IF;
  IF OLD.approval_id IS NOT NULL AND (NEW.approval_id IS DISTINCT FROM OLD.approval_id OR NEW.approval_payload IS DISTINCT FROM OLD.approval_payload OR NEW.approval_hash IS DISTINCT FROM OLD.approval_hash) THEN
    RAISE EXCEPTION 'constructed approval payload is immutable';
  END IF;
  IF OLD.outcome IN ('accepted','rejected','invalid','fenced','failed') AND ROW(NEW.outcome,NEW.outcome_reason,NEW.acceptance_id,NEW.finished_at) IS DISTINCT FROM ROW(OLD.outcome,OLD.outcome_reason,OLD.acceptance_id,OLD.finished_at) THEN
    RAISE EXCEPTION 'terminal approval outcome is immutable';
  END IF;
  RETURN NEW;
END
$$
"""

    execute "CREATE TRIGGER fount_run_approval_immutable BEFORE UPDATE ON fount_run_approval_attempts FOR EACH ROW EXECUTE FUNCTION fount_run_guard_approval_immutable()"
  end
end
