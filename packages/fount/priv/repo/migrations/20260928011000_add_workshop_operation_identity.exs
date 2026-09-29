defmodule Fount.Repo.Migrations.AddWorkshopOperationIdentity do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE writing_sessions ADD COLUMN operation_key text"
    execute "ALTER TABLE writing_candidates ADD COLUMN operation_key text"

    execute "CREATE UNIQUE INDEX writing_sessions_operation_key_unique ON writing_sessions(operation_key) WHERE operation_key IS NOT NULL"
    execute "CREATE UNIQUE INDEX writing_candidates_operation_key_unique ON writing_candidates(operation_key) WHERE operation_key IS NOT NULL"

    execute "ALTER TABLE writing_sessions ADD CONSTRAINT writing_sessions_operation_key_nonblank CHECK (operation_key IS NULL OR operation_key <> '')"
    execute "ALTER TABLE writing_candidates ADD CONSTRAINT writing_candidates_operation_key_nonblank CHECK (operation_key IS NULL OR operation_key <> '')"
  end

  def down do
    execute "ALTER TABLE writing_candidates DROP CONSTRAINT IF EXISTS writing_candidates_operation_key_nonblank"
    execute "ALTER TABLE writing_sessions DROP CONSTRAINT IF EXISTS writing_sessions_operation_key_nonblank"
    execute "DROP INDEX IF EXISTS writing_candidates_operation_key_unique"
    execute "DROP INDEX IF EXISTS writing_sessions_operation_key_unique"
    execute "ALTER TABLE writing_candidates DROP COLUMN IF EXISTS operation_key"
    execute "ALTER TABLE writing_sessions DROP COLUMN IF EXISTS operation_key"
  end
end
