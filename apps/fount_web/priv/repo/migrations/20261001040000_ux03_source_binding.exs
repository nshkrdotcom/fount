defmodule FountWeb.Migrations.UX03SourceBinding do
  use Ecto.Migration

  def up do
    create unique_index(:fount_web_projects, [:owner_id, :id, :screenplay_id],
             name: :ux03_project_source_identity
           )

    for table <-
          ~w(fount_web_note_review_responses fount_web_project_artifacts fount_web_table_reads) do
      execute(
        "ALTER TABLE #{table} ADD CONSTRAINT #{table}_project_source_fk FOREIGN KEY (owner_id,project_id,screenplay_id) REFERENCES fount_web_projects(owner_id,id,screenplay_id)"
      )

      column =
        if table == "fount_web_note_review_responses",
          do: "source_revision_id",
          else: "revision_id"

      execute(
        "ALTER TABLE #{table} ADD CONSTRAINT #{table}_source_revision_fk FOREIGN KEY (screenplay_id,#{column}) REFERENCES revisions(screenplay_id,id)"
      )
    end

    execute(
      "ALTER TABLE fount_web_note_review_responses ADD CONSTRAINT ux03_reviewed_source_fk FOREIGN KEY (screenplay_id,reviewed_revision_id) REFERENCES revisions(screenplay_id,id)"
    )
  end

  def down do
    execute("ALTER TABLE fount_web_note_review_responses DROP CONSTRAINT ux03_reviewed_source_fk")

    for table <-
          ~w(fount_web_note_review_responses fount_web_project_artifacts fount_web_table_reads) do
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_source_revision_fk")
      execute("ALTER TABLE #{table} DROP CONSTRAINT #{table}_project_source_fk")
    end

    drop index(:fount_web_projects, [:owner_id, :id, :screenplay_id],
           name: :ux03_project_source_identity
         )
  end
end
