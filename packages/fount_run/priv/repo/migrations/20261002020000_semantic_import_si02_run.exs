defmodule FountRun.Repo.Migrations.SemanticImportSI02Run do
  use Ecto.Migration

  @screenplay_stages ~w(intake investigate plan write check iterate decide deliver)
  @semantic_stages ~w(semantic_intake semantic_plan semantic_extract semantic_reconcile semantic_validate semantic_persist)
  @statuses ~w(queued running paused waiting_for_decision waiting_for_approval partial completed_candidate completed_accepted completed_nonmutating stopped failed)

  def up do
    stages = Enum.map_join(@screenplay_stages ++ @semantic_stages, ",", &"'#{&1}'")
    statuses = Enum.map_join(@statuses, ",", &"'#{&1}'")

    execute "ALTER TABLE fount_runs DROP CONSTRAINT IF EXISTS fount_runs_stage_check"
    execute "ALTER TABLE fount_run_steps DROP CONSTRAINT IF EXISTS fount_run_steps_stage_check"
    execute "ALTER TABLE fount_runs DROP CONSTRAINT IF EXISTS fount_runs_status_check"
    execute "ALTER TABLE fount_runs ADD CONSTRAINT fount_runs_stage_check CHECK (stage IN (#{stages}))"
    execute "ALTER TABLE fount_run_steps ADD CONSTRAINT fount_run_steps_stage_check CHECK (stage IN (#{stages}))"
    execute "ALTER TABLE fount_runs ADD CONSTRAINT fount_runs_status_check CHECK (status IN (#{statuses}))"
  end

  def down do
    execute "ALTER TABLE fount_runs DROP CONSTRAINT IF EXISTS fount_runs_stage_check"
    execute "ALTER TABLE fount_run_steps DROP CONSTRAINT IF EXISTS fount_run_steps_stage_check"
    execute "ALTER TABLE fount_runs DROP CONSTRAINT IF EXISTS fount_runs_status_check"
    execute "ALTER TABLE fount_runs ADD CONSTRAINT fount_runs_stage_check CHECK (stage IN ('intake','investigate','plan','write','check','iterate','decide','deliver'))"
    execute "ALTER TABLE fount_run_steps ADD CONSTRAINT fount_run_steps_stage_check CHECK (stage IN ('intake','investigate','plan','write','check','iterate','decide','deliver'))"
    execute "ALTER TABLE fount_runs ADD CONSTRAINT fount_runs_status_check CHECK (status IN ('queued','running','paused','waiting_for_decision','waiting_for_approval','partial','completed_candidate','completed_accepted','stopped','failed'))"
  end
end
