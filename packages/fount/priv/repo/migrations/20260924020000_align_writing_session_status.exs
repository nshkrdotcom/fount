defmodule Fount.Repo.Migrations.AlignWritingSessionStatus do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE writing_sessions DROP CONSTRAINT writing_sessions_status_check"

    execute """
    ALTER TABLE writing_sessions ADD CONSTRAINT writing_sessions_status_check
    CHECK (status IN ('open','running','ready','strategies_ready','review_ready','partial','failed','closed'))
    """
  end

  def down do
    execute "UPDATE writing_sessions SET status='ready' WHERE status IN ('strategies_ready','review_ready')"
    execute "ALTER TABLE writing_sessions DROP CONSTRAINT writing_sessions_status_check"

    execute """
    ALTER TABLE writing_sessions ADD CONSTRAINT writing_sessions_status_check
    CHECK (status IN ('open','running','ready','partial','failed','closed'))
    """
  end
end
