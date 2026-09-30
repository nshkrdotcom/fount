defmodule FountWeb.Migrations.CreateAuthoringTables do
  use Ecto.Migration

  def change do
    create table(:fount_web_drafts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :owner_id, :text, null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :base_revision_id, references(:revisions, type: :uuid, on_delete: :nothing), null: false
      add :raw_source, :text, null: false
      add :source_sha256, :text, null: false
      add :last_valid_source, :text
      add :last_valid_sha256, :text
      add :last_valid_fidelity, :map
      add :identity_anchors, :map, null: false
      add :version, :bigint, null: false, default: 1
      add :status, :text, null: false, default: "active"
      add :saved_candidate_id, references(:writing_candidates, type: :uuid, on_delete: :nilify_all)
      add :saved_candidate_version, :bigint
      timestamps(type: :utc_datetime_usec)
    end

    create index(:fount_web_drafts, [:owner_id, :project_id, :status, :updated_at])
    create index(:fount_web_drafts, [:owner_id, :screenplay_id, :base_revision_id])
    create unique_index(:fount_web_drafts, [:owner_id, :id])

    create constraint(:fount_web_drafts, :draft_version_positive, check: "version >= 1")
    create constraint(:fount_web_drafts, :draft_status_valid,
             check: "status IN ('active','discarded','accepted')"
           )

    create table(:fount_web_draft_history, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :draft_id, references(:fount_web_drafts, type: :uuid, on_delete: :delete_all), null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :owner_id, :text, null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :base_revision_id, references(:revisions, type: :uuid, on_delete: :nothing), null: false
      add :draft_version, :bigint, null: false
      add :raw_source, :text, null: false
      add :source_sha256, :text, null: false
      add :reason, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:fount_web_draft_history, [:draft_id, :draft_version])
    create index(:fount_web_draft_history, [:owner_id, :draft_id, :inserted_at])
  end
end
