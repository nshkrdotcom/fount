defmodule FountRun.Repo.Migrations.DurableExecution do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE fount_run_steps ADD COLUMN result jsonb"
    execute "ALTER TABLE fount_run_steps ADD COLUMN result_fingerprint text"
    execute "ALTER TABLE fount_run_steps ADD COLUMN malformed_repair_count integer NOT NULL DEFAULT 0 CHECK (malformed_repair_count >= 0)"
    execute "ALTER TABLE fount_run_steps ADD COLUMN transient_retry_count integer NOT NULL DEFAULT 0 CHECK (transient_retry_count >= 0)"
    execute "ALTER TABLE fount_run_steps ADD COLUMN provider_dispatch_count integer NOT NULL DEFAULT 0 CHECK (provider_dispatch_count >= 0)"
    execute "ALTER TABLE fount_run_steps ADD COLUMN measurement_state_count bigint NOT NULL DEFAULT 0 CHECK (measurement_state_count >= 0)"
    execute "ALTER TABLE fount_run_steps ADD COLUMN completed_at timestamptz"
    execute "ALTER TABLE fount_run_steps ADD CONSTRAINT fount_run_step_result_hash CHECK (result_fingerprint IS NULL OR char_length(result_fingerprint)=64)"
    execute "ALTER TABLE fount_run_steps ADD CONSTRAINT fount_run_step_completion_shape CHECK ((status='succeeded' AND result IS NOT NULL AND result_fingerprint IS NOT NULL AND completed_at IS NOT NULL) OR status<>'succeeded')"

    execute ~S"""
CREATE TABLE fount_run_provider_requests (
  id uuid PRIMARY KEY,
  operation_id text NOT NULL UNIQUE CHECK (operation_id <> ''),
  run_id uuid NOT NULL,
  screenplay_id uuid NOT NULL,
  step_id uuid NOT NULL,
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  fencing_token bigint NOT NULL CHECK (fencing_token >= 0),
  usage_id uuid,
  request_fingerprint text NOT NULL CHECK (char_length(request_fingerprint)=64),
  request_mode text NOT NULL CHECK (request_mode <> ''),
  dispatch_index integer NOT NULL CHECK (dispatch_index > 0),
  transport_retry integer NOT NULL DEFAULT 0 CHECK (transport_retry >= 0),
  malformed_repair boolean NOT NULL DEFAULT false,
  status text NOT NULL CHECK (status IN ('intended','dispatched','succeeded','failed','unknown','partial')),
  provider_request_id text,
  response jsonb,
  response_fingerprint text CHECK (response_fingerprint IS NULL OR char_length(response_fingerprint)=64),
  usage jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(usage)='object'),
  error_category text,
  intended_at timestamptz NOT NULL DEFAULT now(),
  dispatched_at timestamptz,
  responded_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (screenplay_id,run_id) REFERENCES fount_runs(screenplay_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (run_id,step_id) REFERENCES fount_run_steps(run_id,id) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (step_id,attempt_number) REFERENCES fount_run_attempts(step_id,attempt_number) DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (usage_id) REFERENCES fount_run_usage(id) DEFERRABLE INITIALLY DEFERRED,
  CHECK ((status='intended' AND dispatched_at IS NULL AND responded_at IS NULL) OR
         (status='dispatched' AND dispatched_at IS NOT NULL AND responded_at IS NULL) OR
         (status IN ('succeeded','failed','partial') AND dispatched_at IS NOT NULL AND responded_at IS NOT NULL) OR
         (status='unknown' AND dispatched_at IS NOT NULL))
)
"""

    execute "CREATE INDEX fount_run_provider_recovery ON fount_run_provider_requests(step_id,status,updated_at)"
  end

  def down do
    execute "DROP TABLE IF EXISTS fount_run_provider_requests"
    execute "ALTER TABLE fount_run_steps DROP CONSTRAINT IF EXISTS fount_run_step_completion_shape"
    execute "ALTER TABLE fount_run_steps DROP CONSTRAINT IF EXISTS fount_run_step_result_hash"
    execute "ALTER TABLE fount_run_steps DROP COLUMN IF EXISTS completed_at"
    execute "ALTER TABLE fount_run_steps DROP COLUMN IF EXISTS measurement_state_count"
    execute "ALTER TABLE fount_run_steps DROP COLUMN IF EXISTS provider_dispatch_count"
    execute "ALTER TABLE fount_run_steps DROP COLUMN IF EXISTS transient_retry_count"
    execute "ALTER TABLE fount_run_steps DROP COLUMN IF EXISTS malformed_repair_count"
    execute "ALTER TABLE fount_run_steps DROP COLUMN IF EXISTS result_fingerprint"
    execute "ALTER TABLE fount_run_steps DROP COLUMN IF EXISTS result"
  end
end
