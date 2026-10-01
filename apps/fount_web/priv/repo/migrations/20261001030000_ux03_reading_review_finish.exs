defmodule FountWeb.Migrations.UX03ReadingReviewFinish do
  use Ecto.Migration

  def up do
    # Human table reads are a manual reader workflow and must not require a synthetic Run.
    execute("ALTER TABLE fount_web_table_reads ALTER COLUMN run_id DROP NOT NULL")

    create table(:fount_web_note_review_responses, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :note_id, :text, null: false
      add :source_revision_id, references(:revisions, type: :uuid, on_delete: :nothing), null: false
      add :reviewed_revision_id, references(:revisions, type: :uuid, on_delete: :nothing), null: false
      add :response, :text, null: false
      add :comment, :text
      add :actor_label, :text, null: false
      add :version, :bigint, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :fount_web_note_review_responses,
             [:owner_id, :project_id, :note_id, :reviewed_revision_id],
             name: :fount_web_note_review_identity_index
           )

    create index(
             :fount_web_note_review_responses,
             [:owner_id, :project_id, :note_id, :updated_at],
             name: :fount_web_note_review_note_index
           )

    create constraint(:fount_web_note_review_responses, :ux03_note_review_response,
             check: "response IN ('open','addressed','not_addressed','deferred')"
           )

    create constraint(:fount_web_note_review_responses, :ux03_note_review_version,
             check: "version >= 1"
           )

    create table(:fount_web_project_artifacts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :revision_id, references(:revisions, type: :uuid, on_delete: :nothing), null: false
      add :kind, :text, null: false
      add :source_label, :text, null: false
      add :filename, :text, null: false
      add :state, :text, null: false
      add :output_location, :text
      add :output_checksum, :text
      add :error, :text
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_project_artifacts, [:owner_id, :id])

    create index(
             :fount_web_project_artifacts,
             [:owner_id, :project_id, :revision_id, :kind, :inserted_at],
             name: :fount_web_project_artifact_source_index
           )

    create constraint(:fount_web_project_artifacts, :ux03_project_artifact_kind,
             check: "kind IN ('fountain','fdx','pdf','notes_memo')"
           )

    create constraint(:fount_web_project_artifacts, :ux03_project_artifact_state,
             check: "state IN ('building','ready','failed')"
           )
  end

  def down do
    drop table(:fount_web_project_artifacts)
    drop table(:fount_web_note_review_responses)

    execute("DELETE FROM fount_web_table_reads WHERE run_id IS NULL")
    execute("ALTER TABLE fount_web_table_reads ALTER COLUMN run_id SET NOT NULL")
  end
end
