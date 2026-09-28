defmodule Fount.ApprovalMigrationIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Fount.{ID, Persistence}

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :fount, adapter: Ecto.Adapters.Postgres
  end

  setup do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    prefix = "phase01_#{String.replace(ID.v4(), "-", "")}"
    {:ok, admin} = Postgrex.start_link(url: url)
    Postgrex.query!(admin, ~s(CREATE SCHEMA "#{prefix}"), [])

    start_supervised!(
      {MigrationRepo,
       url: url,
       pool_size: 1,
       parameters: [search_path: prefix],
       migration_default_prefix: prefix}
    )

    on_exit(fn ->
      if Process.alive?(admin) do
        Postgrex.query!(admin, ~s(DROP SCHEMA IF EXISTS "#{prefix}" CASCADE), [])
        GenServer.stop(admin)
      end
    end)

    %{prefix: prefix}
  end

  test "fresh migration installs approval identity and required-check audit columns" do
    Ecto.Migrator.run(MigrationRepo, Persistence.migrations_path(), :up, all: true)

    columns =
      SQL.query!(
        MigrationRepo,
        "SELECT table_name,column_name FROM information_schema.columns WHERE table_schema=current_schema() AND table_name IN ('acceptances','writing_candidates')",
        [],
        log: false
      ).rows
      |> MapSet.new()

    for pair <- [
          ["acceptances", "acceptance_kind"],
          ["acceptances", "approval_id"],
          ["acceptances", "approval_hash"],
          ["acceptances", "approval"],
          ["acceptances", "approver_type"],
          ["acceptances", "reviewer_type"],
          ["acceptances", "review_hash"],
          ["acceptances", "check_set_fingerprint"],
          ["acceptances", "report_ids"],
          ["writing_candidates", "required_checks"],
          ["writing_candidates", "check_set_fingerprint"],
          ["writing_candidates", "approval_id"]
        ] do
      assert MapSet.member?(columns, pair), "missing migrated column #{inspect(pair)}"
    end
  end

  test "baseline upgrade classifies historical audits without inventing principal types" do
    Ecto.Migrator.run(MigrationRepo, Persistence.migrations_path(), :up, to: 20_260_927_000_000)

    screenplay = ID.v4()
    root = ID.v4()
    edited = ID.v4()

    SQL.query!(MigrationRepo, "INSERT INTO screenplays(id,key) VALUES($1::uuid,$2)", [screenplay, "upgrade-#{screenplay}"], log: false)

    SQL.query!(
      MigrationRepo,
      "INSERT INTO revisions(id,screenplay_id,parent_id,content_hash,render_hash,model,actor) VALUES($1::uuid,$2::uuid,NULL,$3,$4,'{}'::jsonb,$5),($6::uuid,$2::uuid,$1::uuid,$7,$8,'{}'::jsonb,$9)",
      [root, screenplay, String.duplicate("a", 64), String.duplicate("b", 64), "legacy-root", edited, String.duplicate("c", 64), String.duplicate("d", 64), "legacy-edit"],
      log: false
    )

    SQL.query!(
      MigrationRepo,
      "INSERT INTO acceptances(id,screenplay_id,base_revision_id,result_revision_id,candidate_id,actor,origin,operations,provenance,review) VALUES($1::uuid,$2::uuid,NULL,$3::uuid,NULL,$4,'writer_edit','[]'::jsonb,'{}'::jsonb,'{}'::jsonb),($5::uuid,$2::uuid,$3::uuid,$6::uuid,NULL,$7,'writer_edit','[]'::jsonb,'{}'::jsonb,'{}'::jsonb)",
      [ID.v4(), screenplay, root, "legacy-genesis", ID.v4(), edited, "legacy-direct-actor"],
      log: false
    )

    SQL.query!(MigrationRepo, "UPDATE screenplays SET head_revision_id=$2::uuid WHERE id=$1::uuid", [screenplay, edited], log: false)

    Ecto.Migrator.run(MigrationRepo, Persistence.migrations_path(), :up, all: true)

    rows =
      SQL.query!(
        MigrationRepo,
        "SELECT result_revision_id::text,actor,acceptance_kind,approver_type,reviewer_type,approval_id FROM acceptances WHERE screenplay_id=$1::uuid ORDER BY inserted_at,id",
        [screenplay],
        log: false
      ).rows

    assert Enum.any?(rows, &(&1 == [root, "legacy-genesis", "genesis", nil, nil, nil]))
    assert Enum.any?(rows, &(&1 == [edited, "legacy-direct-actor", "historical", nil, nil, nil]))

    candidate_result = ID.v4()
    candidate_id = ID.v4()
    session_id = ID.v4()

    SQL.query!(
      MigrationRepo,
      "INSERT INTO revisions(id,screenplay_id,parent_id,content_hash,render_hash,model,actor) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,'{}'::jsonb,'candidate')",
      [candidate_result, screenplay, edited, String.duplicate("e", 64), String.duplicate("f", 64)],
      log: false
    )

    SQL.query!(
      MigrationRepo,
      "INSERT INTO writing_sessions(id,screenplay_id,base_revision_id,workflow,status,request) VALUES($1::uuid,$2::uuid,$3::uuid,'pass','review_ready','{}'::jsonb)",
      [session_id, screenplay, edited],
      log: false
    )

    SQL.query!(
      MigrationRepo,
      "INSERT INTO writing_candidates(id,screenplay_id,session_id,base_revision_id,result_revision_id,label,change_groups,provenance,required_checks,check_set_fingerprint) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,'upgrade candidate','[]'::jsonb,'{}'::jsonb,'[]'::jsonb,'fp')",
      [candidate_id, screenplay, session_id, edited, candidate_result],
      log: false
    )

    assert_raise Postgrex.Error, fn ->
      SQL.query!(
        MigrationRepo,
        "INSERT INTO acceptances(id,screenplay_id,base_revision_id,result_revision_id,candidate_id,actor,origin,operations,provenance,review,acceptance_kind) VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,'new','writer_edit','[]'::jsonb,'{}'::jsonb,'{}'::jsonb,'approved')",
        [ID.v4(), screenplay, edited, candidate_result, candidate_id],
        log: false
      )
    end
  end
end
