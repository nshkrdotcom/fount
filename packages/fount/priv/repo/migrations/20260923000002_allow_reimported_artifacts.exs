defmodule Fount.Repo.Migrations.AllowReimportedArtifacts do
  use Ecto.Migration

  def change do
    drop unique_index(:import_artifacts, [:screenplay_id, :bytes_sha256, :format])
    create unique_index(:import_artifacts, [:screenplay_id, :imported_model_revision_id, :format])
  end
end
