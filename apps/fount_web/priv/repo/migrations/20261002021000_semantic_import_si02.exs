defmodule FountWeb.Migrations.SemanticImportSI02 do
  use Ecto.Migration

  def up do
    alter table(:fount_web_semantic_assessments) do
      add :command_id, :text
      add :supersedes_assessment_id, :uuid
      add :error, :map, null: false, default: %{}
      add :completed_at, :utc_datetime_usec
    end

    drop_if_exists index(:fount_web_semantic_assessments, [:owner_id, :project_id, :revision_id, :schema_version, :origin, :source_sha256],
                     name: :semantic_assessment_source_identity
                   )

    create unique_index(
             :fount_web_semantic_assessments,
             [:owner_id, :project_id, :revision_id, :schema_version, :origin, :source_sha256],
             where: "origin IN ('manual','legacy_literal')",
             name: :semantic_manual_assessment_source_identity
           )

    create unique_index(:fount_web_semantic_assessments, [:owner_id, :project_id, :command_id],
             where: "command_id IS NOT NULL",
             name: :semantic_assessment_command_identity
           )

    create index(
             :fount_web_semantic_assessments,
             [:owner_id, :project_id, :revision_id, :origin, :inserted_at],
             name: :semantic_assessment_history_index
           )

    execute(
      "ALTER TABLE fount_web_semantic_assessments ADD CONSTRAINT semantic_assessment_run_fk FOREIGN KEY (run_id) REFERENCES fount_runs(id)"
    )

    execute(
      "ALTER TABLE fount_web_semantic_assessments ADD CONSTRAINT semantic_assessment_supersedes_fk FOREIGN KEY (supersedes_assessment_id) REFERENCES fount_web_semantic_assessments(id)"
    )
  end

  def down do
    execute(
      "ALTER TABLE fount_web_semantic_assessments DROP CONSTRAINT IF EXISTS semantic_assessment_supersedes_fk"
    )

    execute(
      "ALTER TABLE fount_web_semantic_assessments DROP CONSTRAINT IF EXISTS semantic_assessment_run_fk"
    )

    drop_if_exists index(:fount_web_semantic_assessments, [:owner_id, :project_id, :revision_id, :origin, :inserted_at],
                     name: :semantic_assessment_history_index
                   )

    drop_if_exists unique_index(:fount_web_semantic_assessments, [:owner_id, :project_id, :command_id],
                     name: :semantic_assessment_command_identity
                   )

    drop_if_exists unique_index(:fount_web_semantic_assessments, [:owner_id, :project_id, :revision_id, :schema_version, :origin, :source_sha256],
                     name: :semantic_manual_assessment_source_identity
                   )

    create unique_index(
             :fount_web_semantic_assessments,
             [:owner_id, :project_id, :revision_id, :schema_version, :origin, :source_sha256],
             name: :semantic_assessment_source_identity
           )

    alter table(:fount_web_semantic_assessments) do
      remove :completed_at
      remove :error
      remove :supersedes_assessment_id
      remove :command_id
    end
  end
end
