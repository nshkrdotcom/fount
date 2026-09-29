defmodule FountWeb.Migrations.CreateHostTables do
  use Ecto.Migration

  def change do
    create table(:fount_web_projects, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :owner_id, :text, null: false
      add :screenplay_id, references(:screenplays, type: :uuid, on_delete: :delete_all), null: false
      add :key, :text, null: false
      add :title, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:fount_web_projects, [:owner_id, :id])
    create unique_index(:fount_web_projects, [:owner_id, :key])
    create unique_index(:fount_web_projects, [:screenplay_id])

    create table(:fount_web_runs, primary_key: false) do
      add :run_id, references(:fount_runs, column: :id, type: :uuid, on_delete: :delete_all), primary_key: true
      add :project_id, references(:fount_web_projects, type: :uuid, on_delete: :delete_all), null: false
      add :owner_id, :text, null: false
      add :preset, :text, null: false
      add :journey, :text, null: false
      add :launched_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:fount_web_runs, [:owner_id, :project_id])
    create index(:fount_web_runs, [:owner_id, :launched_at])
  end
end
