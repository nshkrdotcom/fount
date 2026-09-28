defmodule FountRun.FoundationIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Fount.{ID, Persistence}
  alias Fount.Writing.{Approval, Principal, Review}
  alias FountRun.ActorContext

  defmodule Repo do
    use Ecto.Repo, otp_app: :fount_run, adapter: Ecto.Adapters.Postgres
  end

  setup do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    prefix = "phase02_#{String.replace(ID.v4(), "-", "")}"
    {:ok, admin} = Postgrex.start_link(Ecto.Repo.Supervisor.parse_url(url))
    Postgrex.query!(admin, ~s(CREATE SCHEMA "#{prefix}"), [])

    start_supervised!(
      {Repo,
       url: url,
       pool_size: 2,
       parameters: [search_path: prefix],
       migration_default_prefix: prefix}
    )

    Ecto.Migrator.run(Repo, Persistence.migrations_path(), :up, all: true)
    Ecto.Migrator.run(Repo, FountRun.migrations_path(), :up, all: true)

    on_exit(fn ->
      if Process.alive?(admin) do
        Postgrex.query!(admin, ~s(DROP SCHEMA IF EXISTS "#{prefix}" CASCADE), [])
        GenServer.stop(admin)
      end
    end)

    %{repo: Repo}
  end

  test "Core then Run migrations install every prefixed table", %{repo: repo} do
    tables =
      SQL.query!(
        repo,
        "SELECT table_name FROM information_schema.tables WHERE table_schema=current_schema() AND table_name LIKE 'fount_run_%' ORDER BY table_name",
        [],
        log: false
      ).rows
      |> List.flatten()

    assert Enum.sort(tables) ==
             Enum.sort(
               ~w(fount_run_approval_attempts fount_run_attempts fount_run_decisions fount_run_deliveries fount_run_events fount_run_plans fount_run_policies fount_run_steps fount_run_usage fount_runs)
             )
  end

  test "start/read/list are authorized, provider-free and idempotent", %{repo: repo} do
    {screenplay, revision} = seed_core(repo)
    {:ok, owner} = Principal.new(:human, "owner")
    {:ok, context} = ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run])
    attrs = start_attrs(screenplay, revision, "key-1")

    assert {:ok, first} = FountRun.start_run(repo, attrs, context)
    assert {:ok, replay} = FountRun.start_run(repo, attrs, context)
    assert first["id"] == replay["id"]
    assert first["current_plan_version"] == 1
    assert first["current_policy_version"] == 1
    assert {:error, :idempotency_conflict} = FountRun.start_run(repo, put_in(attrs, ["goal"], "Different"), context)
    assert {:error, :invalid_start_options} = FountRun.start_run(repo, Map.put(attrs, "client_idempotency_key", "key-options"), context, future: true)

    {:ok, service} = Principal.new(:service, "service-starter")
    {:ok, service_context} = ActorContext.new(service, owner, screenplay, [:read_run, :manage_run], approvers: [service])
    assert {:error, :idempotency_conflict} = FountRun.start_run(repo, attrs, service_context)

    assert {:ok, loaded} = FountRun.get_run(repo, first["id"], context)
    assert loaded["id"] == first["id"]
    assert {:ok, [listed]} = FountRun.list_runs(repo, %{}, context)
    assert listed["id"] == first["id"]

    {:ok, other_owner} = Principal.new(:human, "other-owner")
    {:ok, other_context} = ActorContext.new(other_owner, other_owner, screenplay, [:read_run, :manage_run])
    assert {:error, :unauthorized} = FountRun.get_run(repo, first["id"], other_context)
    assert {:ok, []} = FountRun.list_runs(repo, %{}, other_context)

    {:ok, read_only} = ActorContext.new(owner, owner, screenplay, [:read_run])
    assert {:error, :unauthorized} = FountRun.start_run(repo, start_attrs(screenplay, revision, "key-read-only"), read_only)
    assert {:error, :invalid_run_id} = FountRun.get_run(repo, "not-a-uuid", context)

    assert SQL.query!(repo, "SELECT count(*) FROM fount_run_events WHERE run_id=$1::text::uuid", [first["id"]], log: false).rows == [[1]]
  end

  test "plan and policy snapshots append atomically while history stays immutable", %{repo: repo} do
    {screenplay, revision} = seed_core(repo)
    {:ok, owner} = Principal.new(:human, "owner")
    {:ok, context} = ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run])
    attrs = start_attrs(screenplay, revision, "key-snapshots")
    {:ok, run} = FountRun.start_run(repo, attrs, context)

    next_plan =
      attrs
      |> Map.drop(["policy", "client_idempotency_key"])
      |> Map.put("goal", "Clarified opening goal")

    assert {:ok, plan2} =
             FountRun.Persistence.append_plan_snapshot(repo, run["id"], next_plan, context,
               expected_version: 1,
               reason: "writer_clarification"
             )

    assert plan2["version"] == 2

    assert {:ok, policy2} =
             FountRun.Persistence.append_policy_snapshot(repo, run["id"], attrs["policy"], context,
               expected_version: 1
             )

    assert policy2["version"] == 2
    assert {:ok, current} = FountRun.get_run(repo, run["id"], context)
    assert current["current_plan_version"] == 2
    assert current["current_policy_version"] == 2
    assert current["plan"]["goal"] == "Clarified opening goal"

    assert_raise Postgrex.Error, fn ->
      SQL.query!(
        repo,
        "UPDATE fount_run_plans SET goal='overwrite' WHERE run_id=$1::text::uuid AND version=1",
        [run["id"]],
        log: false
      )
    end

    assert_raise Postgrex.Error, fn ->
      SQL.query!(
        repo,
        "UPDATE fount_run_policies SET policy='{}'::jsonb WHERE run_id=$1::text::uuid AND version=1",
        [run["id"]],
        log: false
      )
    end

    assert_raise Postgrex.Error, fn ->
      SQL.query!(
        repo,
        "UPDATE fount_run_events SET safe_summary='overwrite' WHERE run_id=$1::text::uuid",
        [run["id"]],
        log: false
      )
    end

    assert {:error, {:stale_plan_version, 2}} =
             FountRun.Persistence.append_plan_snapshot(repo, run["id"], next_plan, context,
               expected_version: 1
             )

    {:ok, service} = Principal.new(:service, "planner-service")
    {:ok, service_context} = ActorContext.new(service, owner, screenplay, [:read_run, :manage_run], approvers: [service])
    assert {:error, :owner_required} =
             FountRun.Persistence.append_plan_snapshot(repo, run["id"], next_plan, service_context,
               expected_version: 2
             )
  end

  test "decision resolves once with exact authenticated response", %{repo: repo} do
    {screenplay, revision} = seed_core(repo)
    {:ok, owner} = Principal.new(:human, "owner")
    {:ok, context} = ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run])
    {:ok, run} = FountRun.start_run(repo, start_attrs(screenplay, revision, "key-decision"), context)

    assert {:ok, decision} =
             FountRun.Persistence.put_pending_decision(
               repo,
               run["id"],
               %{
                 "checkpoint_key" => "route",
                 "kind" => "strategy",
                 "prompt" => "Choose",
                 "options" => [%{"id" => "a"}]
               },
               context
             )

    assert {:ok, same} =
             FountRun.Persistence.put_pending_decision(
               repo,
               run["id"],
               %{
                 "checkpoint_key" => "route",
                 "kind" => "strategy",
                 "prompt" => "Choose",
                 "options" => [%{"id" => "a"}]
               },
               context
             )

    assert same["id"] == decision["id"]
    assert {:ok, resolved} = FountRun.Persistence.resolve_decision(repo, decision["id"], %{"choice" => "a"}, context)
    assert resolved["status"] == "resolved"
    assert {:ok, _} = FountRun.Persistence.resolve_decision(repo, decision["id"], %{"choice" => "a"}, context)
    assert {:error, :already_resolved} = FountRun.Persistence.resolve_decision(repo, decision["id"], %{"choice" => "b"}, context)

    assert_raise Postgrex.Error, fn ->
      SQL.query!(repo, "UPDATE fount_run_decisions SET response='{}'::jsonb WHERE id=$1::text::uuid", [decision["id"]], log: false)
    end
  end

  test "competing decision submissions resolve exactly once", %{repo: repo} do
    {screenplay, revision} = seed_core(repo)
    {:ok, owner} = Principal.new(:human, "owner")
    {:ok, context} = ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run])
    {:ok, run} = FountRun.start_run(repo, start_attrs(screenplay, revision, "key-decision-race"), context)

    {:ok, decision} =
      FountRun.Persistence.put_pending_decision(
        repo,
        run["id"],
        %{
          "checkpoint_key" => "race",
          "kind" => "strategy",
          "prompt" => "Choose once",
          "options" => [%{"id" => "a"}, %{"id" => "b"}]
        },
        context
      )

    parent = self()

    tasks =
      for choice <- ["a", "b"] do
        Task.async(fn ->
          send(parent, {:ready, self()})
          receive do
            :go -> :ok
          end
          FountRun.Persistence.resolve_decision(repo, decision["id"], %{"choice" => choice}, context)
        end)
      end

    pids =
      for _ <- tasks do
        assert_receive {:ready, pid}, 1_000
        pid
      end

    Enum.each(pids, &send(&1, :go))
    results = Enum.map(tasks, &Task.await(&1, 5_000))

    assert Enum.count(results, &match?({:ok, %{"status" => "resolved"}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :already_resolved}, &1)) == 1

    %{rows: [[respondent_type, respondent_id, response_fingerprint]]} =
      SQL.query!(
        repo,
        "SELECT respondent_type,respondent_id,response_fingerprint FROM fount_run_decisions WHERE id=$1::text::uuid",
        [decision["id"]],
        log: false
      )

    assert respondent_type == "human"
    assert respondent_id == "owner"
    assert is_binary(response_fingerprint) and byte_size(response_fingerprint) == 64
  end

  test "approval attempts preserve exact review and approval identity without advancing canon", %{repo: repo} do
    {screenplay, revision} = seed_core(repo)
    {:ok, owner} = Principal.new(:human, "owner")
    {:ok, context} = ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run])
    attrs = start_attrs(screenplay, revision, "key-approval", "accept", owner)
    {:ok, run} = FountRun.start_run(repo, attrs, context)
    candidate = seed_candidate(repo, screenplay, revision)

    attempt_attrs = %{
      "candidate_id" => candidate.id,
      "base_revision_id" => revision,
      "content_hash" => candidate.content_hash,
      "check_set_fingerprint" => candidate.check_set_fingerprint,
      "packet" => %{"candidate_id" => candidate.id, "content_hash" => candidate.content_hash},
      "reviewer" => owner,
      "approver" => owner,
      "callback_operation_id" => "approval-op-1",
      "fencing_token" => run["current_fencing_token"]
    }

    assert {:ok, attempt} = FountRun.Persistence.create_approval_attempt(repo, run["id"], attempt_attrs, context)
    assert {:ok, same_attempt} = FountRun.Persistence.create_approval_attempt(repo, run["id"], attempt_attrs, context)
    assert same_attempt["id"] == attempt["id"]

    assert {:error, :idempotency_conflict} =
             FountRun.Persistence.create_approval_attempt(
               repo,
               run["id"],
               put_in(attempt_attrs, ["packet", "content_hash"], String.duplicate("e", 64)),
               context
             )

    {:ok, review} =
      Review.new(
        reviewer: owner,
        candidate_id: candidate.id,
        base_revision_id: revision,
        content_hash: candidate.content_hash,
        report_ids: [],
        check_set_fingerprint: candidate.check_set_fingerprint,
        recommendation: :approve
      )

    assert {:ok, reviewed} =
             FountRun.Persistence.record_approval_review(repo, attempt["id"], review, "approve", context)

    assert reviewed["outcome"] == "reviewed"

    {:ok, approval} =
      Approval.new(
        id: ID.v4(),
        approver: owner,
        screenplay_id: screenplay,
        candidate_id: candidate.id,
        base_revision_id: revision,
        content_hash: candidate.content_hash,
        review: review,
        run_id: run["id"],
        run_policy_version: run["policy"]["version"],
        run_policy_fingerprint: run["policy"]["fingerprint"]
      )

    assert {:ok, ready} =
             FountRun.Persistence.record_approval_payload(
               repo,
               attempt["id"],
               approval.id,
               approval,
               context
             )

    assert ready["outcome"] == "ready"
    assert ready["approval_id"] == approval.id
    assert {:error, :acceptance_bridge_required} =
             FountRun.Persistence.record_approval_outcome(repo, attempt["id"], "accepted", nil, context)

    assert SQL.query!(repo, "SELECT count(*) FROM acceptances", [], log: false).rows == [[0]]

    assert_raise Postgrex.Error, fn ->
      SQL.query!(
        repo,
        "UPDATE fount_run_approval_attempts SET received_review='{}'::jsonb WHERE id=$1::text::uuid",
        [attempt["id"]],
        log: false
      )
    end
  end

  test "step lease, usage and delivery identities survive reload and reject conflicting replay", %{repo: repo} do
    {screenplay, revision} = seed_core(repo)
    {:ok, owner} = Principal.new(:human, "owner")
    {:ok, context} = ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run])
    {:ok, run} = FountRun.start_run(repo, start_attrs(screenplay, revision, "key-storage"), context)
    candidate = seed_candidate(repo, screenplay, revision)

    step_attrs = %{
      "stage" => "write",
      "iteration" => 1,
      "branch_id" => "main",
      "input_revision_id" => revision,
      "idempotency_key" => "write-1",
      "request" => %{"operation" => "fixture"}
    }

    assert {:ok, step} = FountRun.Persistence.create_step(repo, run["id"], step_attrs, context)
    assert {:ok, same_step} = FountRun.Persistence.create_step(repo, run["id"], step_attrs, context)
    assert same_step["id"] == step["id"]
    assert {:error, :idempotency_conflict} =
             FountRun.Persistence.create_step(repo, run["id"], Map.put(step_attrs, "stage", "check"), context)

    assert {:ok, lease} =
             FountRun.Persistence.store_active_lease(
               repo,
               run["id"],
               step["id"],
               %{"owner" => "worker-1", "token" => 1, "expires_at" => "2099-01-01T00:00:00Z"},
               context
             )

    assert lease["lease_token"] == 1
    assert {:ok, loaded} = FountRun.get_run(repo, run["id"], context)
    assert loaded["active_step_id"] == step["id"]

    usage_attrs = %{
      "operation_id" => "provider-op-1",
      "step_id" => step["id"],
      "resource" => "inference_calls",
      "reserved_quantity" => 1,
      "reserved_cost_microunits" => nil,
      "currency" => "USD",
      "knowledge_state" => "unknown"
    }

    assert {:ok, usage} = FountRun.Persistence.reserve_usage(repo, run["id"], usage_attrs, context)
    assert {:ok, same_usage} = FountRun.Persistence.reserve_usage(repo, run["id"], usage_attrs, context)
    assert same_usage["id"] == usage["id"]

    assert {:ok, settled} =
             FountRun.Persistence.settle_usage(
               repo,
               usage["id"],
               %{
                 "settled_quantity" => 1,
                 "settled_cost_microunits" => 1250,
                 "provider_request_id" => "provider-1",
                 "knowledge_state" => "known",
                 "reconciliation_state" => "settled"
               },
               context
             )

    assert settled["settled_cost_microunits"] == 1250
    assert {:error, :already_settled} =
             FountRun.Persistence.settle_usage(repo, usage["id"], %{"settled_quantity" => 2}, context)

    delivery_attrs = %{"candidate_id" => candidate.id, "format" => "fountain", "options" => %{"mode" => "review"}}
    assert {:ok, delivery} = FountRun.Persistence.create_delivery(repo, run["id"], delivery_attrs, context)
    assert {:ok, same_delivery} = FountRun.Persistence.create_delivery(repo, run["id"], delivery_attrs, context)
    assert same_delivery["id"] == delivery["id"]

    assert {:ok, ready} =
             FountRun.Persistence.record_delivery_result(
               repo,
               delivery["id"],
               %{
                 "state" => "ready",
                 "output_checksum" => String.duplicate("f", 64),
                 "output_location" => "artifact://review/fountain"
               },
               context
             )

    assert ready["state"] == "ready"
    assert {:error, :already_resolved} =
             FountRun.Persistence.record_delivery_result(
               repo,
               delivery["id"],
               %{
                 "state" => "ready",
                 "output_checksum" => String.duplicate("f", 64),
                 "output_location" => "artifact://review/fountain"
               },
               context
             )
  end

  test "attempt storage is controlled and events retain step/attempt identity", %{repo: repo} do
    {screenplay, revision} = seed_core(repo)
    {:ok, owner} = Principal.new(:human, "owner")
    {:ok, context} = ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run])
    {:ok, run} = FountRun.start_run(repo, start_attrs(screenplay, revision, "attempt-run"), context)

    {:ok, step} =
      FountRun.Persistence.create_step(
        repo,
        run["id"],
        %{
          "stage" => "intake",
          "iteration" => 0,
          "branch_id" => "main",
          "input_revision_id" => revision,
          "idempotency_key" => "attempt-step",
          "request" => %{"kind" => "storage-only"}
        },
        context
      )

    attrs = %{"step_id" => step["id"], "attempt_number" => 1, "fencing_token" => 0}
    assert {:ok, attempt} = FountRun.Persistence.begin_attempt(repo, run["id"], attrs, context)
    assert attempt["outcome"] == "running"
    assert {:ok, replay} = FountRun.Persistence.begin_attempt(repo, run["id"], attrs, context)
    assert replay["step_id"] == step["id"]

    result = %{
      "outcome" => "unknown",
      "redacted_error" => %{"kind" => "ambiguous"},
      "provider_request_id" => "request-1"
    }

    assert {:ok, finished} = FountRun.Persistence.finish_attempt(repo, step["id"], 1, result, context)
    assert finished["outcome"] == "unknown"
    assert {:ok, replay_finished} = FountRun.Persistence.finish_attempt(repo, step["id"], 1, result, context)
    assert replay_finished["outcome"] == "unknown"

    assert SQL.query!(
             repo,
             "SELECT count(*) FROM fount_run_events WHERE run_id=$1::text::uuid AND step_id=$2::text::uuid AND attempt_number=1",
             [run["id"], step["id"]],
             log: false
           ).rows == [[2]]
  end

  test "cross-screenplay and cross-run references fail transactionally", %{repo: repo} do
    {screenplay, revision} = seed_core(repo)
    {other_screenplay, other_revision} = seed_core(repo)
    other_candidate = seed_candidate(repo, other_screenplay, other_revision)
    {:ok, owner} = Principal.new(:human, "owner")
    {:ok, context} = ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run])
    {:ok, run} = FountRun.start_run(repo, start_attrs(screenplay, revision, "key-cross-1"), context)
    {:ok, run2} = FountRun.start_run(repo, start_attrs(screenplay, revision, "key-cross-2"), context)
    {:ok, foreign_step} =
      FountRun.Persistence.create_step(
        repo,
        run2["id"],
        %{"stage" => "write", "idempotency_key" => "foreign-step", "request" => %{}},
        context
      )

    assert_raise Postgrex.Error, fn ->
      SQL.query!(
        repo,
        "UPDATE fount_runs SET selected_candidate_id=$2::text::uuid WHERE id=$1::text::uuid",
        [run["id"], other_candidate.id],
        log: false
      )
    end

    assert_raise Postgrex.Error, fn ->
      SQL.query!(
        repo,
        "UPDATE fount_runs SET active_step_id=$2::text::uuid WHERE id=$1::text::uuid",
        [run["id"], foreign_step["id"]],
        log: false
      )
    end
  end

  defp seed_core(repo) do
    screenplay = ID.v4()
    revision = ID.v4()

    SQL.query!(repo, "INSERT INTO screenplays(id,key) VALUES($1::text::uuid,$2)", [screenplay, "run-#{screenplay}"], log: false)

    SQL.query!(
      repo,
      "INSERT INTO revisions(id,screenplay_id,parent_id,content_hash,render_hash,model,actor) VALUES($1::text::uuid,$2::text::uuid,NULL,$3,$4,'{}'::jsonb,'fixture')",
      [revision, screenplay, String.duplicate("a", 64), String.duplicate("b", 64)],
      log: false
    )

    SQL.query!(repo, "UPDATE screenplays SET head_revision_id=$2::text::uuid WHERE id=$1::text::uuid", [screenplay, revision], log: false)
    {screenplay, revision}
  end

  defp seed_candidate(repo, screenplay, base_revision) do
    result_revision = ID.v4()
    session = ID.v4()
    candidate = ID.v4()
    content_hash = String.duplicate("c", 64)
    check_set_fingerprint = String.duplicate("d", 64)

    SQL.query!(
      repo,
      "INSERT INTO revisions(id,screenplay_id,parent_id,content_hash,render_hash,model,actor) VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,$4,$5,'{}'::jsonb,'fixture')",
      [result_revision, screenplay, base_revision, content_hash, String.duplicate("e", 64)],
      log: false
    )

    SQL.query!(
      repo,
      "INSERT INTO writing_sessions(id,screenplay_id,base_revision_id,workflow,status,request,strategies,progress,provenance) VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,'develop','review_ready','{}'::jsonb,'[]'::jsonb,'{}'::jsonb,'{}'::jsonb)",
      [session, screenplay, base_revision],
      log: false
    )

    SQL.query!(
      repo,
      "INSERT INTO writing_candidates(id,screenplay_id,session_id,base_revision_id,result_revision_id,label,strategy,change_groups,lineage,provenance,required_checks,check_set_fingerprint) VALUES($1::text::uuid,$2::text::uuid,$3::text::uuid,$4::text::uuid,$5::text::uuid,'fixture','{}'::jsonb,'[]'::jsonb,'[]'::jsonb,'{}'::jsonb,'[]'::jsonb,$6)",
      [candidate, screenplay, session, base_revision, result_revision, check_set_fingerprint],
      log: false
    )

    %{id: candidate, result_revision_id: result_revision, content_hash: content_hash, check_set_fingerprint: check_set_fingerprint}
  end

  defp start_attrs(screenplay, revision, key, completion \\ "candidate", owner \\ nil) do
    approver =
      case {completion, owner} do
        {"accept", %Principal{} = principal} -> Principal.to_map(principal)
        _ -> nil
      end

    %{
      "screenplay_id" => screenplay,
      "base_revision_id" => revision,
      "goal" => "Revise opening",
      "scope" => %{"scene_ids" => ["scene-a"]},
      "constraints" => [],
      "protected_material" => [],
      "client_idempotency_key" => key,
      "policy" => %{
        "gates" => %{
          "investigation_scope" => "automatic",
          "strategy_choice" => "human",
          "candidate_generation" => "automatic",
          "iteration" => "automatic"
        },
        "completion" => completion,
        "approver" => approver,
        "fallback_approver" => nil,
        "route_choice" => %{"rule" => "pause_on_material_tradeoff"},
        "limits" => %{}
      }
    }
  end
end
