Code.require_file("../../fount_workshop/support/scripted_completion.ex", __DIR__)

defmodule FountRun.DurableExecutionIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Fount.{ID, Persistence, Screenplay}
  alias Fount.Writing.Principal
  alias FountRun.{ActorContext, ExecutionStore}
  alias FountWorkshop.TestSupport.ScriptedCompletion

  defmodule Repo do
    use Ecto.Repo, otp_app: :fount_run, adapter: Ecto.Adapters.Postgres
  end

  defmodule RaceRepoOne do
    use Ecto.Repo, otp_app: :fount_run, adapter: Ecto.Adapters.Postgres
  end

  defmodule RaceRepoTwo do
    use Ecto.Repo, otp_app: :fount_run, adapter: Ecto.Adapters.Postgres
  end

  setup do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    prefix = "phase03_#{String.replace(ID.v4(), "-", "")}"
    {:ok, admin} = Postgrex.start_link(Ecto.Repo.Supervisor.parse_url(url))
    Postgrex.query!(admin, ~s(CREATE SCHEMA "#{prefix}"), [])
    GenServer.stop(admin)

    on_exit(fn ->
      {:ok, cleanup} = Postgrex.start_link(Ecto.Repo.Supervisor.parse_url(url))
      Postgrex.query!(cleanup, ~s(DROP SCHEMA IF EXISTS "#{prefix}" CASCADE), [])
      GenServer.stop(cleanup)
    end)

    start_supervised!({Repo, url: url, pool_size: 4, parameters: [search_path: prefix]})
    Ecto.Migrator.run(Repo, Persistence.migrations_path(), :up, all: true)
    Ecto.Migrator.run(Repo, FountRun.migrations_path(), :up, all: true)

    %{repo: Repo, url: url, prefix: prefix}
  end

  test "W01 real Workshop operation saves session/candidate/usage without advancing canon", %{repo: repo} do
    %{run: run, context: context, root: root, request: request} = fixture_run(repo, "w01")
    {:ok, _step} = enqueue_write(repo, run, context, root, request)
    {client, script} = scripted_client(root)

    assert {:ok, %{"status" => "succeeded"}} =
             FountRun.step(repo, run["id"], context, inference: client, lease_ms: 5_000)

    assert [] = Agent.get(script, & &1)
    assert [[1]] = sql(repo, "SELECT count(*) FROM writing_sessions WHERE operation_key IS NOT NULL")
    assert [[1]] = sql(repo, "SELECT count(*) FROM writing_candidates WHERE operation_key IS NOT NULL")
    assert [[2]] = sql(repo, "SELECT count(*) FROM fount_run_provider_requests WHERE status='succeeded'")
    assert [[2]] = sql(repo, "SELECT count(*) FROM fount_run_usage WHERE resource='inference' AND reconciliation_state='settled'")
    assert {:ok, head} = Persistence.load(repo, "phase03-w01")
    assert head.revision.id == root.revision.id
  end

  test "W02 known provider success replays after crash while ambiguous paid response blocks replay", %{repo: repo} do
    %{run: run, context: context, root: root, request: request} = fixture_run(repo, "w02-known")
    {:ok, step} = enqueue_write(repo, run, context, root, request)
    {client, script} = scripted_client(root)

    crash_after_saved_response = fn
      :after_provider_response_persisted -> raise "phase03 injected crash"
      _ -> :ok
    end

    assert_raise RuntimeError, "phase03 injected crash", fn ->
      FountRun.step(repo, run["id"], context,
        inference: client,
        lease_ms: 1_000,
        fault_injector: crash_after_saved_response
      )
    end

    expire(repo, step["id"])
    assert {:ok, %{"status" => "succeeded"}} =
             FountRun.step(repo, run["id"], context, inference: client, lease_ms: 5_000)

    assert [] = Agent.get(script, & &1)
    assert [[2]] = sql(repo, "SELECT count(*) FROM fount_run_provider_requests")
    assert [[1]] = sql(repo, "SELECT count(*) FROM writing_candidates")

    %{run: unknown_run, context: unknown_context, root: unknown_root, request: unknown_request} =
      fixture_run(repo, "w02-unknown")

    {:ok, unknown_step} = enqueue_write(repo, unknown_run, unknown_context, unknown_root, unknown_request)
    {unknown_client, unknown_script} = scripted_client(unknown_root)

    crash_after_call = fn
      :after_provider_call_before_response_persist -> raise "provider response lost with process"
      _ -> :ok
    end

    assert_raise RuntimeError, "provider response lost with process", fn ->
      FountRun.step(repo, unknown_run["id"], unknown_context,
        inference: unknown_client,
        lease_ms: 1_000,
        fault_injector: crash_after_call
      )
    end

    expire(repo, unknown_step["id"])
    assert {:error, :ambiguous_provider_outcome} =
             FountRun.step(repo, unknown_run["id"], unknown_context,
               inference: unknown_client,
               lease_ms: 5_000
             )

    assert [_proposal_not_replayed] = Agent.get(unknown_script, & &1)
    assert [["unknown"]] = sql(repo, "SELECT status FROM fount_run_provider_requests WHERE run_id=$1::text::uuid", [unknown_run["id"]])
    assert [["reserved", nil]] = sql(repo, "SELECT reconciliation_state,settled_quantity FROM fount_run_usage WHERE run_id=$1::text::uuid AND resource='inference'", [unknown_run["id"]])
  end

  test "W03 competing claims serialize and stale fencing cannot heartbeat or persist domain output", %{repo: repo, url: url, prefix: prefix} do
    %{run: run, context: context, root: root, request: request} = fixture_run(repo, "w03")
    {:ok, _step} = enqueue_write(repo, run, context, root, request)

    for race_repo <- [RaceRepoOne, RaceRepoTwo] do
      start_supervised!({race_repo, url: url, pool_size: 1, parameters: [search_path: prefix]})
    end

    t1 = Task.async(fn -> ExecutionStore.claim(RaceRepoOne, run["id"], "worker-1", context, lease_ms: 1_000) end)
    t2 = Task.async(fn -> ExecutionStore.claim(RaceRepoTwo, run["id"], "worker-2", context, lease_ms: 1_000) end)
    results = [Task.await(t1), Task.await(t2)]
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :busy}, &1)) == 1
    {:ok, stale} = Enum.find(results, &match?({:ok, _}, &1))

    expire(repo, stale["step_id"])
    assert {:ok, fresh} = ExecutionStore.claim(repo, run["id"], "worker-3", context, lease_ms: 5_000)
    assert fresh["fencing_token"] > stale["fencing_token"]
    assert {:error, :stale_fencing_token} = ExecutionStore.heartbeat(repo, stale)
    assert {:error, :stale_fencing_token} = ExecutionStore.domain_guard(repo, stale, :candidate, ID.v4())
  end

  test "W04 reservations are idempotent, capped and retry counters persist", %{repo: repo} do
    %{run: run, context: context, root: root, request: request} = fixture_run(repo, "w04", %{"max_inference_calls" => 2, "max_measurement_states" => 2})
    {:ok, _step} = enqueue_write(repo, run, context, root, request)
    {:ok, claim} = ExecutionStore.claim(repo, run["id"], "budget-worker", context, lease_ms: 5_000)

    dispatch = %{request_sha256: String.duplicate("a", 64), mode: "json_text", dispatch_index: 1, transport_retry: 0, malformed_repair: false}
    assert {:ok, op} = ExecutionStore.provider_intent(repo, claim, dispatch)
    assert {:ok, ^op} = ExecutionStore.provider_intent(repo, claim, dispatch)
    assert {:ok, :ok} = ExecutionStore.provider_dispatched(repo, claim, op)
    assert {:ok, _} = ExecutionStore.provider_result(repo, op, %{"status" => "error", "category" => "timeout", "usage" => %{}})

    retry_dispatch = %{dispatch | request_sha256: String.duplicate("b", 64), dispatch_index: 2, transport_retry: 1, malformed_repair: true}
    assert {:ok, retry_op} = ExecutionStore.provider_intent(repo, claim, retry_dispatch)
    assert {:ok, :ok} = ExecutionStore.provider_dispatched(repo, claim, retry_op)
    assert [[2, 1, 1]] = sql(repo, "SELECT provider_dispatch_count,malformed_repair_count,transient_retry_count FROM fount_run_steps WHERE id=$1::text::uuid", [claim["step_id"]])

    extra = %{dispatch | request_sha256: String.duplicate("c", 64), dispatch_index: 3}
    assert {:error, {:budget_exhausted, "inference"}} = ExecutionStore.provider_intent(repo, claim, extra)
    assert {:ok, 2} = ExecutionStore.reserve_measurement(repo, claim, "measurement-op", 2)
    assert {:ok, 2} = ExecutionStore.reserve_measurement(repo, claim, "measurement-op", 2)
    assert {:error, {:budget_exhausted, "measurement_states"}} = ExecutionStore.reserve_measurement(repo, claim, "measurement-op-2", 1)
    assert [[2]] = sql(repo, "SELECT measurement_state_count FROM fount_run_steps WHERE id=$1::text::uuid", [claim["step_id"]])
  end

  test "W05 persisted control fences the owner before the next dispatch and progress redacts response bodies", %{repo: repo} do
    %{run: run, context: context, root: root, request: request} = fixture_run(repo, "w05")
    {:ok, _step} = enqueue_write(repo, run, context, root, request)
    {:ok, claim} = ExecutionStore.claim(repo, run["id"], "control-worker", context, lease_ms: 5_000)
    assert {:ok, :ok} = ExecutionStore.install_control_request(repo, run["id"], :pause, context)

    dispatch = %{request_sha256: String.duplicate("d", 64), mode: "json_text", dispatch_index: 1, transport_retry: 0, malformed_repair: false}
    assert {:error, :pause_requested} = ExecutionStore.provider_intent(repo, claim, dispatch)
    assert {:ok, progress} = FountRun.progress(repo, run["id"], context)
    assert progress["provider_requests"] == []
    refute inspect(progress) =~ "prompt"
  end

  test "W06 operation identities replay session/candidate once and stale domain writes are fenced", %{repo: repo} do
    %{run: run, context: context, root: root, request: request} = fixture_run(repo, "w06")
    {:ok, step} = enqueue_write(repo, run, context, root, request)
    {client, _script} = scripted_client(root)
    assert {:ok, %{"status" => "succeeded"}} = FountRun.step(repo, run["id"], context, inference: client, lease_ms: 5_000)
    assert [[1, 1]] = sql(repo, "SELECT (SELECT count(*) FROM writing_sessions),(SELECT count(*) FROM writing_candidates)")
    assert {:error, :no_work} = FountRun.step(repo, run["id"], context, inference: client, lease_ms: 5_000)
    assert [["succeeded"]] = sql(repo, "SELECT status FROM fount_run_steps WHERE id=$1::text::uuid", [step["id"]])
  end

  test "W07 unavailable stage handlers and services fail explicitly", %{repo: repo} do
    %{run: run, context: context, root: root, request: request} = fixture_run(repo, "w07-handler")
    {:ok, _} = FountRun.enqueue_step(repo, run["id"], %{"stage" => "intake", "idempotency_key" => "intake", "input_revision_id" => root.revision.id, "request" => %{}}, context)
    assert {:error, {:stage_handler_unavailable, "intake"}} = FountRun.step(repo, run["id"], context, lease_ms: 5_000)

    %{run: run2, context: context2, root: root2} = fixture_run(repo, "w07-service")
    {:ok, _} = enqueue_write(repo, run2, context2, root2, request_for(root2))
    assert {:error, :inference_unavailable} = FountRun.step(repo, run2["id"], context2, lease_ms: 5_000)
  end

  defp fixture_run(repo, suffix, limit_overrides \\ %{}) do
    root = Screenplay.new(title: [{"Title", "Phase 03 #{suffix}"}])
    key = "phase03-#{suffix}"
    assert {:ok, _} = Persistence.create(repo, key, root)
    {:ok, owner} = Principal.new(:human, "owner-#{suffix}")
    {:ok, context} = ActorContext.new(owner, owner, root.id, [:read_run, :manage_run])
    request = request_for(root)

    limits = Map.merge(%{"max_iterations" => 1, "max_malformed_repairs_per_call" => 1, "max_transient_retries" => 2, "max_inference_calls" => 12, "max_measurement_states" => 500, "money" => nil}, limit_overrides)

    attrs = %{
      "screenplay_id" => root.id,
      "base_revision_id" => root.revision.id,
      "goal" => "Create one reviewable opening candidate",
      "scope" => %{"whole_screenplay" => true},
      "constraints" => [],
      "protected_material" => [],
      "client_idempotency_key" => "run-#{suffix}",
      "operation_parameters" => %{"workflow" => "develop"},
      "policy" => %{
        "gates" => %{"investigation_scope" => "automatic", "strategy_choice" => "human", "candidate_generation" => "automatic", "iteration" => "automatic"},
        "completion" => "candidate",
        "approver" => nil,
        "fallback_approver" => nil,
        "route_choice" => %{"rule" => "pause_on_material_tradeoff"},
        "limits" => limits
      }
    }

    assert {:ok, run} = FountRun.start_run(repo, attrs, context)
    %{run: run, context: context, root: root, request: request}
  end

  defp enqueue_write(repo, run, context, root, request) do
    FountRun.enqueue_step(repo, run["id"], %{
      "stage" => "write",
      "iteration" => 0,
      "branch_id" => "main",
      "input_revision_id" => root.revision.id,
      "idempotency_key" => "write-main",
      "request" => request
    }, context)
  end

  defp request_for(root) do
    %{
      "version" => 1,
      "workflow" => "develop",
      "mode" => "draft",
      "base_revision_id" => root.revision.id,
      "instruction" => "Open on a visible choice under time pressure.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 1,
      "options" => %{"placement" => %{"kind" => "start"}}
    }
  end

  defp scripted_client(root) do
    {:ok, script} = Agent.start_link(fn -> [fn _ -> strategy_response() end, fn _ -> proposal(root) end] end)
    client = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])
    {client, script}
  end

  defp strategy_response do
    %{"strategies" => [%{
      "id" => "a",
      "title" => "Visible choice",
      "premise_of_change" => "Mara commits before she can explain herself",
      "dramatic_mechanism" => "A physical choice closes the easy exit",
      "entry_state" => "Hesitating",
      "exit_state" => "Committed",
      "beats" => ["The easy exit closes"],
      "preserves" => [], "changes" => [], "inventions" => [], "consequences" => [], "evidence_ids" => [], "open_questions" => []
    }]}
  end

  defp proposal(root) do
    %{
      "version" => 1,
      "base_revision_id" => root.revision.id,
      "strategy_id" => "a",
      "summary" => "Mara chooses the locked room.",
      "inventions" => [],
      "unresolved_questions" => [],
      "groups" => [%{
        "id" => "opening",
        "title" => "Opening",
        "reason" => "Play the choice",
        "depends_on" => [], "addresses_notes" => [], "evidence_ids" => [], "origin" => "generated_text",
        "operations" => [%{
          "kind" => "insert_scene",
          "value" => %{
            "after_scene_id" => nil,
            "scene" => %{
              "local_id" => "new:opening",
              "heading" => "INT. LOCKED ROOM - NIGHT",
              "elements" => [%{"local_id" => "new:action", "type" => "action", "text" => "Mara turns the deadbolt before the footsteps reach the hall.", "attrs" => %{}}]
            }
          }
        }]
      }]
    }
  end

  defp expire(repo, step_id) do
    SQL.query!(repo, "UPDATE fount_run_steps SET lease_expires_at=now()-interval '1 second' WHERE id=$1::text::uuid", [step_id], log: false)
  end

  defp sql(repo, statement, params \\ []) do
    SQL.query!(repo, statement, params, log: false).rows
  end
end
