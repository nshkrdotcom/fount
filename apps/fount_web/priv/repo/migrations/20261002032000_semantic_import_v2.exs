defmodule FountWeb.Repo.Migrations.SemanticImportV2 do
  use Ecto.Migration

  def up do
    drop constraint(:fount_web_semantic_assessments, :semantic_assessment_schema_version)

    create constraint(:fount_web_semantic_assessments, :semantic_assessment_schema_version,
             check: "schema_version IN ('source_inventory_v1','semantic_import_v1','source_inventory_v2','semantic_import_v2')"
           )
  end

  def down do
    raise "Semantic import v2 results are immutable; restore a task-owned database backup to downgrade"
  end
end
