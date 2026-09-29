defmodule FountRun.UpgradeIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Fount.{ID, Persistence}

  defmodule UpgradeRepo do
    use Ecto.Repo, otp_app: :fount_run, adapter: Ecto.Adapters.Postgres
  end

  test "populated Phase 02 Core and Run schema upgrades through Phase 03" do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    prefix = "phase02_upgrade_#{String.replace(ID.v4(), "-", "")}"
    {:ok, admin} = Postgrex.start_link(Ecto.Repo.Supervisor.parse_url(url))
    Postgrex.query!(admin, ~s(CREATE SCHEMA "#{prefix}"), [])
    GenServer.stop(admin)

    on_exit(fn ->
      {:ok, cleanup} = Postgrex.start_link(Ecto.Repo.Supervisor.parse_url(url))
      Postgrex.query!(cleanup, ~s(DROP SCHEMA IF EXISTS "#{prefix}" CASCADE), [])
      GenServer.stop(cleanup)
    end)

    start_supervised!(
      {UpgradeRepo,
       url: url, pool_size: 2, parameters: [search_path: prefix], migration_default_prefix: prefix}
    )

    Ecto.Migrator.run(UpgradeRepo, Persistence.migrations_path(), :up, to: 20_260_928_000_000)

    screenplay_id = ID.v4()
    revision_id = ID.v4()

    SQL.query!(
      UpgradeRepo,
      "INSERT INTO screenplays(id,key) VALUES($1::text::uuid,$2)",
      [
        screenplay_id,
        "existing-#{screenplay_id}"
      ],
      log: false
    )

    SQL.query!(
      UpgradeRepo,
      "INSERT INTO revisions(id,screenplay_id,content_hash,render_hash,model) VALUES($1::text::uuid,$2::text::uuid,$3,$4,'{}'::jsonb)",
      [revision_id, screenplay_id, String.duplicate("a", 64), String.duplicate("b", 64)],
      log: false
    )

    SQL.query!(
      UpgradeRepo,
      "UPDATE screenplays SET head_revision_id=$2::text::uuid WHERE id=$1::text::uuid",
      [screenplay_id, revision_id],
      log: false
    )

    assert [[0]] =
             SQL.query!(
               UpgradeRepo,
               "SELECT count(*) FROM information_schema.tables WHERE table_schema=current_schema() AND table_name='fount_runs'",
               [],
               log: false
             ).rows

    Ecto.Migrator.run(UpgradeRepo, FountRun.migrations_path(), :up, to: 20_260_928_010_000)

    assert [[0]] =
             SQL.query!(
               UpgradeRepo,
               "SELECT count(*) FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='writing_sessions' AND column_name='operation_key'",
               [],
               log: false
             ).rows

    Ecto.Migrator.run(UpgradeRepo, Persistence.migrations_path(), :up, all: true)
    Ecto.Migrator.run(UpgradeRepo, FountRun.migrations_path(), :up, all: true)

    assert [[1]] =
             SQL.query!(
               UpgradeRepo,
               "SELECT count(*) FROM information_schema.tables WHERE table_schema=current_schema() AND table_name='fount_runs'",
               [],
               log: false
             ).rows

    assert [[1]] =
             SQL.query!(
               UpgradeRepo,
               "SELECT count(*) FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='writing_sessions' AND column_name='operation_key'",
               [],
               log: false
             ).rows

    assert [[1]] =
             SQL.query!(
               UpgradeRepo,
               "SELECT count(*) FROM information_schema.tables WHERE table_schema=current_schema() AND table_name='fount_run_provider_requests'",
               [],
               log: false
             ).rows

    assert [[^revision_id]] =
             SQL.query!(
               UpgradeRepo,
               "SELECT head_revision_id::text FROM screenplays WHERE id=$1::text::uuid",
               [screenplay_id],
               log: false
             ).rows

    assert [[1]] =
             SQL.query!(
               UpgradeRepo,
               "SELECT count(*) FROM revisions WHERE id=$1::text::uuid",
               [revision_id],
               log: false
             ).rows
  end
end
