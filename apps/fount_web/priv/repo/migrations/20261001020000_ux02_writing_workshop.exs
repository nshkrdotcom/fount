defmodule FountWeb.Migrations.UX02WritingWorkshop do
  use Ecto.Migration

  def change do
    create table(:fount_web_note_work_links, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :note_id, :text, null: false
      add :source_revision_id, references(:revisions, type: :uuid, on_delete: :nothing), null: false
      add :source_fingerprint, :text, null: false
      add :run_id, references(:fount_runs, column: :id, type: :uuid, on_delete: :delete_all), null: false
      add :proposal_candidate_id, references(:writing_candidates, type: :uuid, on_delete: :nilify_all)
      add :result_revision_id, references(:revisions, type: :uuid, on_delete: :nothing)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_note_work_links, [:owner_id, :note_id, :run_id],
             name: :fount_web_note_work_links_owner_note_run_index
           )

    create index(:fount_web_note_work_links, [:owner_id, :project_id, :note_id, :inserted_at],
             name: :fount_web_note_work_links_project_note_index
           )
  end
end
