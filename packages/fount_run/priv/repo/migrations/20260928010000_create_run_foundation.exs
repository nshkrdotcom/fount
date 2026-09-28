defmodule FountRun.Repo.Migrations.CreateRunFoundation do
  use Ecto.Migration

  def up do
    execute ~S"""
CREATE TABLE fount_runs (
  id uuid PRIMARY KEY,
  owner_type text NOT NULL CHECK (owner_type IN ('human','agent','service')),
  owner_id text NOT NULL CHECK (owner_id <> ''),
  screenplay_id uuid NOT NULL REFERENCES screenplays(id),
  client_idempotency_key text NOT NULL CHECK (client_idempotency_key <> ''),
  input_fingerprint text NOT NULL CHECK (char_length(input_fingerprint)=64),
  current_plan_version integer NOT NULL CHECK (current_plan_version > 0),
  current_policy_version integer NOT NULL CHECK (current_policy_version > 0),
  status text NOT NULL CHECK (status IN ('queued','running','paused','waiting_for_decision','waiting_for_approval','partial','completed_candidate','completed_accepted','stopped','failed')),
  stage text NOT NULL CHECK (stage IN ('intake','investigate','plan','write','check','iterate','decide','deliver')),
  iteration integer NOT NULL DEFAULT 0 CHECK (iteration >= 0),
  selected_candidate_id uuid,
  active_step_id uuid,
  current_fencing_token bigint NOT NULL DEFAULT 0 CHECK (current_fencing_token >= 0),
  parent_run_id uuid,
  superseding_run_id uuid,
  lock_version integer NOT NULL DEFAULT 1 CHECK (lock_version > 0),
  pause_requested_at timestamptz,
  stop_requested_at timestamptz,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (screenplay_id,id),
  UNIQUE (owner_type,owner_id,client_idempotency_key),
  FOREIGN KEY (screenplay_id,selected_candidate_id) REFERENCES writing_candidates(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,parent_run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,superseding_run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  CHECK (parent_run_id IS NULL OR parent_run_id <> id),
  CHECK (superseding_run_id IS NULL OR superseding_run_id <> id)
)
"""

    execute ~S"""
CREATE TABLE fount_run_plans (
  run_id uuid NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  screenplay_id uuid NOT NULL,
  base_revision_id uuid NOT NULL,
  goal text NOT NULL CHECK (goal <> ''),
  scope jsonb NOT NULL CHECK (jsonb_typeof(scope)='object'),
  constraints jsonb NOT NULL CHECK (jsonb_typeof(constraints)='array'),
  protected_material jsonb NOT NULL CHECK (jsonb_typeof(protected_material)='array'),
  input_brief jsonb CHECK (input_brief IS NULL OR jsonb_typeof(input_brief)='object'),
  input_notes jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(input_notes)='array'),
  operation_parameters jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(operation_parameters)='object'),
  fingerprint text NOT NULL CHECK (char_length(fingerprint)=64),
  author_type text NOT NULL CHECK (author_type IN ('human','agent','service')),
  author_id text NOT NULL CHECK (author_id <> ''),
  change_reason text NOT NULL CHECK (change_reason <> ''),
  inserted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_id,version),
  UNIQUE (run_id,version,fingerprint),
  FOREIGN KEY (screenplay_id,run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,base_revision_id) REFERENCES revisions(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED
)
"""

    execute ~S"""
CREATE TABLE fount_run_policies (
  run_id uuid NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  policy jsonb NOT NULL CHECK (jsonb_typeof(policy)='object'),
  fingerprint text NOT NULL CHECK (char_length(fingerprint)=64),
  author_type text NOT NULL CHECK (author_type IN ('human','agent','service')),
  author_id text NOT NULL CHECK (author_id <> ''),
  inserted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_id,version),
  UNIQUE (run_id,version,fingerprint),
  FOREIGN KEY (run_id) REFERENCES fount_runs(id) DEFERRABLE INITIALLY DEFERRED
)
"""

    execute "ALTER TABLE fount_runs ADD CONSTRAINT fount_run_current_plan_fk FOREIGN KEY (id,current_plan_version) REFERENCES fount_run_plans(run_id,version) DEFERRABLE INITIALLY DEFERRED"
    execute "ALTER TABLE fount_runs ADD CONSTRAINT fount_run_current_policy_fk FOREIGN KEY (id,current_policy_version) REFERENCES fount_run_policies(run_id,version) DEFERRABLE INITIALLY DEFERRED"

    execute ~S"""
CREATE TABLE fount_run_steps (
  id uuid PRIMARY KEY,
  run_id uuid NOT NULL,
  screenplay_id uuid NOT NULL,
  plan_version integer NOT NULL CHECK (plan_version > 0),
  policy_version integer NOT NULL CHECK (policy_version > 0),
  stage text NOT NULL CHECK (stage IN ('intake','investigate','plan','write','check','iterate','decide','deliver')),
  iteration integer NOT NULL DEFAULT 0 CHECK (iteration >= 0),
  branch_id text NOT NULL DEFAULT 'main' CHECK (branch_id <> ''),
  input_revision_id uuid,
  input_candidate_id uuid,
  request jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(request)='object'),
  request_fingerprint text NOT NULL CHECK (char_length(request_fingerprint)=64),
  idempotency_key text NOT NULL CHECK (idempotency_key <> ''),
  session_id uuid,
  output_candidate_id uuid,
  output_revision_id uuid,
  output_report_ids jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(output_report_ids)='array'),
  status text NOT NULL CHECK (status IN ('queued','claimed','running','waiting','succeeded','failed','cancelled','fenced')),
  lease_owner text,
  lease_token bigint CHECK (lease_token IS NULL OR lease_token >= 0),
  lease_expires_at timestamptz,
  heartbeat_at timestamptz,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (run_id,id),
  UNIQUE (run_id,idempotency_key),
  FOREIGN KEY (screenplay_id,run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,plan_version) REFERENCES fount_run_plans(run_id,version) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,policy_version) REFERENCES fount_run_policies(run_id,version) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,input_revision_id) REFERENCES revisions(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,input_candidate_id) REFERENCES writing_candidates(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,session_id) REFERENCES writing_sessions(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,output_candidate_id) REFERENCES writing_candidates(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,output_revision_id) REFERENCES revisions(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  CHECK ((lease_owner IS NULL AND lease_token IS NULL AND lease_expires_at IS NULL) OR (lease_owner IS NOT NULL AND lease_token IS NOT NULL AND lease_expires_at IS NOT NULL))
)
"""
    execute "ALTER TABLE fount_runs ADD CONSTRAINT fount_run_active_step_fk FOREIGN KEY (id,active_step_id) REFERENCES fount_run_steps(run_id,id) DEFERRABLE INITIALLY DEFERRED"

    execute ~S"""
CREATE TABLE fount_run_attempts (
  step_id uuid NOT NULL,
  run_id uuid NOT NULL,
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  fencing_token bigint NOT NULL CHECK (fencing_token >= 0),
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  outcome text NOT NULL CHECK (outcome IN ('running','succeeded','failed','unknown','cancelled','fenced')),
  redacted_error jsonb,
  provider_request_id text,
  PRIMARY KEY (step_id,attempt_number),
  FOREIGN KEY (run_id,step_id) REFERENCES fount_run_steps(run_id,id) DEFERRABLE INITIALLY DEFERRED,
  CHECK ((outcome='running' AND ended_at IS NULL) OR (outcome<>'running' AND ended_at IS NOT NULL))
)
"""

    execute ~S"""
CREATE TABLE fount_run_events (
  id uuid PRIMARY KEY,
  run_id uuid NOT NULL,
  screenplay_id uuid NOT NULL,
  sequence bigint NOT NULL CHECK (sequence > 0),
  step_id uuid,
  attempt_number integer,
  actor_type text NOT NULL CHECK (actor_type IN ('human','agent','service')),
  actor_id text NOT NULL CHECK (actor_id <> ''),
  plan_version integer NOT NULL CHECK (plan_version > 0),
  policy_version integer NOT NULL CHECK (policy_version > 0),
  event_type text NOT NULL CHECK (event_type <> ''),
  payload jsonb NOT NULL,
  payload_fingerprint text NOT NULL CHECK (char_length(payload_fingerprint)=64),
  safe_summary text NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (run_id,sequence),
  FOREIGN KEY (screenplay_id,run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,plan_version) REFERENCES fount_run_plans(run_id,version) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,policy_version) REFERENCES fount_run_policies(run_id,version) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,step_id) REFERENCES fount_run_steps(run_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (step_id,attempt_number) REFERENCES fount_run_attempts(step_id,attempt_number) DEFERRABLE INITIALLY DEFERRED,
  CHECK ((step_id IS NULL AND attempt_number IS NULL) OR step_id IS NOT NULL)
)
"""

    execute ~S"""
CREATE TABLE fount_run_decisions (
  id uuid PRIMARY KEY,
  run_id uuid NOT NULL,
  screenplay_id uuid NOT NULL,
  step_id uuid,
  plan_version integer NOT NULL CHECK (plan_version > 0),
  policy_version integer NOT NULL CHECK (policy_version > 0),
  checkpoint_key text NOT NULL CHECK (checkpoint_key <> ''),
  kind text NOT NULL CHECK (kind <> ''),
  prompt text NOT NULL CHECK (prompt <> ''),
  options jsonb NOT NULL CHECK (jsonb_typeof(options)='array' AND jsonb_array_length(options)>0),
  candidate_id uuid,
  base_revision_id uuid,
  content_hash text CHECK (content_hash IS NULL OR char_length(content_hash)=64),
  check_set_fingerprint text CHECK (check_set_fingerprint IS NULL OR char_length(check_set_fingerprint)=64),
  context_fingerprint text NOT NULL CHECK (char_length(context_fingerprint)=64),
  status text NOT NULL CHECK (status IN ('pending','resolved','superseded')),
  authorized_type text NOT NULL CHECK (authorized_type IN ('human','agent','service')),
  authorized_id text NOT NULL CHECK (authorized_id <> ''),
  response jsonb,
  response_fingerprint text CHECK (response_fingerprint IS NULL OR char_length(response_fingerprint)=64),
  respondent_type text CHECK (respondent_type IS NULL OR respondent_type IN ('human','agent','service')),
  respondent_id text,
  resolved_at timestamptz,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (run_id,id),
  UNIQUE (run_id,checkpoint_key),
  FOREIGN KEY (screenplay_id,run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,step_id) REFERENCES fount_run_steps(run_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,plan_version) REFERENCES fount_run_plans(run_id,version) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,policy_version) REFERENCES fount_run_policies(run_id,version) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,candidate_id) REFERENCES writing_candidates(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,base_revision_id) REFERENCES revisions(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  CHECK ((status='pending' AND response IS NULL AND respondent_type IS NULL AND respondent_id IS NULL AND resolved_at IS NULL) OR (status='resolved' AND response IS NOT NULL AND response_fingerprint IS NOT NULL AND respondent_type IS NOT NULL AND respondent_id IS NOT NULL AND resolved_at IS NOT NULL) OR status='superseded')
)
"""

    execute "CREATE UNIQUE INDEX fount_run_acceptance_identity ON acceptances(screenplay_id,id)"

    execute ~S"""
CREATE TABLE fount_run_approval_attempts (
  id uuid PRIMARY KEY,
  run_id uuid NOT NULL,
  screenplay_id uuid NOT NULL,
  step_id uuid,
  decision_id uuid,
  plan_version integer NOT NULL CHECK (plan_version > 0),
  plan_fingerprint text NOT NULL CHECK (char_length(plan_fingerprint)=64),
  policy_version integer NOT NULL CHECK (policy_version > 0),
  policy_fingerprint text NOT NULL CHECK (char_length(policy_fingerprint)=64),
  candidate_id uuid NOT NULL,
  base_revision_id uuid NOT NULL,
  content_hash text NOT NULL CHECK (char_length(content_hash)=64),
  check_set_fingerprint text NOT NULL CHECK (char_length(check_set_fingerprint)=64),
  packet jsonb,
  packet_artifact_ref text,
  reviewer_type text NOT NULL CHECK (reviewer_type IN ('human','agent','service')),
  reviewer_id text NOT NULL CHECK (reviewer_id <> ''),
  approver_type text NOT NULL CHECK (approver_type IN ('human','agent','service')),
  approver_id text NOT NULL CHECK (approver_id <> ''),
  callback_operation_id text NOT NULL UNIQUE CHECK (callback_operation_id <> ''),
  fencing_token bigint NOT NULL CHECK (fencing_token >= 0),
  received_review jsonb,
  review_hash text CHECK (review_hash IS NULL OR char_length(review_hash)=64),
  recommendation text,
  approval_id text UNIQUE,
  approval_payload jsonb,
  approval_hash text CHECK (approval_hash IS NULL OR char_length(approval_hash)=64),
  outcome text NOT NULL CHECK (outcome IN ('pending','reviewed','ready','accepted','rejected','invalid','fenced','failed','unknown')),
  outcome_reason text,
  acceptance_id uuid,
  finished_at timestamptz,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (screenplay_id,run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,step_id) REFERENCES fount_run_steps(run_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,decision_id) REFERENCES fount_run_decisions(run_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,plan_version,plan_fingerprint) REFERENCES fount_run_plans(run_id,version,fingerprint) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,policy_version,policy_fingerprint) REFERENCES fount_run_policies(run_id,version,fingerprint) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,candidate_id) REFERENCES writing_candidates(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,base_revision_id) REFERENCES revisions(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,acceptance_id) REFERENCES acceptances(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  CHECK ((packet IS NULL) <> (packet_artifact_ref IS NULL)),
  CHECK ((received_review IS NULL AND review_hash IS NULL AND recommendation IS NULL) OR (received_review IS NOT NULL AND review_hash IS NOT NULL AND recommendation IS NOT NULL)),
  CHECK ((approval_id IS NULL AND approval_payload IS NULL AND approval_hash IS NULL) OR (approval_id IS NOT NULL AND approval_payload IS NOT NULL AND approval_hash IS NOT NULL)),
  CHECK ((outcome='accepted' AND acceptance_id IS NOT NULL AND approval_id IS NOT NULL) OR (outcome<>'accepted' AND acceptance_id IS NULL))
)
"""
    execute "CREATE UNIQUE INDEX fount_run_human_approval_decision_once ON fount_run_approval_attempts(decision_id) WHERE decision_id IS NOT NULL"

    execute ~S"""
CREATE TABLE fount_run_usage (
  id uuid PRIMARY KEY,
  operation_id text NOT NULL CHECK (operation_id <> ''),
  run_id uuid NOT NULL,
  screenplay_id uuid NOT NULL,
  step_id uuid,
  attempt_number integer,
  session_id uuid,
  provider_request_id text,
  resource text NOT NULL CHECK (resource <> ''),
  reserved_quantity bigint NOT NULL CHECK (reserved_quantity >= 0),
  settled_quantity bigint CHECK (settled_quantity IS NULL OR settled_quantity >= 0),
  currency text CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
  reserved_cost_microunits bigint CHECK (reserved_cost_microunits IS NULL OR reserved_cost_microunits >= 0),
  settled_cost_microunits bigint CHECK (settled_cost_microunits IS NULL OR settled_cost_microunits >= 0),
  knowledge_state text NOT NULL CHECK (knowledge_state IN ('known','estimated','unknown')),
  reconciliation_state text NOT NULL CHECK (reconciliation_state IN ('reserved','settled','released','unknown')),
  settled_at timestamptz,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (operation_id,resource),
  FOREIGN KEY (screenplay_id,run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,step_id) REFERENCES fount_run_steps(run_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (step_id,attempt_number) REFERENCES fount_run_attempts(step_id,attempt_number) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,session_id) REFERENCES writing_sessions(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  CHECK ((reserved_cost_microunits IS NULL AND settled_cost_microunits IS NULL) OR currency IS NOT NULL),
  CHECK ((reconciliation_state='reserved' AND settled_quantity IS NULL AND settled_at IS NULL) OR (reconciliation_state<>'reserved' AND settled_quantity IS NOT NULL AND settled_at IS NOT NULL)),
  CHECK (attempt_number IS NULL OR step_id IS NOT NULL)
)
"""

    execute ~S"""
CREATE TABLE fount_run_deliveries (
  id uuid PRIMARY KEY,
  run_id uuid NOT NULL,
  screenplay_id uuid NOT NULL,
  candidate_id uuid,
  accepted_revision_id uuid,
  format text NOT NULL CHECK (format <> ''),
  options jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(options)='object'),
  options_fingerprint text NOT NULL CHECK (char_length(options_fingerprint)=64),
  delivery_key text NOT NULL UNIQUE CHECK (char_length(delivery_key)=64),
  output_checksum text CHECK (output_checksum IS NULL OR char_length(output_checksum)=64),
  output_location text,
  state text NOT NULL CHECK (state IN ('pending','ready','failed')),
  error text,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (screenplay_id,run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,candidate_id) REFERENCES writing_candidates(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (screenplay_id,accepted_revision_id) REFERENCES acceptances(screenplay_id,result_revision_id) DEFERRABLE INITIALLY DEFERRED,
  CHECK ((candidate_id IS NULL) <> (accepted_revision_id IS NULL)),
  CHECK ((state='pending' AND output_checksum IS NULL AND output_location IS NULL AND error IS NULL) OR (state='ready' AND output_checksum IS NOT NULL AND output_location IS NOT NULL AND error IS NULL) OR (state='failed' AND error IS NOT NULL))
)
"""

    execute "CREATE INDEX fount_runs_runnable ON fount_runs(status,stage,inserted_at) WHERE status IN ('queued','running')"
    execute "CREATE INDEX fount_run_step_leases ON fount_run_steps(lease_expires_at) WHERE lease_owner IS NOT NULL"
    execute "CREATE INDEX fount_run_pending_decisions ON fount_run_decisions(run_id,inserted_at) WHERE status='pending'"
    execute "CREATE INDEX fount_run_approval_reconciliation ON fount_run_approval_attempts(run_id,outcome,inserted_at) WHERE outcome IN ('pending','reviewed','ready','unknown')"
    execute "CREATE INDEX fount_run_timeline ON fount_run_events(run_id,sequence)"
    execute "CREATE INDEX fount_run_usage_by_run ON fount_run_usage(run_id,resource,inserted_at)"

    execute ~S"""
CREATE FUNCTION fount_run_reject_snapshot_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'fount run snapshots/events are append-only';
END
$$
"""
    execute "CREATE TRIGGER fount_run_plans_append_only BEFORE UPDATE OR DELETE ON fount_run_plans FOR EACH ROW EXECUTE FUNCTION fount_run_reject_snapshot_mutation()"
    execute "CREATE TRIGGER fount_run_policies_append_only BEFORE UPDATE OR DELETE ON fount_run_policies FOR EACH ROW EXECUTE FUNCTION fount_run_reject_snapshot_mutation()"
    execute "CREATE TRIGGER fount_run_events_append_only BEFORE UPDATE OR DELETE ON fount_run_events FOR EACH ROW EXECUTE FUNCTION fount_run_reject_snapshot_mutation()"

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

    execute ~S"""
CREATE FUNCTION fount_run_guard_decision_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF ROW(NEW.run_id,NEW.screenplay_id,NEW.step_id,NEW.plan_version,NEW.policy_version,NEW.checkpoint_key,NEW.kind,NEW.prompt,NEW.options,NEW.candidate_id,NEW.base_revision_id,NEW.content_hash,NEW.check_set_fingerprint,NEW.context_fingerprint,NEW.authorized_type,NEW.authorized_id) IS DISTINCT FROM ROW(OLD.run_id,OLD.screenplay_id,OLD.step_id,OLD.plan_version,OLD.policy_version,OLD.checkpoint_key,OLD.kind,OLD.prompt,OLD.options,OLD.candidate_id,OLD.base_revision_id,OLD.content_hash,OLD.check_set_fingerprint,OLD.context_fingerprint,OLD.authorized_type,OLD.authorized_id) THEN
    RAISE EXCEPTION 'decision checkpoint identity is immutable';
  END IF;
  IF OLD.status <> 'pending' AND ROW(NEW.status,NEW.response,NEW.response_fingerprint,NEW.respondent_type,NEW.respondent_id,NEW.resolved_at) IS DISTINCT FROM ROW(OLD.status,OLD.response,OLD.response_fingerprint,OLD.respondent_type,OLD.respondent_id,OLD.resolved_at) THEN
    RAISE EXCEPTION 'resolved decision is immutable';
  END IF;
  RETURN NEW;
END
$$
"""
    execute "CREATE TRIGGER fount_run_decision_identity_immutable BEFORE UPDATE ON fount_run_decisions FOR EACH ROW EXECUTE FUNCTION fount_run_guard_decision_identity()"

    execute ~S"""
CREATE FUNCTION fount_run_guard_usage_reservation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF ROW(NEW.operation_id,NEW.run_id,NEW.screenplay_id,NEW.step_id,NEW.attempt_number,NEW.session_id,NEW.resource,NEW.reserved_quantity,NEW.currency,NEW.reserved_cost_microunits) IS DISTINCT FROM ROW(OLD.operation_id,OLD.run_id,OLD.screenplay_id,OLD.step_id,OLD.attempt_number,OLD.session_id,OLD.resource,OLD.reserved_quantity,OLD.currency,OLD.reserved_cost_microunits) THEN
    RAISE EXCEPTION 'usage reservation identity is immutable';
  END IF;
  IF OLD.settled_quantity IS NOT NULL AND ROW(NEW.settled_quantity,NEW.settled_cost_microunits,NEW.provider_request_id,NEW.knowledge_state,NEW.reconciliation_state,NEW.settled_at) IS DISTINCT FROM ROW(OLD.settled_quantity,OLD.settled_cost_microunits,OLD.provider_request_id,OLD.knowledge_state,OLD.reconciliation_state,OLD.settled_at) THEN
    RAISE EXCEPTION 'usage settlement is immutable';
  END IF;
  RETURN NEW;
END
$$
"""
    execute "CREATE TRIGGER fount_run_usage_identity_immutable BEFORE UPDATE ON fount_run_usage FOR EACH ROW EXECUTE FUNCTION fount_run_guard_usage_reservation()"

    execute ~S"""
CREATE FUNCTION fount_run_guard_delivery_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF ROW(NEW.run_id,NEW.screenplay_id,NEW.candidate_id,NEW.accepted_revision_id,NEW.format,NEW.options,NEW.options_fingerprint,NEW.delivery_key) IS DISTINCT FROM ROW(OLD.run_id,OLD.screenplay_id,OLD.candidate_id,OLD.accepted_revision_id,OLD.format,OLD.options,OLD.options_fingerprint,OLD.delivery_key) THEN
    RAISE EXCEPTION 'delivery identity is immutable';
  END IF;
  IF OLD.state <> 'pending' AND ROW(NEW.state,NEW.output_checksum,NEW.output_location,NEW.error) IS DISTINCT FROM ROW(OLD.state,OLD.output_checksum,OLD.output_location,OLD.error) THEN
    RAISE EXCEPTION 'terminal delivery result is immutable';
  END IF;
  RETURN NEW;
END
$$
"""
    execute "CREATE TRIGGER fount_run_delivery_identity_immutable BEFORE UPDATE ON fount_run_deliveries FOR EACH ROW EXECUTE FUNCTION fount_run_guard_delivery_identity()"

    execute ~S"""
CREATE FUNCTION fount_run_guard_terminal_attempt() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF ROW(NEW.step_id,NEW.run_id,NEW.attempt_number,NEW.fencing_token,NEW.started_at) IS DISTINCT FROM ROW(OLD.step_id,OLD.run_id,OLD.attempt_number,OLD.fencing_token,OLD.started_at) THEN
    RAISE EXCEPTION 'run attempt identity is immutable';
  END IF;
  IF OLD.outcome <> 'running' OR OLD.ended_at IS NOT NULL THEN
    RAISE EXCEPTION 'terminal run attempt is immutable';
  END IF;
  RETURN NEW;
END
$$
"""
    execute "CREATE TRIGGER fount_run_attempt_terminal_immutable BEFORE UPDATE ON fount_run_attempts FOR EACH ROW EXECUTE FUNCTION fount_run_guard_terminal_attempt()"
  end

  def down do
    execute "DROP TRIGGER fount_run_attempt_terminal_immutable ON fount_run_attempts"
    execute "DROP FUNCTION fount_run_guard_terminal_attempt()"
    execute "DROP TRIGGER fount_run_delivery_identity_immutable ON fount_run_deliveries"
    execute "DROP FUNCTION fount_run_guard_delivery_identity()"
    execute "DROP TRIGGER fount_run_usage_identity_immutable ON fount_run_usage"
    execute "DROP FUNCTION fount_run_guard_usage_reservation()"
    execute "DROP TRIGGER fount_run_decision_identity_immutable ON fount_run_decisions"
    execute "DROP FUNCTION fount_run_guard_decision_identity()"
    execute "DROP TRIGGER fount_run_approval_immutable ON fount_run_approval_attempts"
    execute "DROP FUNCTION fount_run_guard_approval_immutable()"
    execute "DROP TRIGGER fount_run_events_append_only ON fount_run_events"
    execute "DROP TRIGGER fount_run_policies_append_only ON fount_run_policies"
    execute "DROP TRIGGER fount_run_plans_append_only ON fount_run_plans"
    execute "DROP FUNCTION fount_run_reject_snapshot_mutation()"
    execute "ALTER TABLE fount_runs DROP CONSTRAINT fount_run_active_step_fk"
    execute "ALTER TABLE fount_runs DROP CONSTRAINT fount_run_current_policy_fk"
    execute "ALTER TABLE fount_runs DROP CONSTRAINT fount_run_current_plan_fk"
    execute "DROP TABLE fount_run_deliveries"
    execute "DROP TABLE fount_run_usage"
    execute "DROP TABLE fount_run_approval_attempts"
    execute "DROP INDEX fount_run_acceptance_identity"
    execute "DROP TABLE fount_run_decisions"
    execute "DROP TABLE fount_run_events"
    execute "DROP TABLE fount_run_attempts"
    execute "DROP TABLE fount_run_steps"
    execute "DROP TABLE fount_run_policies"
    execute "DROP TABLE fount_run_plans"
    execute "DROP TABLE fount_runs"
  end
end
