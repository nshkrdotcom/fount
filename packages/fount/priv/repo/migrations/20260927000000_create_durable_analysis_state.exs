defmodule Fount.Repo.Migrations.CreateDurableAnalysisState do
  use Ecto.Migration

  def up do
    execute ~S"""
CREATE TABLE analysis_assets (
  id uuid PRIMARY KEY,
  screenplay_id uuid REFERENCES screenplays(id),
  scope_id text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('lens','calibration','playbook','genre_pack')),
  logical_id text NOT NULL,
  trust text NOT NULL,
  source jsonb NOT NULL DEFAULT '{}',
  content jsonb NOT NULL,
  sha256 text NOT NULL CHECK (char_length(sha256) = 64),
  parent_id uuid REFERENCES analysis_assets(id),
  enabled boolean NOT NULL DEFAULT false,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (scope_id,kind,logical_id,sha256)
)
"""

    execute ~S"""
CREATE INDEX analysis_assets_current
  ON analysis_assets(scope_id,kind,logical_id,enabled,inserted_at DESC)
"""

    execute ~S"""
CREATE TABLE analysis_runs (
  id uuid PRIMARY KEY,
  screenplay_id uuid NOT NULL REFERENCES screenplays(id),
  revision_id uuid NOT NULL,
  revision_content_sha256 text NOT NULL CHECK (char_length(revision_content_sha256) = 64),
  session_id uuid,
  candidate_id uuid,
  playbook text NOT NULL,
  playbook_sha256 text,
  status text NOT NULL CHECK (status IN ('running','complete','partial','failed')),
  concern jsonb NOT NULL DEFAULT '{}',
  intent jsonb NOT NULL DEFAULT '{}',
  scope jsonb NOT NULL DEFAULT '{}',
  privacy_namespace text NOT NULL,
  output_contract_id text,
  output_contract_sha256 text,
  preflight jsonb NOT NULL DEFAULT '{}',
  resource_usage jsonb NOT NULL DEFAULT '{}',
  summary jsonb NOT NULL DEFAULT '{}',
  result jsonb NOT NULL DEFAULT '{}',
  metadata jsonb NOT NULL DEFAULT '{}',
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (screenplay_id,id),
  FOREIGN KEY (screenplay_id,session_id) REFERENCES writing_sessions(screenplay_id,id)
)
"""

    execute ~S"""
CREATE INDEX analysis_runs_for_revision
  ON analysis_runs(screenplay_id,revision_id,playbook,inserted_at DESC)
"""

    execute ~S"""
CREATE INDEX analysis_runs_for_session
  ON analysis_runs(screenplay_id,session_id,inserted_at DESC)
"""

    execute ~S"""
CREATE TABLE analysis_measurement_results (
  cache_key text NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  result_id text NOT NULL,
  privacy_namespace text NOT NULL,
  measurement_spec_sha256 text NOT NULL,
  input_sha256 text NOT NULL,
  semantic_execution_sha256 text NOT NULL,
  output_contract_id text NOT NULL,
  output_contract_sha256 text NOT NULL,
  provider_fingerprint jsonb NOT NULL,
  payload jsonb NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now(),
  last_accessed_at timestamptz NOT NULL DEFAULT now(),
  access_count bigint NOT NULL DEFAULT 0 CHECK (access_count >= 0),
  PRIMARY KEY (privacy_namespace,cache_key,ordinal),
  UNIQUE (privacy_namespace,result_id)
)
"""

    execute ~S"""
CREATE INDEX analysis_measurement_results_lru
  ON analysis_measurement_results(privacy_namespace,last_accessed_at,cache_key)
"""

    execute ~S"""
CREATE TABLE analysis_observations (
  id text PRIMARY KEY,
  analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id),
  screenplay_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  request_id text,
  result_id text NOT NULL,
  kind text NOT NULL,
  target jsonb NOT NULL,
  evidence jsonb NOT NULL DEFAULT '[]',
  dependencies jsonb NOT NULL DEFAULT '[]',
  payload jsonb NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now()
)
"""

    execute ~S"""
CREATE INDEX analysis_observations_for_run
  ON analysis_observations(analysis_run_id,inserted_at,id)
"""

    execute ~S"""
CREATE INDEX analysis_observations_for_revision
  ON analysis_observations(screenplay_id,revision_id,kind,inserted_at)
"""

    execute ~S"""
CREATE TABLE analysis_dependencies (
  id uuid PRIMARY KEY,
  screenplay_id uuid NOT NULL REFERENCES screenplays(id),
  subject_kind text NOT NULL,
  subject_id text NOT NULL,
  dependency_key text NOT NULL,
  analysis_run_id uuid NOT NULL REFERENCES analysis_runs(id),
  inserted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (analysis_run_id,subject_kind,subject_id,dependency_key)
)
"""

    execute ~S"""
CREATE INDEX analysis_dependencies_reverse
  ON analysis_dependencies(screenplay_id,dependency_key,subject_kind,subject_id)
"""
  end

  def down do
    execute "DROP TABLE analysis_dependencies CASCADE"
    execute "DROP TABLE analysis_observations CASCADE"
    execute "DROP TABLE analysis_measurement_results CASCADE"
    execute "DROP TABLE analysis_runs CASCADE"
    execute "DROP TABLE analysis_assets CASCADE"
  end
end
