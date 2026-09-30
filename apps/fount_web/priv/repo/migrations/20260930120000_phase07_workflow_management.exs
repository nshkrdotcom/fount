defmodule FountWeb.Migrations.Phase07WorkflowManagement do
  use Ecto.Migration

  def change do
    create table(:fount_web_policy_presets, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :name, :text, null: false
      add :version, :integer, null: false
      add :policy, :map, null: false
      add :policy_fingerprint, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_policy_presets, [:owner_id, :name, :version])
    create index(:fount_web_policy_presets, [:owner_id, :updated_at])

    create table(:fount_web_workflow_selections, primary_key: false) do
      add :run_id, references(:fount_runs, column: :id, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :owner_id, :text, null: false
      add :screenplay_id, :uuid, null: false
      add :base_revision_id, :uuid, null: false
      add :selection, :map, null: false
      add :selection_fingerprint, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_workflow_selections, [:owner_id, :run_id])
    create index(:fount_web_workflow_selections, [:owner_id, :screenplay_id, :base_revision_id])
  end
end
