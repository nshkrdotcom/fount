defmodule FountWeb.Migrations.UX01ArrivalWorkspace do
  use Ecto.Migration

  def change do
    alter table(:fount_web_projects) do
      add :logline, :text
      add :project_kind, :text, null: false, default: "screenplay"
      add :source_name, :text
    end

    create constraint(:fount_web_projects, :ux01_project_kind,
             check: "project_kind IN ('screenplay','example')"
           )

    create table(:fount_web_preferences, primary_key: false) do
      add :owner_id, :text, primary_key: true
      add :preferences, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    alter table(:fount_web_runs) do
      add :display_key, :text
      add :display_label, :text
    end

    create unique_index(:fount_web_runs, [:owner_id, :project_id, :display_key],
             where: "display_key IS NOT NULL",
             name: :fount_web_runs_owner_project_display_key_index
           )
  end
end
