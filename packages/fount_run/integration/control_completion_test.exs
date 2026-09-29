defmodule FountRun.ControlCompletionIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Fount.{ID, Persistence, Screenplay}
  alias Fount.Writing.{Approval, Authority, Principal}
  alias FountRun.{ActorContext, ApprovalBridge, Control, PipelineRequest}

  defmodule Repo do
    use Ecto.Repo, otp_app: :fount_run, adapter: Ecto.Adapters.Postgres
  end

  defmodule RepoB do
    use Ecto.Repo, otp_app: :fount_run, adapter: Ecto.Adapters.Postgres
  end

  setup do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    prefix = "phase05_#{String.replace(ID.v4(), "-", "")}"
    {:ok, admin} = Postgrex.start_link(Ecto.Repo.Supervisor.parse_url(url))
    Postgrex.query!(admin, ~s(CREATE SCHEMA "#{prefix}"), [])
    GenServer.stop(admin)

    on_exit(fn ->
      {:ok, cleanup} = Postgrex.start_link(Ecto.Repo.Supervisor.parse_url(url))
      Postgrex.query!(cleanup, ~s(DROP SCHEMA IF EXISTS "#{prefix}" CASCADE), [])
      GenServer.stop(cleanup)
    end)

    start_supervised!(
      {Repo,
       url: url, pool_size: 6, parameters: [search_path: prefix], migration_default_prefix: prefix}
    )

    start_supervised!({RepoB, url: url, pool_size: 1, parameters: [search_path: prefix]})

    Ecto.Migrator.run(Repo, Persistence.migrations_path(), :up, all: true)
    Ecto.Migrator.run(Repo, FountRun.migrations_path(), :up, all: true)
    %{repo: Repo, repo_b: RepoB, prefix: prefix}
  end

  test "C05/C02 public plan and policy commands replay exactly and pause survives Repo restart",
       %{repo: repo, prefix: prefix} do
    {key, root} = seed_screenplay(repo, "steering")
    {_owner, context} = owner_context(root.id, "steering-owner")
    {:ok, run} = FountRun.start_run(repo, start_attrs(root, "steering-run"), context)

    plan =
      run["plan"]
      |> Map.take(
        ~w(screenplay_id base_revision_id goal scope constraints protected_material input_brief input_notes operation_parameters)
      )
      |> Map.put("goal", "Sharpen the opening while preserving the accepted base")

    assert {:ok, first} =
             FountRun.update_plan(repo, run["id"], plan, context,
               expected_version: 1,
               command_id: "plan-command-1"
             )

    assert first["plan"]["version"] == 2
    assert first["replay"] == false

    assert {:ok, replay} =
             FountRun.update_plan(repo, run["id"], plan, context,
               expected_version: 1,
               command_id: "plan-command-1"
             )

    assert replay["plan"]["version"] == 2
    assert replay["replay"] == true

    assert {:error, :command_id_conflict} =
             FountRun.update_plan(
               repo,
               run["id"],
               Map.put(plan, "goal", "Different retry"),
               context,
               expected_version: 1,
               command_id: "plan-command-1"
             )

    current = elem(FountRun.get_run(repo, run["id"], context), 1)

    policy =
      put_in(current, ["policy", "policy", "limits", "max_iterations"], 5)["policy"]["policy"]

    assert {:ok, policy_update} =
             FountRun.update_policy(repo, run["id"], policy, context,
               expected_version: 1,
               command_id: "policy-command-1"
             )

    assert policy_update["policy"]["version"] == 2
    assert {:ok, %{"run" => paused}} = FountRun.pause_run(repo, run["id"], context)
    assert paused["status"] == "paused"

    restart_repo(prefix)
    assert {:ok, %{"run" => resumed}} = FountRun.resume_run(repo, run["id"], context)
    refute resumed["status"] == "paused"

    assert {:ok, %{"run" => stopped}} = FountRun.stop_run(repo, run["id"], context)
    assert stopped["status"] == "stopped"
    assert {:error, :stopped} = FountRun.resume_run(repo, run["id"], context)
    assert {:ok, canonical} = Persistence.load(repo, key)
    assert canonical.revision.id == root.revision.id
  end

  test "C01/C03 exact human approval replays to one Core acceptance and rejects wrong bindings",
       %{repo: repo, repo_b: repo_b} do
    {key, root} = seed_screenplay(repo, "human-approval")
    {owner, context} = owner_context(root.id, "human-owner")
    candidate = candidate_from_edit(repo, key, root, "Mara leaves before dawn.")

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "human-run", completion: "accept", approver: owner),
        context
      )

    decision = final_decision(repo, run, candidate, owner, context)
    request = approval_response(decision)

    parent = self()

    tasks =
      for connection_repo <- [repo, repo_b] do
        Task.async(fn ->
          [[backend_pid]] = sql(connection_repo, "SELECT pg_backend_pid()", [])
          send(parent, {:approval_connection_ready, self(), backend_pid})

          receive do
            :race_approval -> :ok
          end

          {backend_pid, FountRun.approve_run(connection_repo, run["id"], request, context)}
        end)
      end

    assert_receive {:approval_connection_ready, first_pid, first_backend}, 5_000
    assert_receive {:approval_connection_ready, second_pid, second_backend}, 5_000
    refute first_backend == second_backend
    send(first_pid, :race_approval)
    send(second_pid, :race_approval)

    results =
      Enum.map(tasks, fn task ->
        {_backend, result} = Task.await(task, 15_000)
        result
      end)

    assert Enum.all?(results, &match?({:ok, _}, &1))

    approval_ids = results |> Enum.map(fn {:ok, value} -> value["approval_id"] end) |> Enum.uniq()
    assert length(approval_ids) == 1

    assert {:ok, %{"status" => "partial", "stage" => "deliver"}} =
             FountRun.get_run(repo, run["id"], context)

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid AND outcome='accepted'",
               [run["id"]]
             )

    assert {:ok, head} = Persistence.load(repo, key)
    assert head.revision.id == candidate.screenplay.revision.id

    assert {:error, :cross_run_decision} =
             FountRun.approve_run(repo, ID.v4(), request, context)

    bad = Map.put(request, "context_fingerprint", String.duplicate("0", 64))
    assert {:error, :stale_decision_context} = FountRun.approve_run(repo, run["id"], bad, context)

    assert {:error, :decision_conflict} =
             FountRun.submit_decision(
               repo,
               decision["id"],
               request |> Map.delete("decision_id") |> Map.put("choice", "reject"),
               context
             )

    for field <- ["candidate_id", "check_set_fingerprint", "content_hash"] do
      altered =
        request
        |> Map.delete("decision_id")
        |> Map.put("choice", "approve")
        |> Map.put(field, ID.v4())

      assert {:error, :unknown_decision_response_field} =
               FountRun.submit_decision(repo, decision["id"], altered, context)
    end

    assert {:error, :stale_decision_binding} =
             FountRun.approve_run(repo, run["id"], Map.put(request, "plan_version", 99), context)

    assert {:error, :stale_decision_binding} =
             FountRun.approve_run(
               repo,
               run["id"],
               Map.put(request, "policy_version", 99),
               context
             )

    {:ok, other} = Principal.new(:human, "other-reviewer")
    {:ok, other_context} = ActorContext.new(other, owner, root.id, [:read_run, :manage_run])
    assert {:error, :unauthorized} = FountRun.approve_run(repo, run["id"], request, other_context)
  end

  test "C02 a stopped run fences an in-flight callback, retains safe evidence, and cannot accept later",
       %{repo: repo, repo_b: repo_b} do
    {key, root} = seed_screenplay(repo, "stop-callback")
    candidate = candidate_from_edit(repo, key, root, "Mara locks the door.")
    {:ok, owner} = Principal.new(:human, "stop-owner")
    {:ok, service} = Principal.new(:service, "stop-service")

    {:ok, owner_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, service_context} =
      ActorContext.new(service, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "stop-callback-run", completion: "accept", approver: service),
        owner_context
      )

    assert {:ok, %{"selected_candidate_id" => candidate_id}} =
             Control.mark_completion(repo, run["id"], candidate.id, "partial", owner_context)

    assert candidate_id == candidate.id

    parent = self()

    callback = fn _packet ->
      send(parent, {:approval_callback_started, self()})

      receive do
        :release_callback -> %{"recommendation" => "approve", "findings" => [], "overrides" => []}
      end
    end

    task =
      Task.async(fn ->
        ApprovalBridge.automated(
          repo,
          run,
          candidate.id,
          owner_context,
          service_context,
          callback
        )
      end)

    assert_receive {:approval_callback_started, callback_pid}, 5_000

    assert {:ok, %{"run" => %{"status" => "stopped"}}} =
             FountRun.stop_run(repo_b, run["id"], owner_context)

    send(callback_pid, :release_callback)
    assert {:error, :already_resolved} = Task.await(task, 15_000)

    assert [[0]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )

    [[outcome, callback_evidence]] =
      sql(
        repo,
        "SELECT outcome,callback_response::text FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid",
        [run["id"]]
      )

    assert outcome == "fenced"
    assert is_binary(callback_evidence)
    assert callback_evidence =~ "recommendation"

    artifact_root = Path.join(System.tmp_dir!(), "fount-stopped-#{ID.v4()}")
    on_exit(fn -> File.rm_rf(artifact_root) end)

    assert {:ok, exported} =
             FountRun.deliver(repo, run["id"], "stopped", owner_context,
               artifact_root: artifact_root
             )

    assert exported["run"]["status"] == "stopped"

    Enum.each(exported["manifest"]["artifacts"], fn artifact ->
      bytes = File.read!(Path.join(artifact_root, artifact["output_location"]))
      assert sha256(bytes) == artifact["output_checksum"]
    end)

    never_again = fn _packet -> flunk("stopped approval callback must not be redispatched") end

    assert {:error, :stopped} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               never_again
             )

    assert {:ok, head} = Persistence.load(repo, key)
    assert head.revision.id == root.revision.id
  end

  test "C02 stop from a second connection fences an active worker claim and retains its candidate",
       %{repo: repo, repo_b: repo_b} do
    {key, root} = seed_screenplay(repo, "stop-worker")
    candidate = candidate_from_edit(repo, key, root, "Mara waits at the window.")
    {_owner, context} = owner_context(root.id, "worker-stop-owner")
    {:ok, run} = FountRun.start_run(repo, start_attrs(root, "worker-stop-run"), context)

    assert {:ok, %{"selected_candidate_id" => candidate_id}} =
             Control.mark_completion(repo, run["id"], candidate.id, "partial", context)

    assert candidate_id == candidate.id

    {:ok, request} =
      PipelineRequest.new(%{
        "version" => 1,
        "workflow" => "develop",
        "mode" => "revise",
        "base_revision_id" => root.revision.id,
        "instruction" => "Inspect the retained candidate",
        "selection" => %{"whole_screenplay" => true},
        "constraints" => [],
        "alternatives" => 1,
        "options" => %{"placement" => %{"kind" => "start"}}
      })

    assert {:ok, _step} =
             FountRun.enqueue_step(
               repo,
               run["id"],
               %{
                 "stage" => "write",
                 "iteration" => 0,
                 "branch_id" => "main",
                 "input_revision_id" => root.revision.id,
                 "request" => request,
                 "idempotency_key" => "active-worker-before-stop"
               },
               context
             )

    {:ok, claim} =
      FountRun.ExecutionStore.claim(repo, run["id"], "active-worker", context, lease_ms: 5_000)

    [[worker_backend]] = sql(repo, "SELECT pg_backend_pid()", [])
    [[stop_backend]] = sql(repo_b, "SELECT pg_backend_pid()", [])
    refute worker_backend == stop_backend

    assert {:ok, %{"run" => %{"status" => "stopped"}}} =
             FountRun.stop_run(repo_b, run["id"], context)

    assert {:error, :stale_fencing_token} =
             FountRun.ExecutionStore.domain_guard(repo, claim, :candidate, ID.v4())

    assert [["stopped", ^candidate_id, new_token]] =
             sql(
               repo,
               "SELECT status,selected_candidate_id::text,current_fencing_token FROM fount_runs WHERE id=$1::text::uuid",
               [run["id"]]
             )

    assert new_token > claim["fencing_token"]

    assert [["fenced", "fenced", token]] =
             sql(
               repo,
               "SELECT a.outcome,s.status,a.fencing_token FROM fount_run_attempts a JOIN fount_run_steps s ON s.id=a.step_id WHERE a.step_id=$1::text::uuid",
               [claim["step_id"]]
             )

    assert token == claim["fencing_token"]
    assert {:ok, head} = Persistence.load(repo, key)
    assert head.revision.id == root.revision.id
  end

  test "C04 malformed automated review keeps redacted evidence and never reaches Core", %{
    repo: repo
  } do
    {key, root} = seed_screenplay(repo, "malformed-review")
    candidate = candidate_from_edit(repo, key, root, "Mara checks the latch.")
    {:ok, owner} = Principal.new(:human, "malformed-owner")
    {:ok, service} = Principal.new(:service, "malformed-service")

    {:ok, owner_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, service_context} =
      ActorContext.new(service, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "malformed-review-run", completion: "accept", approver: service),
        owner_context
      )

    callback = fn _packet ->
      %{
        "recommendation" => "approve",
        "findings" => [],
        "overrides" => [],
        "provider_private" => %{"token" => "must-not-persist"}
      }
    end

    assert {:error, :malformed_approval_response} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback
             )

    [[outcome, evidence]] =
      sql(
        repo,
        "SELECT outcome,callback_response::text FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid",
        [run["id"]]
      )

    assert outcome == "invalid"
    assert evidence =~ "provider_private"
    refute evidence =~ "must-not-persist"

    assert [[0]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )
  end

  test "C04 rejected automation opens a fresh human fallback decision linked to the failed attempt",
       %{repo: repo} do
    {key, root} = seed_screenplay(repo, "fallback")
    candidate = candidate_from_edit(repo, key, root, "Mara leaves the porch light on.")
    {:ok, owner} = Principal.new(:human, "fallback-owner")
    {:ok, service} = Principal.new(:service, "fallback-service")

    {:ok, owner_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, service_context} =
      ActorContext.new(service, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "fallback-run",
          completion: "accept",
          approver: service,
          fallback_approver: owner
        ),
        owner_context
      )

    {:ok, packet} = FountWorkshop.Review.packet(repo, candidate.id)

    :ok =
      persist_succeeded_check(
        repo,
        run,
        candidate.id,
        packet["check_set_fingerprint"],
        owner_context
      )

    claim = %{
      "stage" => "decide",
      "run_id" => run["id"],
      "step_id" => nil,
      "input_candidate_id" => candidate.id
    }

    callback = fn _packet ->
      %{"recommendation" => "reject", "findings" => [], "overrides" => []}
    end

    assert {:ok, %{"status" => "waiting_for_final_approval", "decision_id" => decision_id}} =
             FountRun.CompletionHandler.execute(claim,
               repo: repo,
               actor_context: owner_context,
               approval_context: service_context,
               approval_callback: callback
             )

    [[parent_id, parent_outcome]] =
      sql(
        repo,
        "SELECT id::text,outcome FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid ORDER BY inserted_at,id LIMIT 1",
        [run["id"]]
      )

    assert parent_outcome == "rejected"

    {:ok, progress} = FountRun.progress(repo, run["id"], owner_context)
    decision = Enum.find(progress["decisions"], &(&1["id"] == decision_id))
    assert decision

    assert {:ok, accepted} =
             FountRun.approve_run(repo, run["id"], approval_response(decision), owner_context)

    assert accepted["status"] == "accepted"

    [[child_parent]] =
      sql(
        repo,
        "SELECT parent_attempt_id::text FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid AND id<>$2::text::uuid ORDER BY inserted_at,id LIMIT 1",
        [run["id"], parent_id]
      )

    assert child_parent == parent_id

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )
  end

  test "C04 required semantic uncertainty needs a declared human override with a reason",
       %{repo: repo} do
    {key, root} = seed_screenplay(repo, "semantic-override")
    {owner, context} = owner_context(root.id, "semantic-owner")
    action = Enum.find(root.ir.elements, &(&1.type == :action))

    constraint = %{
      "id" => "story-truth",
      "kind" => "semantic",
      "target" => %{"kind" => "screenplay", "id" => root.id},
      "spec" => %{"proposition" => "The reveal reads clearly", "expected" => true},
      "severity" => "required"
    }

    {:ok, session} =
      Persistence.save_session(repo, %{
        screenplay_id: root.id,
        base_revision_id: root.revision.id,
        workflow: "pass",
        request: %{
          "constraints" => [constraint],
          "approval" => %{"overridable_constraint_ids" => ["story-truth"]}
        },
        status: "open"
      })

    {:ok, edited, _} =
      Screenplay.apply(root, [
        %{
          "kind" => "replace_text",
          "target" => %{"kind" => "element", "id" => action.id},
          "value" => "Mara reveals the hidden letter."
        }
      ])

    check = %{
      "constraint_id" => "story-truth",
      "kind" => "semantic",
      "severity" => "required",
      "evaluation" => "semantic",
      "status" => "unknown"
    }

    {:ok, candidate} =
      Persistence.save_candidate(repo, session.id, %{
        screenplay: edited,
        provenance: %{"constraints" => [constraint], "checks" => [check], "report_ids" => []}
      })

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "semantic-override-run", completion: "accept", approver: owner),
        context
      )

    decision = final_decision(repo, run, candidate, owner, context)
    request = approval_response(decision)

    assert {:error,
            {:core_acceptance_rejected,
             {:review_blockers, [%{"reason" => "human_override_required"}]}}} =
             FountRun.approve_run(repo, run["id"], request, context)

    assert [["failed", reason]] =
             sql(
               repo,
               "SELECT outcome,outcome_reason FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid",
               [run["id"]]
             )

    assert reason =~ "review_blockers"

    assert [[0]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [root.id]
             )

    {:ok, blank_run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "semantic-blank-run", completion: "accept", approver: owner),
        context
      )

    blank_decision = final_decision(repo, blank_run, candidate, owner, context)

    blank =
      blank_decision
      |> approval_response()
      |> Map.put("overrides", [%{"constraint_id" => "story-truth", "reason" => " "}])

    assert {:error, _} = FountRun.approve_run(repo, blank_run["id"], blank, context)

    assert [[0]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [root.id]
             )

    {:ok, approved_run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "semantic-approved-run", completion: "accept", approver: owner),
        context
      )

    approved_decision = final_decision(repo, approved_run, candidate, owner, context)

    accepted =
      Map.put(approval_response(approved_decision), "overrides", [
        %{"constraint_id" => "story-truth", "reason" => "Writer inspected the ambiguity"}
      ])

    assert {:ok, result} = FountRun.approve_run(repo, approved_run["id"], accepted, context)
    assert is_binary(result["approval_id"])
    assert {:ok, head} = Persistence.load(repo, key)
    assert head.revision.id == candidate.screenplay.revision.id

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [root.id]
             )
  end

  test "C04 deterministic required failure blocks a human even with an override", %{repo: repo} do
    {key, root} = seed_screenplay(repo, "deterministic-fail")
    {owner, context} = owner_context(root.id, "deterministic-owner")
    action = Enum.find(root.ir.elements, &(&1.type == :action))

    {:ok, session} =
      Persistence.save_session(repo, %{
        screenplay_id: root.id,
        base_revision_id: root.revision.id,
        workflow: "pass",
        request: %{"constraints" => []},
        status: "open"
      })

    {:ok, edited, _} =
      Screenplay.apply(root, [
        %{
          "kind" => "replace_text",
          "target" => %{"kind" => "element", "id" => action.id},
          "value" => "Mara pockets the evidence."
        }
      ])

    check = %{
      "constraint_id" => "application-structure",
      "kind" => "application",
      "severity" => "required",
      "evaluation" => "deterministic",
      "status" => "fail"
    }

    {:ok, candidate} =
      Persistence.save_candidate(repo, session.id, %{
        screenplay: edited,
        provenance: %{"checks" => [check], "report_ids" => []}
      })

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "deterministic-fail-run", completion: "accept", approver: owner),
        context
      )

    decision = final_decision(repo, run, candidate, owner, context)

    request =
      decision
      |> approval_response()
      |> Map.put("overrides", [
        %{"constraint_id" => "application-structure", "reason" => "Writer inspected this check"}
      ])

    assert {:error, _} = FountRun.approve_run(repo, run["id"], request, context)

    {:ok, no_override_run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "deterministic-no-override-run", completion: "accept", approver: owner),
        context
      )

    no_override_decision = final_decision(repo, no_override_run, candidate, owner, context)

    assert {:error,
            {:core_acceptance_rejected,
             {:review_blockers, [%{"reason" => "required_check_not_passing"}]}}} =
             FountRun.approve_run(
               repo,
               no_override_run["id"],
               approval_response(no_override_decision),
               context
             )

    {:ok, candidate_map} = Persistence.candidate(repo, candidate.id)

    for type <- [:agent, :service] do
      {:ok, principal} = Principal.new(type, "deterministic-#{type}")
      {:ok, authority} = Authority.new(principal, root.id, [:approve])
      {:ok, approval} = Approval.direct(candidate_map, principal, ID.v4())

      assert {:error, {:review_blockers, [%{"reason" => "required_check_not_passing"}]}} =
               Persistence.accept_candidate(repo, candidate.id,
                 approval: approval,
                 authority: authority
               )
    end

    assert {:ok, head} = Persistence.load(repo, key)
    assert head.revision.id == root.revision.id

    assert [[0]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [root.id]
             )
  end

  test "C03 candidate-only completion exports byte-verified artifacts without moving canon", %{
    repo: repo
  } do
    {key, root} = seed_screenplay(repo, "candidate-export")
    {_owner, context} = owner_context(root.id, "candidate-owner")
    candidate = candidate_from_edit(repo, key, root, "Mara waits at the locked door.")
    {:ok, run} = FountRun.start_run(repo, start_attrs(root, "candidate-run"), context)

    assert {:ok, _} =
             FountRun.Control.mark_completion(repo, run["id"], candidate.id, "partial", context)

    artifact_root = Path.join(System.tmp_dir!(), "fount-run-phase05-#{ID.v4()}")
    on_exit(fn -> File.rm_rf(artifact_root) end)

    assert {:ok, delivered} =
             FountRun.deliver(repo, run["id"], "bundle", context, artifact_root: artifact_root)

    fountain = Path.join([artifact_root, "bundle", "screenplay.fountain"])
    manifest = Path.join([artifact_root, "bundle", "manifest.json"])
    assert File.regular?(fountain)
    assert File.regular?(manifest)
    assert File.read!(fountain) =~ "Mara waits at the locked door."

    decoded = Jason.decode!(File.read!(manifest))
    assert decoded["completion_kind"] == "candidate"
    assert decoded["candidate_id"] == candidate.id
    assert decoded["result_revision_id"] == candidate.screenplay.revision.id
    assert delivered["manifest"]["manifest_sha256"] == sha256(File.read!(manifest))

    assert {:ok, head} = Persistence.load(repo, key)
    assert head.revision.id == root.revision.id

    File.rm!(fountain)

    assert {:ok, _retry} =
             FountRun.deliver(repo, run["id"], "bundle", context, artifact_root: artifact_root)

    assert File.regular?(fountain)

    assert [[2]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_deliveries WHERE run_id=$1::text::uuid AND format='fountain'",
               [run["id"]]
             )
  end

  test "C06 configured PDF failure retries only PDF and verifies every delivered byte", %{
    repo: repo
  } do
    {key, root} = seed_screenplay(repo, "pdf-retry")
    {_owner, context} = owner_context(root.id, "pdf-owner")
    candidate = candidate_from_edit(repo, key, root, "Mara folds the receipt.")
    {:ok, run} = FountRun.start_run(repo, start_attrs(root, "pdf-retry-run"), context)

    assert {:ok, _} =
             FountRun.Control.mark_completion(repo, run["id"], candidate.id, "partial", context)

    artifact_root = Path.join(System.tmp_dir!(), "fount-run-pdf-#{ID.v4()}")
    on_exit(fn -> File.rm_rf(artifact_root) end)

    assert {:partial, :delivery_partial, first} =
             FountRun.deliver(repo, run["id"], "bundle", context,
               artifact_root: artifact_root,
               pdf: true,
               pdf_options: [renderer: "/no/such/afterwriting"]
             )

    assert Enum.find(first["manifest"]["artifacts"], &(&1["format"] == "pdf"))["state"] ==
             "failed"

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_deliveries WHERE run_id=$1::text::uuid AND format='pdf' AND state='failed'",
               [run["id"]]
             )

    assert {:ok, second} =
             FountRun.deliver(repo, run["id"], "bundle", context,
               artifact_root: artifact_root,
               pdf: true
             )

    artifacts = second["manifest"]["artifacts"]
    assert Enum.all?(artifacts, &(&1["state"] == "ready"))
    assert Enum.count(artifacts, &(&1["format"] == "pdf")) == 1
    assert Enum.all?(Enum.reject(artifacts, &(&1["format"] == "pdf")), & &1["reused"])

    Enum.each(artifacts, fn artifact ->
      bytes = File.read!(Path.join(artifact_root, artifact["output_location"]))
      assert sha256(bytes) == artifact["output_checksum"]
    end)

    assert [[2]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_deliveries WHERE run_id=$1::text::uuid AND format='pdf'",
               [run["id"]]
             )

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_deliveries WHERE run_id=$1::text::uuid AND format='fountain'",
               [run["id"]]
             )

    pdf = Path.join([artifact_root, "bundle", "screenplay.pdf"])
    {info, 0} = System.cmd("pdfinfo", [pdf])
    assert info =~ "Pages:"

    IO.puts(
      "PDF_QC " <>
        (info
         |> String.split("\n")
         |> Enum.filter(&String.starts_with?(&1, ["Pages:", "Page size:"]))
         |> Enum.join(" | "))
    )

    assert {:ok, head} = Persistence.load(repo, key)
    assert head.revision.id == root.revision.id
  end

  test "C03 accepted canon survives a failed PDF delivery until the missing format retries", %{
    repo: repo
  } do
    {key, root} = seed_screenplay(repo, "accepted-delivery-retry")
    {owner, context} = owner_context(root.id, "accepted-delivery-owner")
    candidate = candidate_from_edit(repo, key, root, "Mara carries the ledger upstairs.")

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "accepted-delivery-run", completion: "accept", approver: owner),
        context
      )

    decision = final_decision(repo, run, candidate, owner, context)

    assert {:ok, accepted} =
             FountRun.approve_run(repo, run["id"], approval_response(decision), context)

    assert accepted["status"] == "accepted"
    artifact_root = Path.join(System.tmp_dir!(), "fount-accepted-delivery-#{ID.v4()}")
    on_exit(fn -> File.rm_rf(artifact_root) end)

    assert {:partial, :delivery_partial, first} =
             FountRun.deliver(repo, run["id"], "bundle", context,
               artifact_root: artifact_root,
               pdf: true,
               pdf_options: [renderer: "/no/such/afterwriting"]
             )

    assert first["run"]["status"] == "partial"

    assert Enum.find(first["manifest"]["artifacts"], &(&1["format"] == "pdf"))["state"] ==
             "failed"

    assert {:ok, canonical} = Persistence.load(repo, key)
    assert canonical.revision.id == candidate.screenplay.revision.id

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE run_id=$1::text::uuid AND acceptance_kind='approved'",
               [run["id"]]
             )

    assert {:ok, delivered} =
             FountRun.deliver(repo, run["id"], "bundle", context,
               artifact_root: artifact_root,
               pdf: true
             )

    assert delivered["run"]["status"] == "completed_accepted"
    assert Enum.all?(delivered["manifest"]["artifacts"], &(&1["state"] == "ready"))

    assert Enum.all?(
             Enum.reject(delivered["manifest"]["artifacts"], &(&1["format"] == "pdf")),
             & &1["reused"]
           )

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE run_id=$1::text::uuid AND acceptance_kind='approved'",
               [run["id"]]
             )
  end

  test "C05 a plan change fences a saved automated review before Core acceptance", %{repo: repo} do
    {key, root} = seed_screenplay(repo, "plan-fence")
    candidate = candidate_from_edit(repo, key, root, "Mara opens the curtains.")
    {:ok, owner} = Principal.new(:human, "plan-fence-owner")
    {:ok, service} = Principal.new(:service, "plan-fence-service")

    {:ok, owner_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, service_context} =
      ActorContext.new(service, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "plan-fence-run", completion: "accept", approver: service),
        owner_context
      )

    callback = fn _packet ->
      %{"recommendation" => "approve", "findings" => [], "overrides" => []}
    end

    fault = fn
      :after_review_persistence -> {:error, :hold_after_review}
      _ -> :ok
    end

    assert {:error, {:fault, :after_review_persistence, :hold_after_review}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback,
               fault_injector: fault
             )

    current = elem(FountRun.get_run(repo, run["id"], owner_context), 1)

    plan =
      current["plan"]
      |> Map.take(
        ~w(screenplay_id base_revision_id goal scope constraints protected_material input_brief input_notes operation_parameters)
      )
      |> Map.put("input_notes", [
        %{"reference" => "test://review", "sha256" => sha256("Changed after review")}
      ])

    assert {:ok, updated} =
             FountRun.update_plan(repo, run["id"], plan, owner_context,
               expected_version: 1,
               command_id: "plan-fence-update"
             )

    assert updated["plan"]["version"] == 2

    assert {:error, {:approval_attempt_terminal, "fenced", _reason}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback
             )

    assert [[0]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )

    assert [["fenced"]] =
             sql(
               repo,
               "SELECT outcome FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid",
               [run["id"]]
             )
  end

  test "C05 a policy change fences identical saved pages and preserves immutable snapshots",
       %{repo: repo} do
    {key, root} = seed_screenplay(repo, "policy-fence")
    candidate = candidate_from_edit(repo, key, root, "Mara opens the curtains.")
    {:ok, owner} = Principal.new(:human, "policy-fence-owner")
    {:ok, service} = Principal.new(:service, "policy-fence-service")

    {:ok, owner_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, service_context} =
      ActorContext.new(service, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "policy-fence-run", completion: "accept", approver: service),
        owner_context
      )

    callback = fn _packet ->
      %{"recommendation" => "approve", "findings" => [], "overrides" => []}
    end

    fault = fn
      :after_review_persistence -> {:error, :hold_after_policy_review}
      _ -> :ok
    end

    assert {:error, {:fault, :after_review_persistence, :hold_after_policy_review}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback,
               fault_injector: fault
             )

    before_packet = elem(FountWorkshop.Review.packet(repo, candidate.id), 1)
    current = elem(FountRun.get_run(repo, run["id"], owner_context), 1)
    policy = put_in(current, ["policy", "policy", "limits", "max_iterations"], 4)
    policy = policy["policy"]["policy"]

    assert {:ok, changed} =
             FountRun.update_policy(repo, run["id"], policy, owner_context,
               expected_version: 1,
               command_id: "policy-fence-change"
             )

    assert changed["policy"]["version"] == 2
    assert changed["replay"] == false

    assert {:ok, replay} =
             FountRun.update_policy(repo, run["id"], policy, owner_context,
               expected_version: 1,
               command_id: "policy-fence-change"
             )

    assert replay["replay"] == true
    assert replay["policy"]["version"] == 2

    assert [[1, 2]] =
             sql(
               repo,
               "SELECT min(version),max(version) FROM fount_run_policies WHERE run_id=$1::text::uuid",
               [run["id"]]
             )

    assert {:error, {:approval_attempt_terminal, "fenced", _reason}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback
             )

    assert [["fenced", 1, 1]] =
             sql(
               repo,
               "SELECT outcome,plan_version,policy_version FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid",
               [run["id"]]
             )

    after_packet = elem(FountWorkshop.Review.packet(repo, candidate.id), 1)
    assert after_packet["content_hash"] == before_packet["content_hash"]
    assert after_packet["check_set_fingerprint"] == before_packet["check_set_fingerprint"]
    assert {:ok, head} = Persistence.load(repo, key)
    assert head.revision.id == root.revision.id

    assert [[0]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [root.id]
             )
  end

  test "C06 ambiguous callback response pauses for reconciliation and never blindly redispatches",
       %{repo: repo} do
    {key, root} = seed_screenplay(repo, "unknown-recovery")
    candidate = candidate_from_edit(repo, key, root, "Mara closes the ledger.")
    {:ok, owner} = Principal.new(:human, "unknown-owner")
    {:ok, service} = Principal.new(:service, "unknown-service")

    {:ok, owner_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, service_context} =
      ActorContext.new(service, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "unknown-run", completion: "accept", approver: service),
        owner_context
      )

    {:ok, calls} = Agent.start_link(fn -> 0 end)

    callback = fn _packet ->
      Agent.update(calls, &(&1 + 1))
      %{"recommendation" => "approve", "findings" => [], "overrides" => []}
    end

    before_dispatch = fn
      :before_callback_dispatch -> {:error, :held_before_dispatch}
      _ -> :ok
    end

    assert {:error, {:fault, :before_callback_dispatch, :held_before_dispatch}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback,
               fault_injector: before_dispatch
             )

    assert Agent.get(calls, & &1) == 0

    assert [["pending", nil]] =
             sql(
               repo,
               "SELECT outcome,callback_response FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid",
               [run["id"]]
             )

    fault = fn
      :after_callback_response_before_persistence -> {:error, :lost_response}
      _ -> :ok
    end

    assert {:partial, :approval_outcome_unknown, %{"approval_attempt_id" => attempt_id}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback,
               fault_injector: fault
             )

    assert Agent.get(calls, & &1) == 1

    never_again = fn _packet -> flunk("unknown callback must be reconciled, not redispatched") end

    assert {:partial, :approval_outcome_unknown, %{"approval_attempt_id" => ^attempt_id}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               never_again
             )

    reconciler = fn operation_id, _packet ->
      assert is_binary(operation_id)
      {:ok, %{"recommendation" => "approve", "findings" => [], "overrides" => []}}
    end

    assert {:ok, accepted} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               never_again,
               approval_reconciler: reconciler
             )

    assert accepted["status"] == "accepted"
    assert Agent.get(calls, & &1) == 1

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )
  end

  test "C05 three-way rebase composes candidate edits on the accepted head and binds a new check",
       %{
         repo: repo
       } do
    root =
      Screenplay.new(
        body: [
          %{
            type: :scene,
            heading: "INT. OFFICE - NIGHT",
            elements: [
              %{type: :action, text: "Mara opens the drawer."},
              %{type: :action, text: "Lena studies the receipt."},
              %{type: :action, text: "The station clock stops."}
            ]
          }
        ]
      )

    key = "phase05-rebase-#{ID.v4()}"
    assert {:ok, ^root} = Persistence.create(repo, key, root)
    [first, second, third] = Enum.filter(root.ir.elements, &(&1.type == :action))
    {owner, context} = owner_context(root.id, "rebase-owner")

    run_attrs =
      put_in(start_attrs(root, "rebase-run"), ["policy", "limits"], %{
        "max_inference_calls" => 7,
        "money" => %{"currency" => "USD", "max_microunits" => 10_000}
      })

    {:ok, run} = FountRun.start_run(repo, run_attrs, context)

    sql(
      repo,
      "INSERT INTO fount_run_usage(id,operation_id,run_id,screenplay_id,resource,reserved_quantity,settled_quantity,currency,reserved_cost_microunits,settled_cost_microunits,knowledge_state,reconciliation_state,settled_at) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,'inference',2,2,'USD',5000,5000,'known','settled',now())",
      [ID.v4(), "rebase-parent-usage:#{ID.v4()}", run["id"], root.id]
    )

    candidate_ops = [
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => first.id},
        "value" => "Mara hides the receipt in the drawer."
      },
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => second.id},
        "value" => "Lena notices the forged signature."
      }
    ]

    {:ok, envelope} =
      PipelineRequest.new(%{
        "version" => 1,
        "workflow" => "develop",
        "mode" => "revise",
        "base_revision_id" => root.revision.id,
        "instruction" => "Rebase the saved edit",
        "selection" => %{"whole_screenplay" => true},
        "constraints" => [],
        "alternatives" => 1,
        "options" => %{"placement" => %{"kind" => "start"}}
      })

    services = %{store: FountWorkshop.Store.new(repo)}
    {:ok, session} = FountWorkshop.Session.open(root, envelope["workshop_request"], services)

    {:ok, candidate} =
      FountWorkshop.Candidate.manual(session["id"], candidate_ops, services,
        actor: "rebase-writer"
      )

    candidate_id = candidate["id"]
    {:ok, packet} = FountWorkshop.Review.packet(repo, candidate_id)

    {:ok, check} =
      FountRun.Persistence.create_step(
        repo,
        run["id"],
        %{
          "stage" => "check",
          "iteration" => 0,
          "branch_id" => "main",
          "input_revision_id" => root.revision.id,
          "input_candidate_id" => candidate_id,
          "request" => envelope,
          "idempotency_key" => "pre-rebase-check"
        },
        context
      )

    check_result = %{
      "candidate_id" => candidate_id,
      "check_set_fingerprint" => packet["check_set_fingerprint"],
      "checks" => [],
      "report_ids" => []
    }

    sql(
      repo,
      "UPDATE fount_run_steps SET status='succeeded',result=$2::jsonb,result_fingerprint=$3,completed_at=now(),updated_at=now() WHERE id=$1::text::uuid",
      [check["id"], check_result, sha256(Jason.encode!(check_result))]
    )

    attrs = %{
      "checkpoint_key" => "stale-base:#{candidate_id}",
      "kind" => "rebase",
      "prompt" => "Resolve the exact three-way conflict",
      "options" => [
        %{"id" => "rebase", "label" => "Rebase"},
        %{"id" => "stop", "label" => "Stop"}
      ],
      "step_id" => check["id"],
      "candidate_id" => candidate_id,
      "base_revision_id" => packet["base_revision_id"],
      "content_hash" => packet["content_hash"],
      "check_set_fingerprint" => packet["check_set_fingerprint"],
      "authorized_principal" => Principal.to_map(owner)
    }

    {:ok, decision} = FountRun.Persistence.put_pending_decision(repo, run["id"], attrs, context)
    old_approval = final_decision(repo, run, candidate, owner, context)
    sql(repo, "UPDATE fount_runs SET iteration=2 WHERE id=$1::text::uuid", [run["id"]])

    current_ops = [
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => first.id},
        "value" => "Mara gives the receipt to Dan."
      },
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => third.id},
        "value" => "The station clock keeps running."
      }
    ]

    {:ok, current_model, current_changes} = Screenplay.apply(root, current_ops)

    {:ok, current_candidate} =
      Persistence.save_edit_candidate(repo, key, current_model,
        expected_revision: root.revision.id,
        operations: current_changes.operations
      )

    {:ok, current_map} = Persistence.candidate(repo, current_candidate.id)
    {:ok, authority} = Authority.new(owner, root.id, [:approve])
    {:ok, approval} = Approval.direct(current_map, owner, ID.v4())

    assert {:ok, accepted_head} =
             Persistence.accept_candidate(repo, current_candidate.id,
               approval: approval,
               authority: authority
             )

    {:ok, candidate_map} = Persistence.candidate(repo, candidate_id)
    groups = FountWorkshop.Candidate.proposal(candidate_map)["groups"]
    conflicts = FountWorkshop.Rebase.conflicts(root, accepted_head, candidate_map, groups)
    assert length(conflicts) >= 1
    choices = Map.new(conflicts, &{&1["group_id"], "candidate"})

    response = %{
      "choice" => "rebase",
      "context_fingerprint" => decision["context_fingerprint"],
      "plan_version" => decision["plan_version"],
      "policy_version" => decision["policy_version"],
      "resolutions" => %{"choices" => choices}
    }

    assert {:ok, rebased} = FountRun.submit_decision(repo, decision["id"], response, context)
    assert rebased["outcome"] == "rebased"
    assert rebased["candidate_id"] != candidate_id
    assert rebased["run_id"] != run["id"]

    assert [[2, parent_run_id]] =
             sql(
               repo,
               "SELECT iteration,parent_run_id::text FROM fount_runs WHERE id=$1::text::uuid",
               [rebased["run_id"]]
             )

    assert parent_run_id == run["id"]
    {:ok, successor} = FountRun.get_run(repo, rebased["run_id"], context)
    assert successor["policy"]["policy"]["limits"] == run["policy"]["policy"]["limits"]
    {:ok, new_candidate} = Persistence.candidate(repo, rebased["candidate_id"])
    assert new_candidate["base_revision_id"] == accepted_head.revision.id

    assert Fount.Query.node(new_candidate["screenplay"], first.id).text ==
             "Mara hides the receipt in the drawer."

    assert Fount.Query.node(new_candidate["screenplay"], second.id).text ==
             "Lena notices the forged signature."

    assert Fount.Query.node(new_candidate["screenplay"], third.id).text ==
             "The station clock keeps running."

    assert [["check", 1, 1]] =
             sql(
               repo,
               "SELECT stage,plan_version,policy_version FROM fount_run_steps WHERE id=$1::text::uuid",
               [rebased["check_step_id"]]
             )

    assert {:ok, %{"status" => "succeeded"}} =
             FountRun.step(repo, rebased["run_id"], context)

    assert [["succeeded", checked_candidate]] =
             sql(
               repo,
               "SELECT status,result->>'candidate_id' FROM fount_run_steps WHERE id=$1::text::uuid",
               [rebased["check_step_id"]]
             )

    assert checked_candidate == rebased["candidate_id"]

    assert {:ok, remaining} =
             FountRun.ExecutionStore.remaining_limits(repo, %{
               "run_id" => rebased["run_id"],
               "policy_version" => 1,
               "step_id" => rebased["check_step_id"]
             })

    assert remaining.max_inference_calls == 5

    assert [[5_000]] =
             sql(
               repo,
               "WITH RECURSIVE lineage AS (SELECT id,parent_run_id FROM fount_runs WHERE id=$1::text::uuid UNION ALL SELECT r.id,r.parent_run_id FROM fount_runs r JOIN lineage l ON r.id=l.parent_run_id) SELECT sum(settled_cost_microunits)::bigint FROM fount_run_usage WHERE run_id IN (SELECT id FROM lineage) AND currency='USD'",
               [rebased["run_id"]]
             )

    {:ok, fresh_packet} = FountWorkshop.Review.packet(repo, rebased["candidate_id"])
    assert fresh_packet["candidate_id"] == checked_candidate
    assert fresh_packet["base_revision_id"] == accepted_head.revision.id
    refute fresh_packet["content_hash"] == packet["content_hash"]

    assert {:error, _reason} =
             FountRun.approve_run(repo, run["id"], approval_response(old_approval), context)

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [root.id]
             )

    assert {:ok, head} = Persistence.load(repo, key)
    assert head.revision.id == accepted_head.revision.id
  end

  test "C06 saved approval payload resumes with the same approval identity and no callback replay",
       %{repo: repo} do
    {key, root} = seed_screenplay(repo, "payload-recovery")
    candidate = candidate_from_edit(repo, key, root, "Mara pockets the receipt.")
    {:ok, owner} = Principal.new(:human, "payload-owner")
    {:ok, service} = Principal.new(:service, "payload-service")

    {:ok, owner_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, service_context} =
      ActorContext.new(service, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "payload-run", completion: "accept", approver: service),
        owner_context
      )

    {:ok, calls} = Agent.start_link(fn -> 0 end)

    callback = fn _packet ->
      Agent.update(calls, &(&1 + 1))
      %{"recommendation" => "approve", "findings" => [], "overrides" => []}
    end

    fault = fn
      :after_approval_payload_persistence -> {:error, :payload_saved}
      _ -> :ok
    end

    assert {:error, {:fault, :after_approval_payload_persistence, :payload_saved}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback,
               fault_injector: fault
             )

    [[approval_id, "ready"]] =
      sql(
        repo,
        "SELECT approval_id::text,outcome FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid",
        [run["id"]]
      )

    assert is_binary(approval_id)
    assert Agent.get(calls, & &1) == 1

    assert {:ok, accepted} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback
             )

    assert accepted["approval_id"] == approval_id
    assert Agent.get(calls, & &1) == 1

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )
  end

  test "C07 CLI execution delegates to the same public start, control, show, and export paths", %{
    repo: repo
  } do
    {key, root} = seed_screenplay(repo, "cli-journey")
    {_owner, context} = owner_context(root.id, "cli-owner")
    candidate = candidate_from_edit(repo, key, root, "Mara folds the note twice.")
    temp = Path.join(System.tmp_dir!(), "fount-run-cli-#{ID.v4()}")
    artifact_root = Path.join(temp, "artifacts")
    input = Path.join(temp, "run.json")
    File.mkdir_p!(temp)
    File.write!(input, Jason.encode!(start_attrs(root, "cli-run")))
    on_exit(fn -> File.rm_rf(temp) end)

    runtime = [repo: Repo, actor_context: context, services: %{}, artifact_root: artifact_root]

    assert {0, %{"status" => "ok", "result" => run}} =
             FountRun.CLI.run(["start", "--input", input], runtime: runtime)

    assert {0, %{"result" => shown}} = FountRun.CLI.run(["show", run["id"]], runtime: runtime)
    assert shown["id"] == run["id"]

    assert {0, %{"result" => %{"run" => %{"status" => "paused"}}}} =
             FountRun.CLI.run(["pause", run["id"]], runtime: runtime)

    assert {0, %{"result" => %{"run" => resumed}}} =
             FountRun.CLI.run(["resume", run["id"]], runtime: runtime)

    refute resumed["status"] == "paused"

    assert {:ok, _} =
             FountRun.Control.mark_completion(repo, run["id"], candidate.id, "partial", context)

    assert {0, %{"result" => delivered}} =
             FountRun.CLI.run(["export", run["id"], "--destination", "cli-bundle"],
               runtime: runtime
             )

    assert delivered["manifest"]["candidate_id"] == candidate.id

    assert File.read!(Path.join([artifact_root, "cli-bundle", "screenplay.fountain"])) =~
             "Mara folds the note twice."
  end

  test "C06 saved automated review resumes without a second callback and reuses one approval identity",
       %{repo: repo} do
    {key, root} = seed_screenplay(repo, "review-recovery")
    candidate = candidate_from_edit(repo, key, root, "Mara shuts the window.")
    {:ok, owner} = Principal.new(:human, "recovery-owner")
    {:ok, service} = Principal.new(:service, "review-service")

    {:ok, owner_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, service_context} =
      ActorContext.new(service, owner, root.id, [:read_run, :manage_run], approvers: [service])

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "review-recovery-run", completion: "accept", approver: service),
        owner_context
      )

    {:ok, calls} = Agent.start_link(fn -> 0 end)

    callback = fn _packet ->
      Agent.update(calls, &(&1 + 1))
      %{"recommendation" => "approve", "findings" => [], "overrides" => []}
    end

    fault = fn
      :after_review_persistence -> {:error, :simulated_crash}
      _ -> :ok
    end

    assert {:error, {:fault, :after_review_persistence, :simulated_crash}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback,
               fault_injector: fault
             )

    assert Agent.get(calls, & &1) == 1

    assert {:ok, accepted} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               service_context,
               callback
             )

    assert Agent.get(calls, & &1) == 1
    assert accepted["status"] == "accepted"

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid",
               [run["id"]]
             )

    assert [["writer_edit", "service", service_id, run_id, 1]] =
             sql(
               repo,
               "SELECT origin,approver_type,approver_id,run_id::text,run_policy_version FROM acceptances WHERE approval_id=$1::text::uuid",
               [accepted["approval_id"]]
             )

    assert service_id == service.id
    assert run_id == run["id"]
  end

  test "C06 lost acknowledgement after acceptance commit replays the accepted attempt without callback",
       %{repo: repo} do
    {key, root} = seed_screenplay(repo, "ack-recovery")
    candidate = candidate_from_edit(repo, key, root, "Mara turns out the hall light.")
    {:ok, owner} = Principal.new(:human, "ack-owner")
    {:ok, agent} = Principal.new(:agent, "approval-agent")

    {:ok, owner_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run], approvers: [agent])

    {:ok, agent_context} =
      ActorContext.new(agent, owner, root.id, [:read_run, :manage_run], approvers: [agent])

    {:ok, run} =
      FountRun.start_run(
        repo,
        start_attrs(root, "ack-run", completion: "accept", approver: agent),
        owner_context
      )

    {:ok, unregistered_context} =
      ActorContext.new(owner, owner, root.id, [:read_run, :manage_run])

    assert {:error, :unregistered_approver} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               unregistered_context,
               agent_context,
               fn _ ->
                 flunk("unregistered callback must not dispatch")
               end
             )

    assert [[0]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_approval_attempts WHERE run_id=$1::text::uuid",
               [run["id"]]
             )

    {:ok, calls} = Agent.start_link(fn -> 0 end)

    callback = fn _packet ->
      Agent.update(calls, &(&1 + 1))
      %{"recommendation" => "approve", "findings" => [], "overrides" => []}
    end

    fault = fn
      :after_acceptance_commit -> {:error, :lost_ack}
      _ -> :ok
    end

    assert {:error, {:fault, :after_acceptance_commit, :lost_ack}} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               agent_context,
               callback,
               fault_injector: fault
             )

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )

    assert Agent.get(calls, & &1) == 1

    assert {:ok, replay} =
             ApprovalBridge.automated(
               repo,
               run,
               candidate.id,
               owner_context,
               agent_context,
               callback
             )

    assert replay["replay"] == true
    assert Agent.get(calls, & &1) == 1

    assert [["writer_edit", "agent", agent_id, run_id, 1]] =
             sql(
               repo,
               "SELECT origin,approver_type,approver_id,run_id::text,run_policy_version FROM acceptances WHERE approval_id=$1::text::uuid",
               [replay["approval_id"]]
             )

    assert agent_id == agent.id
    assert run_id == run["id"]

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [
                 root.id
               ]
             )
  end

  defp seed_screenplay(repo, suffix) do
    key = "phase05-#{suffix}-#{ID.v4()}"

    root =
      Screenplay.new(
        title: [{"Title", "Phase 05"}],
        body: [
          %{
            type: :scene,
            heading: "INT. ROOM - NIGHT",
            elements: [%{type: :action, text: "Mara waits."}]
          }
        ]
      )

    assert {:ok, ^root} = Persistence.create(repo, key, root)
    {key, root}
  end

  defp candidate_from_edit(repo, key, root, replacement) do
    action = Enum.find(root.ir.elements, &(&1.type == :action))

    {:ok, edited, changes} =
      Screenplay.apply(root, [
        %{
          "kind" => "replace_text",
          "target" => %{"kind" => "element", "id" => action.id},
          "value" => replacement
        }
      ])

    {:ok, candidate} =
      Persistence.save_edit_candidate(repo, key, edited,
        expected_revision: root.revision.id,
        operations: changes.operations
      )

    candidate
  end

  defp owner_context(screenplay_id, id) do
    {:ok, owner} = Principal.new(:human, id)
    {:ok, context} = ActorContext.new(owner, owner, screenplay_id, [:read_run, :manage_run])
    {owner, context}
  end

  defp start_attrs(root, key, opts \\ []) do
    completion = Keyword.get(opts, :completion, "candidate")
    approver = Keyword.get(opts, :approver)
    fallback_approver = Keyword.get(opts, :fallback_approver)

    %{
      "screenplay_id" => root.id,
      "base_revision_id" => root.revision.id,
      "goal" => "Complete the checked screenplay run",
      "scope" => %{"whole_screenplay" => true},
      "constraints" => [],
      "protected_material" => [],
      "client_idempotency_key" => key,
      "operation_parameters" => %{"workflow" => "develop"},
      "policy" => %{
        "gates" => %{
          "investigation_scope" => "automatic",
          "strategy_choice" => "human",
          "candidate_generation" => "automatic",
          "iteration" => "automatic"
        },
        "completion" => completion,
        "approver" => if(approver, do: Principal.to_map(approver), else: nil),
        "fallback_approver" =>
          if(fallback_approver, do: Principal.to_map(fallback_approver), else: nil),
        "route_choice" => %{"rule" => "pause_on_material_tradeoff"},
        "limits" => %{}
      }
    }
  end

  defp final_decision(repo, run, candidate, owner, context) do
    candidate_id = Map.get(candidate, :id) || Map.fetch!(candidate, "id")
    {:ok, packet} = FountWorkshop.Review.packet(repo, candidate_id)

    :ok =
      persist_succeeded_check(repo, run, candidate_id, packet["check_set_fingerprint"], context)

    attrs = %{
      "checkpoint_key" => "final-approval-test:#{candidate_id}",
      "kind" => "final_approval",
      "prompt" => "Approve exact candidate",
      "options" => [
        %{"id" => "approve", "label" => "Accept"},
        %{"id" => "reject", "label" => "Reject"},
        %{"id" => "replace", "label" => "Replace"}
      ],
      "step_id" => nil,
      "candidate_id" => candidate_id,
      "base_revision_id" => packet["base_revision_id"],
      "content_hash" => packet["content_hash"],
      "check_set_fingerprint" => packet["check_set_fingerprint"],
      "authorized_principal" => Principal.to_map(owner)
    }

    {:ok, decision} = FountRun.Persistence.put_pending_decision(repo, run["id"], attrs, context)
    decision
  end

  defp persist_succeeded_check(repo, run, candidate_id, fingerprint, context) do
    key = "phase05-test-check:#{candidate_id}:#{fingerprint}"

    {:ok, step} =
      FountRun.Persistence.create_step(
        repo,
        run["id"],
        %{
          "stage" => "check",
          "iteration" => run["iteration"] || 0,
          "branch_id" => "main",
          "input_revision_id" => run["plan"]["base_revision_id"],
          "input_candidate_id" => candidate_id,
          "request" => %{"kind" => "phase05_test"},
          "idempotency_key" => key
        },
        context
      )

    result = %{
      "candidate_id" => candidate_id,
      "check_set_fingerprint" => fingerprint,
      "checks" => [],
      "report_ids" => []
    }

    sql(
      repo,
      "UPDATE fount_run_steps SET status='succeeded',result=$2::jsonb,result_fingerprint=$3,completed_at=now(),updated_at=now() WHERE id=$1::text::uuid",
      [step["id"], result, sha256(Jason.encode!(result))]
    )

    :ok
  end

  defp approval_response(decision) do
    %{
      "decision_id" => decision["id"],
      "context_fingerprint" => decision["context_fingerprint"],
      "plan_version" => decision["plan_version"],
      "policy_version" => decision["policy_version"],
      "findings" => [],
      "overrides" => []
    }
  end

  defp restart_repo(prefix) do
    stop_supervised(Repo)

    start_supervised!(
      {Repo,
       url: System.fetch_env!("FOUNT_DATABASE_URL"),
       pool_size: 6,
       parameters: [search_path: prefix],
       migration_default_prefix: prefix}
    )
  end

  defp sql(repo, statement, params),
    do: SQL.query!(repo, statement, params, log: false).rows

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
