defmodule FountWeb.Migrations.Phase08ProductionTools do
  use Ecto.Migration

  def change do
    alter table(:fount_web_projects) do
      add :synopsis, :text
      add :thumbnail_ref, :text
      add :import_format, :text
      add :import_fidelity, :map
    end

    create table(:fount_web_tool_candidates, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :candidate_id, references(:writing_candidates, type: :uuid, on_delete: :delete_all), null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :base_revision_id, references(:revisions, type: :uuid, on_delete: :nothing), null: false
      add :kind, :text, null: false
      add :resource_id, :text
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_tool_candidates, [:owner_id, :candidate_id])
    create index(:fount_web_tool_candidates, [:owner_id, :project_id, :inserted_at])
    create constraint(:fount_web_tool_candidates, :phase08_tool_candidate_kind,
             check: "kind IN ('note','cast')"
           )

    create table(:fount_web_table_reads, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, references(:fount_runs, column: :id, type: :uuid, on_delete: :delete_all), null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :revision_id, references(:revisions, type: :uuid, on_delete: :nothing), null: false
      add :packet_id, :text, null: false
      add :packet, :map, null: false
      add :bookmark_index, :integer, null: false, default: 0
      add :elapsed_ms, :bigint, null: false, default: 0
      add :scroll_mode, :text, null: false, default: "manual"
      add :version, :bigint, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_table_reads, [:owner_id, :id])
    create index(:fount_web_table_reads, [:owner_id, :project_id, :revision_id, :updated_at])
    create constraint(:fount_web_table_reads, :phase08_table_read_state,
             check: "bookmark_index >= 0 AND elapsed_ms >= 0 AND version >= 1 AND scroll_mode IN ('manual','auto','paused')"
           )

    create table(:fount_web_usefulness_records, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, references(:fount_runs, column: :id, type: :uuid, on_delete: :delete_all), null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :revision_id, references(:revisions, type: :uuid, on_delete: :nothing), null: false
      add :task_id, :text, null: false
      add :condition, :text, null: false
      add :record, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_usefulness_records, [:owner_id, :id])
    create index(:fount_web_usefulness_records, [:owner_id, :project_id, :inserted_at])
    create constraint(:fount_web_usefulness_records, :phase08_usefulness_condition,
             check: "condition IN ('human_only','basic_llm','fount_assisted')"
           )
  end
end
