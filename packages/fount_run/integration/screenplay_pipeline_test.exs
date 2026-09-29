Code.require_file("../../fount_workshop/support/scripted_completion.ex", __DIR__)

defmodule FountRun.ScreenplayPipelineIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Fount.{ID, Persistence, Query, Screenplay}
  alias Fount.Intelligence.Acquisition.CapabilityMeasurements
  alias Fount.Observe.Sandbox
  alias Fount.Writing.Principal
  alias FountRun.{ActorContext, PipelineRequest}
  alias FountWorkshop.Store
  alias FountWorkshop.TestSupport.ScriptedCompletion

  defmodule Repo do
    use Ecto.Repo, otp_app: :fount_run, adapter: Ecto.Adapters.Postgres
  end

  setup do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    prefix = "phase04_#{String.replace(ID.v4(), "-", "")}"
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
       url: url, pool_size: 4, parameters: [search_path: prefix], migration_default_prefix: prefix}
    )

    Ecto.Migrator.run(Repo, Persistence.migrations_path(), :up, all: true)
    Ecto.Migrator.run(Repo, FountRun.migrations_path(), :up, all: true)
    %{repo: Repo, prefix: prefix}
  end

  test "P01/P03 brief reaches the human route gate before pages, then saves checked pages without canon advance",
       %{repo: repo} do
    fixture = fixture_run(repo, "p01")

    {client, script} =
      scripted_client([
        investigation_plan(),
        investigation_explanation(),
        opening_proposal(fixture.root)
      ])

    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)

    assert {:ok, before_pages} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    decision = decision!(before_pages, "strategy")
    assert decision["status"] == "pending"
    assert length(decision["options"]) == 3
    assert [[0]] = sql(repo, "SELECT count(*) FROM writing_candidates")
    assert {:ok, head} = Persistence.load(repo, fixture.key)
    assert head.revision.id == fixture.root.revision.id

    response = decision_response(decision, "route-a")

    assert {:ok, first_submit} =
             FountRun.submit_decision(repo, decision["id"], response, fixture.context)

    assert first_submit["replay"] == false
    assert first_submit["choice"] == "route-a"

    assert {:ok, replay} =
             FountRun.submit_decision(repo, decision["id"], response, fixture.context)

    assert replay["replay"] == true
    assert replay["next_step_id"] == first_submit["next_step_id"]

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_decisions WHERE id=$1::text::uuid AND status='resolved'",
               [decision["id"]]
             )

    write_key = "strategy-decision:" <> decision["id"] <> ":write"

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_steps WHERE run_id=$1::text::uuid AND idempotency_key=$2",
               [fixture.run["id"], write_key]
             )

    competing = Map.put(response, "choice", "route-b")

    assert {:error, :decision_conflict} =
             FountRun.submit_decision(repo, decision["id"], competing, fixture.context)

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert [] = Agent.get(script, & &1)

    assert {:ok, progress} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    assert progress["run"]["status"] == "queued"
    assert progress["run"]["stage"] == "decide"
    refute Enum.any?(progress["decisions"], &(&1["kind"] == "candidate_review"))

    check = Enum.find(progress["steps"], &(&1["stage"] == "check"))
    assert check["result"]["candidate_id"]
    assert check["result"]["report_ids"] != []
    assert is_binary(check["result"]["check_set_fingerprint"])
    assert Enum.all?(check["result"]["checks"], &(&1["status"] == "pass"))
    assert check["result"]["changes_canon"] == false

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, completion_ready} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    assert completion_ready["run"]["status"] == "partial"
    assert completion_ready["run"]["stage"] == "deliver"

    assert {:ok, head_after} = Persistence.load(repo, fixture.key)
    assert head_after.revision.id == fixture.root.revision.id
  end

  test "P01 selected-scene dialogue pass changes only the authorized scene and remains a candidate",
       %{repo: repo} do
    root = dialogue_root()
    scene = hd(root.ir.scenes)
    dialogue = Enum.find(root.ir.elements, &(&1.type == :dialogue))

    request =
      request_for(root, "pass", %{"profile" => "dialogue_subtext"})
      |> Map.put("selection", %{"targets" => [%{"kind" => "scene", "id" => scene.id}]})
      |> Map.put(
        "instruction",
        "Sharpen Nora's selected-scene dialogue without changing the scene's action."
      )

    fixture = fixture_run(repo, "p01-dialogue", root: root, request: request)

    {client, script} =
      scripted_client([
        investigation_plan(),
        investigation_explanation(),
        dialogue_proposal(root, dialogue.id)
      ])

    decision = reach_strategy_gate(repo, fixture, client)

    assert {:ok, _} =
             FountRun.submit_decision(
               repo,
               decision["id"],
               decision_response(decision, "route-a"),
               fixture.context
             )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert [] = Agent.get(script, & &1)

    assert {:ok, progress} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    check = Enum.find(progress["steps"], &(&1["stage"] == "check"))
    {:ok, candidate} = Store.call(Store.new(repo), :candidate, [check["result"]["candidate_id"]])

    assert Query.node(candidate["screenplay"], dialogue.id).text ==
             "If you missed it, you were meant to."

    assert check["result"]["changes_canon"] == false
    assert {:ok, canonical} = Persistence.load(repo, fixture.key)
    assert canonical.revision.id == root.revision.id
  end

  test "P02/P04/P05 protected reveal failure schedules one durable repair that composes on canon and preserves lineage",
       %{repo: repo} do
    root = train_root()
    train_action = Enum.find(root.ir.elements, &(&1.type == :action))

    fixture =
      fixture_run(repo, "p02",
        root: root,
        protected_material: [%{"element_id" => train_action.id, "text" => train_action.text}],
        max_iterations: 1
      )

    responses = [
      investigation_plan(),
      investigation_explanation(),
      violating_reveal_proposal(root, train_action.id),
      repair_extraction_response(),
      repair_strategy_response(),
      repaired_reveal_proposal(root)
    ]

    {client, script} = scripted_client(responses)
    assert {:ok, _} = enqueue_intake(repo, fixture)

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)

    assert {:ok, at_gate} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    strategy = decision!(at_gate, "strategy")

    assert Enum.map(strategy["options"], & &1["id"]) |> Enum.sort() == [
             "route-a",
             "route-b",
             "route-c"
           ]

    strategy_step = Enum.find(at_gate["steps"], &(&1["stage"] == "plan"))

    assert "The antagonist's exact motive remains unstated." in strategy_step["result"][
             "uncertainty"
           ]

    assert [[0]] = sql(repo, "SELECT count(*) FROM writing_candidates")

    assert {:ok, _} =
             FountRun.submit_decision(
               repo,
               strategy["id"],
               decision_response(strategy, "route-a"),
               fixture.context
             )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)

    assert {:ok, after_first_check} = FountRun.progress(repo, fixture.run["id"], fixture.context)

    first_check =
      Enum.find(after_first_check["steps"], &(&1["stage"] == "check" and &1["iteration"] == 0))

    assert first_check["result"]["status"] == "repair_scheduled"

    assert Enum.any?(
             first_check["result"]["checks"],
             &(&1["kind"] == "protected_material" and &1["status"] == "fail")
           )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert [] = Agent.get(script, & &1)

    assert {:ok, progress} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    final_check = Enum.find(progress["steps"], &(&1["stage"] == "check" and &1["iteration"] == 1))
    final_id = final_check["result"]["candidate_id"]
    first_id = first_check["result"]["candidate_id"]

    store = Store.new(repo)
    assert {:ok, final_candidate} = Store.call(store, :candidate, [final_id])
    assert final_candidate["parent_candidate_id"] == first_id
    assert final_candidate["base_revision_id"] == root.revision.id
    assert Query.node(final_candidate["screenplay"], train_action.id).text == train_action.text

    assert {:ok, first_candidate} = Store.call(store, :candidate, [first_id])
    assert first_candidate["base_revision_id"] == root.revision.id
    assert [[0]] = sql(repo, "SELECT count(*) FROM writing_candidates WHERE decision='accepted'")

    first_diff = Screenplay.diff(root, first_candidate["screenplay"])
    final_diff = Screenplay.diff(root, final_candidate["screenplay"])
    assert train_action.id in first_diff.elements.changed
    refute train_action.id in final_diff.elements.changed
    assert length(final_diff.scenes.added) == 1
    assert length(final_diff.elements.added) > 0

    assert String.contains?(
             Screenplay.to_fountain(final_candidate["screenplay"], mode: :spec),
             "The stationmaster locks the evidence cabinet."
           )

    assert final_check["result"]["lineage"] != []
    assert final_check["result"]["report_ids"] != []
    assert Enum.all?(final_check["result"]["checks"], &(&1["status"] == "pass"))
    refute Enum.any?(progress["decisions"], &(&1["kind"] == "candidate_review"))
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, completion_ready} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    assert completion_ready["run"]["status"] == "partial"
    assert completion_ready["run"]["stage"] == "deliver"

    assert [[3, 0, 0]] =
             sql(
               repo,
               "SELECT provider_dispatch_count,malformed_repair_count,transient_retry_count FROM fount_run_steps WHERE run_id=$1::text::uuid AND stage='iterate'",
               [fixture.run["id"]]
             )

    assert {:ok, canonical} = Persistence.load(repo, fixture.key)
    assert canonical.revision.id == root.revision.id
  end

  test "P03 decision submission rejects wrong actor, stale context and stale run bindings", %{
    repo: repo
  } do
    wrong_fixture = fixture_run(repo, "p03-wrong")

    {wrong_client, wrong_script} =
      scripted_client([investigation_plan(), investigation_explanation()])

    decision = reach_strategy_gate(repo, wrong_fixture, wrong_client)
    assert [] = Agent.get(wrong_script, & &1)

    {:ok, intruder} = Principal.new(:human, "intruder")

    {:ok, wrong_context} =
      ActorContext.new(intruder, wrong_fixture.owner, wrong_fixture.root.id, [
        :read_run,
        :manage_run
      ])

    assert {:error, :unauthorized} =
             FountRun.submit_decision(
               repo,
               decision["id"],
               decision_response(decision, "route-a"),
               wrong_context
             )

    bad_context =
      decision
      |> decision_response("route-a")
      |> Map.put("context_fingerprint", String.duplicate("0", 64))

    assert {:error, :stale_decision_context} =
             FountRun.submit_decision(repo, decision["id"], bad_context, wrong_fixture.context)

    plan_fixture = fixture_run(repo, "p03-plan")
    {plan_client, _} = scripted_client([investigation_plan(), investigation_explanation()])
    plan_decision = reach_strategy_gate(repo, plan_fixture, plan_client)

    next_plan =
      Map.put(plan_fixture.attrs, "goal", "A deliberately changed goal")
      |> Map.delete("policy")
      |> Map.delete("client_idempotency_key")

    assert {:ok, _} =
             FountRun.Persistence.append_plan_snapshot(
               repo,
               plan_fixture.run["id"],
               next_plan,
               plan_fixture.context,
               expected_version: 1
             )

    assert {:error, :stale_decision} =
             FountRun.submit_decision(
               repo,
               plan_decision["id"],
               decision_response(plan_decision, "route-a"),
               plan_fixture.context
             )

    policy_fixture = fixture_run(repo, "p03-policy")
    {policy_client, _} = scripted_client([investigation_plan(), investigation_explanation()])
    policy_decision = reach_strategy_gate(repo, policy_fixture, policy_client)

    assert {:ok, _} =
             FountRun.Persistence.append_policy_snapshot(
               repo,
               policy_fixture.run["id"],
               policy_fixture.attrs["policy"],
               policy_fixture.context,
               expected_version: 1
             )

    assert {:error, :stale_decision} =
             FountRun.submit_decision(
               repo,
               policy_decision["id"],
               decision_response(policy_decision, "route-a"),
               policy_fixture.context
             )
  end

  test "P04/P06 unresolved repair stops at the configured cap and restart views reuse saved work",
       %{repo: repo, prefix: prefix} do
    root = train_root()
    train_action = Enum.find(root.ir.elements, &(&1.type == :action))

    fixture =
      fixture_run(repo, "p04-cap",
        root: root,
        protected_material: [%{"element_id" => train_action.id, "text" => train_action.text}],
        max_iterations: 1
      )

    responses = [
      investigation_plan(),
      investigation_explanation(),
      violating_reveal_proposal(root, train_action.id),
      repair_extraction_response(),
      repair_strategy_response(),
      violating_reveal_proposal(root, train_action.id) |> Map.put("strategy_id", "repair")
    ]

    {client, script} = scripted_client(responses)
    decision = reach_strategy_gate(repo, fixture, client)
    restart_repo(prefix)
    assert {:ok, progress_before} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    assert decision!(progress_before, "strategy")["id"] == decision["id"]

    assert [[2]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_provider_requests WHERE run_id=$1::text::uuid",
               [fixture.run["id"]]
             )

    response = decision_response(decision, "route-a")

    assert {:ok, submitted} =
             FountRun.submit_decision(repo, decision["id"], response, fixture.context)

    assert {:ok, replay} =
             FountRun.submit_decision(repo, decision["id"], response, fixture.context)

    assert replay["next_step_id"] == submitted["next_step_id"]

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_steps WHERE run_id=$1::text::uuid AND stage='write'",
               [fixture.run["id"]]
             )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    restart_repo(prefix)

    assert [[3]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_provider_requests WHERE run_id=$1::text::uuid",
               [fixture.run["id"]]
             )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert [] = Agent.get(script, & &1)

    assert {:ok, final} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    assert final["run"]["status"] == "partial"
    assert decision!(final, "iteration")["status"] == "pending"

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_steps WHERE run_id=$1::text::uuid AND stage='iterate'",
               [fixture.run["id"]]
             )

    assert [[6]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_provider_requests WHERE run_id=$1::text::uuid",
               [fixture.run["id"]]
             )
  end

  test "P07 all nine Workshop workflows remain registered alongside Phase 05 headless stages",
       %{repo: repo} do
    root = train_root()
    {root, character} = Screenplay.add_character(root, "NORA")
    action = Enum.find(root.ir.elements, &(&1.type == :action))
    scene = hd(root.ir.scenes)

    requests = [
      request_for(root, "develop", %{"placement" => %{"kind" => "start"}}),
      request_for(root, "alternatives", %{}),
      request_for(root, "propagate", %{"change" => "The secret becomes public."}),
      request_for(root, "sequence", %{"target_scene_count" => 2}),
      request_for(root, "character", %{
        "character_id" => character.id,
        "direction" => "Make Nora choose first."
      }),
      request_for(root, "notes", %{"note_ids" => [], "external_notes" => []}),
      request_for(root, "pass", %{"profile" => "dialogue_subtext"}),
      request_for(root, "recover", %{
        "source_revision_id" => root.revision.id,
        "source_screenplay_id" => root.id,
        "source_targets" => [%{"kind" => "element", "id" => action.id}],
        "destination" => %{"kind" => "after_scene", "after_scene_id" => scene.id}
      }),
      request_for(root, "investigate", %{
        "concern" => "What makes the reveal costly?",
        "write_fixes" => false
      })
    ]

    for request <- requests do
      assert {:ok, _} = FountWorkshop.Request.validate(root, request)
    end

    assert {:ok, _} = PipelineRequest.new(hd(requests))
    assert {:ok, registry} = FountRun.StageRegistry.new()

    assert {:ok, FountRun.CompletionHandler} =
             FountRun.StageRegistry.fetch(registry, "decide")

    assert {:ok, FountRun.DeliveryHandler} =
             FountRun.StageRegistry.fetch(registry, "deliver")

    refute function_exported?(FountRun, :approve, 4)
    assert function_exported?(FountRun, :approve_run, 4)
    assert function_exported?(FountRun, :deliver, 5)
    assert [[0]] = sql(repo, "SELECT count(*) FROM fount_run_deliveries")
  end

  test "R01-R05 trusted Observe survives Run, prewrite lineage reaches plan, and selected write reuses it",
       %{repo: repo} do
    root = dialogue_root()
    dialogue = Enum.find(root.ir.elements, &(&1.type == :dialogue))
    request = request_for(root, "develop", %{"placement" => %{"kind" => "start"}})
    fixture = fixture_run(repo, "r01-r05", root: root, request: request)
    credential_canary = "phase01-provider-secret-#{Fount.ID.v4()}"
    observe = observe_provider(root, credential_canary)

    {client, script} =
      scripted_client([
        investigation_plan(),
        investigation_explanation(),
        dialogue_proposal(root, dialogue.id)
      ])

    assert {:ok, _} = enqueue_intake(repo, fixture)

    assert {:ok, %{"status" => "succeeded"}} =
             FountRun.step(repo, fixture.run["id"], %{
               actor_context: fixture.context,
               observe: observe,
               lease_ms: 5_000
             })

    assert {:ok, worker} =
             FountRun.Worker.init(
               repo: repo,
               run_id: fixture.run["id"],
               context: fixture.context,
               interval_ms: 60_000,
               step_opts: [inference: client, observe: observe, lease_ms: 5_000]
             )

    assert {:noreply, ^worker} = FountRun.Worker.handle_info(:poll, worker)
    assert_receive :poll

    assert {:ok, after_investigate} =
             FountRun.progress(repo, fixture.run["id"], fixture.context)

    investigate_step = Enum.find(after_investigate["steps"], &(&1["stage"] == "investigate"))
    investigate_session_id = investigate_step["result"]["session_id"]
    store = Store.new(repo)
    assert {:ok, investigate_session} = Store.call(store, :session, [investigate_session_id])

    writer_packet =
      get_in(investigate_session, [
        "progress",
        "preparation",
        "context",
        "data",
        "writer_intelligence"
      ])

    assert writer_packet["status"] in ["complete", "partial"]
    refute writer_packet["reason"] == "observe_provider_not_configured"
    assert is_binary(writer_packet["id"])

    investigate_limits = investigate_session["provenance"]["limits"]
    assert investigate_limits["durable_analysis"] == true
    assert is_binary(investigate_limits["analysis_privacy_namespace"])

    assert String.starts_with?(
             investigate_limits["analysis_privacy_namespace"],
             "fount-run:screenplay:"
           )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, at_gate} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    plan_step = Enum.find(at_gate["steps"], &(&1["stage"] == "plan"))
    assert {:ok, plan_session} = Store.call(store, :session, [plan_step["result"]["session_id"]])

    plan_packet =
      get_in(plan_session, ["progress", "preparation", "context", "data", "writer_intelligence"])

    assert plan_packet["id"] == writer_packet["id"]

    assert get_in(plan_session, [
             "progress",
             "preparation",
             "context",
             "data",
             "intelligence_preflight"
           ]) ==
             get_in(investigate_session, [
               "progress",
               "preparation",
               "context",
               "data",
               "intelligence_preflight"
             ])

    assert (investigate_session["progress"]["report_ids"] || []) != []

    assert Enum.all?(
             investigate_session["progress"]["report_ids"],
             &(&1 in plan_session["progress"]["report_ids"])
           )

    assert plan_session["provenance"]["limits"]["durable_analysis"] == true

    assert plan_session["provenance"]["limits"]["analysis_privacy_namespace"] ==
             investigate_limits["analysis_privacy_namespace"]

    assert Enum.all?(plan_step["result"]["strategies"], fn strategy ->
             get_in(strategy, ["intelligence_lineage", "packet_id"]) == writer_packet["id"]
           end)

    strategy = decision!(at_gate, "strategy")

    assert {:ok, _} =
             FountRun.submit_decision(
               repo,
               strategy["id"],
               decision_response(strategy, "route-a"),
               fixture.context
             )

    # The selected-route write starts from the plan session. Its saved durable-analysis
    # options are restored by Session.resume/3 while Observe is supplied as a trusted service.
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, after_write} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    write_step = Enum.find(after_write["steps"], &(&1["stage"] == "write"))
    candidate_id = write_step["result"]["candidate_id"]
    assert {:ok, candidate} = Store.call(store, :candidate, [candidate_id])

    revision_packet = get_in(candidate, ["provenance", "revision_intelligence"])
    assert revision_packet["status"] in ["complete", "partial"], inspect(revision_packet)

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM analysis_runs WHERE candidate_id=$1::text::uuid AND playbook='revision_regression' AND status IN ('complete','partial')",
               [candidate_id]
             )

    assert get_in(candidate, ["provenance", "intelligence_lineage", "pre_analysis_packet", "id"]) ==
             writer_packet["id"]

    revision_checks =
      candidate["provenance"]["checks"]
      |> Enum.filter(&(&1["kind"] == "revision_intelligence"))

    assert revision_checks != []
    assert Enum.all?(revision_checks, &(&1["severity"] == "advisory"))

    assert get_in(candidate, ["provenance", "resource_usage", "pre_analysis"]) ==
             writer_packet["resource_usage"]

    assert [[0]] =
             sql(
               repo,
               """
               SELECT count(*) FROM fount_run_steps
               WHERE run_id=$1::text::uuid
                 AND (request::text LIKE $2 OR result::text LIKE $2)
               """,
               [fixture.run["id"], "%#{credential_canary}%"]
             )

    assert [[0]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_plans WHERE run_id=$1::text::uuid AND row_to_json(fount_run_plans)::text LIKE $2",
               [fixture.run["id"], "%#{credential_canary}%"]
             )

    assert [[0]] =
             sql(
               repo,
               """
               SELECT count(*) FROM writing_sessions
               WHERE screenplay_id=$1::text::uuid
                 AND (request::text LIKE $2 OR strategies::text LIKE $2 OR progress::text LIKE $2 OR provenance::text LIKE $2)
               """,
               [root.id, "%#{credential_canary}%"]
             )

    assert [[0]] =
             sql(
               repo,
               """
               SELECT count(*) FROM writing_candidates
               WHERE screenplay_id=$1::text::uuid AND provenance::text LIKE $2
               """,
               [root.id, "%#{credential_canary}%"]
             )

    # Run check is intentionally non-generative: it consumes the candidate's inherited
    # advisory checks even when Observe is not supplied for the check step.
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, after_check} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    check_step = Enum.find(after_check["steps"], &(&1["stage"] == "check"))

    assert Enum.filter(check_step["result"]["checks"], &(&1["kind"] == "revision_intelligence")) ==
             revision_checks

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM analysis_runs WHERE candidate_id=$1::text::uuid AND playbook='revision_regression'",
               [candidate_id]
             )

    assert [] = Agent.get(script, & &1)

    other = fixture_run(repo, "r01-unknown")
    assert {:ok, _} = enqueue_intake(repo, other)

    assert {:error, :invalid_service_key} =
             FountRun.step(repo, other.run["id"], %{
               actor_context: other.context,
               observe: observe,
               unsupported_service: :reject_me
             })
  end

  test "R05 iterate child receives Observe and revision intelligence without changing canon",
       %{repo: repo} do
    root = train_root()
    action = Enum.find(root.ir.elements, &(&1.type == :action))
    dialogue = Enum.find(root.ir.elements, &(&1.type == :dialogue))

    fixture =
      fixture_run(repo, "r05-iterate",
        root: root,
        protected_material: [%{"element_id" => action.id, "text" => action.text}],
        max_iterations: 1
      )

    observe = observe_provider(root)

    {client, script} =
      scripted_client([
        investigation_plan(),
        investigation_explanation(),
        violating_text_proposal(root, action.id),
        repair_extraction_response(),
        repair_strategy_response(),
        repaired_dialogue_proposal(root, dialogue.id)
      ])

    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, at_gate} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    strategy = decision!(at_gate, "strategy")

    assert {:ok, _} =
             FountRun.submit_decision(
               repo,
               strategy["id"],
               decision_response(strategy, "route-a"),
               fixture.context
             )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)

    assert {:ok, after_first_check} =
             FountRun.progress(repo, fixture.run["id"], fixture.context)

    first_check =
      Enum.find(after_first_check["steps"], &(&1["stage"] == "check" and &1["iteration"] == 0))

    assert first_check["result"]["status"] == "repair_scheduled"

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, after_iterate} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    iterate_step = Enum.find(after_iterate["steps"], &(&1["stage"] == "iterate"))
    child_id = iterate_step["result"]["candidate_id"]

    assert {:ok, child} = Store.call(Store.new(repo), :candidate, [child_id])
    assert child["parent_candidate_id"] == first_check["result"]["candidate_id"]
    assert Query.node(child["screenplay"], action.id).text == action.text

    revision_packet = get_in(child, ["provenance", "revision_intelligence"])
    assert revision_packet["status"] in ["complete", "partial"], inspect(revision_packet)

    assert Enum.any?(
             child["provenance"]["checks"],
             &(&1["kind"] == "revision_intelligence" and &1["severity"] == "advisory")
           )

    assert get_in(child, ["provenance", "intelligence_lineage", "pre_analysis_packet", "status"]) in [
             "complete",
             "partial"
           ]

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert [] = Agent.get(script, & &1)
    assert {:ok, canonical} = Persistence.load(repo, fixture.key)
    assert canonical.revision.id == root.revision.id
  end

  test "R06 no-Observe compatibility keeps analysis explicitly not_run", %{repo: repo} do
    root = dialogue_root()
    dialogue = Enum.find(root.ir.elements, &(&1.type == :dialogue))
    fixture = fixture_run(repo, "r06", root: root)

    {client, script} =
      scripted_client([
        investigation_plan(),
        investigation_explanation(),
        dialogue_proposal(root, dialogue.id)
      ])

    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)

    assert {:ok, after_investigate} =
             FountRun.progress(repo, fixture.run["id"], fixture.context)

    investigate_step = Enum.find(after_investigate["steps"], &(&1["stage"] == "investigate"))

    assert {:ok, investigate_session} =
             Store.call(Store.new(repo), :session, [investigate_step["result"]["session_id"]])

    writer_packet =
      get_in(investigate_session, [
        "progress",
        "preparation",
        "context",
        "data",
        "writer_intelligence"
      ])

    assert writer_packet["status"] == "not_run"
    assert writer_packet["reason"] == "observe_provider_not_configured"
    assert investigate_session["provenance"]["limits"]["durable_analysis"] == false

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, at_gate} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    strategy = decision!(at_gate, "strategy")

    assert {:ok, _} =
             FountRun.submit_decision(
               repo,
               strategy["id"],
               decision_response(strategy, "route-a"),
               fixture.context
             )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, after_write} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    write_step = Enum.find(after_write["steps"], &(&1["stage"] == "write"))

    assert {:ok, candidate} =
             Store.call(Store.new(repo), :candidate, [write_step["result"]["candidate_id"]])

    assert get_in(candidate, ["provenance", "revision_intelligence", "status"]) == "not_run"

    assert get_in(candidate, ["provenance", "revision_intelligence", "reason"]) ==
             "observe_provider_not_configured"

    refute Enum.any?(candidate["provenance"]["checks"], fn check ->
             check["kind"] == "revision_intelligence" and check["status"] == "pass"
           end)

    assert [] = Agent.get(script, & &1)
  end

  test "D01/D02/D04 Observe work consumes Run measurement budget and exposes persisted analysis identity",
       %{repo: repo} do
    root = dialogue_root()
    fixture = fixture_run(repo, "d01-d02-d04", root: root, max_measurement_states: 500)
    observe = observe_provider(root)
    {client, script} = scripted_client([investigation_plan(), investigation_explanation()])

    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert [] = Agent.get(script, & &1)

    assert {:ok, progress} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    investigate = Enum.find(progress["steps"], &(&1["stage"] == "investigate"))
    analysis = investigate["result"]["analysis"]["writer"]

    assert is_binary(analysis["packet_id"])
    assert is_binary(analysis["analysis_run_id"])
    assert analysis["status"] in ["complete", "partial"]
    assert analysis["resources"]["scheduled_states"] > 0

    measurement = progress["resources"]["measurement_states"]
    assert measurement["consumed"] > 0
    assert measurement["remaining"] == measurement["limit"] - measurement["consumed"]
    refute measurement["exhausted"]

    assert Enum.any?(progress["analysis"], fn item ->
             item["step_id"] == investigate["id"] and
               item["session_id"] == investigate["result"]["session_id"] and
               get_in(item, ["writer", "packet_id"]) == analysis["packet_id"] and
               get_in(item, ["writer", "analysis_run_id"]) == analysis["analysis_run_id"]
           end)

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM analysis_runs WHERE id=$1::text::uuid AND session_id=$2::text::uuid",
               [analysis["analysis_run_id"], investigate["result"]["session_id"]]
             )

    assert [[observations]] =
             sql(
               repo,
               "SELECT count(*) FROM analysis_observations WHERE analysis_run_id=$1::text::uuid",
               [analysis["analysis_run_id"]]
             )

    assert observations > 0
    assert [[cache_rows]] = sql(repo, "SELECT count(*) FROM analysis_measurement_results")
    assert cache_rows > 0

    exhausted_root = dialogue_root()

    exhausted =
      fixture_run(repo, "d01-exhausted",
        root: exhausted_root,
        max_measurement_states: 0
      )

    exhausted_observe = observe_provider(exhausted_root)

    {exhausted_client, exhausted_script} =
      scripted_client([investigation_plan(), investigation_explanation()])

    assert {:ok, _} = enqueue_intake(repo, exhausted)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, exhausted, nil)

    assert {:ok, %{"status" => "succeeded"}} =
             run_step(repo, exhausted, exhausted_client, exhausted_observe)

    assert [] = Agent.get(exhausted_script, & &1)
    assert {:ok, exhausted_progress} = FountRun.progress(repo, exhausted.run["id"], exhausted.context)
    exhausted_step = Enum.find(exhausted_progress["steps"], &(&1["stage"] == "investigate"))

    assert exhausted_progress["resources"]["measurement_states"] == %{
             "limit" => 0,
             "consumed" => 0,
             "remaining" => 0,
             "exhausted" => true
           }

    assert exhausted_step["result"]["analysis"]["writer"]["status"] in ["partial", "failed"]
    refute exhausted_step["result"]["analysis"]["writer"]["status"] == "complete"

    packet = writer_packet(repo, exhausted_step)
    assert Enum.any?(packet["errors"] || [], &(&1["class"] == "budget_exhausted"))
    assert get_in(packet, [
             "resource_usage",
             "capability_runs",
             Access.at(0),
             "actual",
             "scheduled_states"
           ]) == 0
  end

  test "D03 durable Sandbox cache reuses equivalent work and changed semantic context misses",
       %{repo: repo} do
    root = dialogue_root()

    first = fixture_run(repo, "d03-first", root: root)
    {first_client, first_script} = scripted_client([investigation_plan(), investigation_explanation()])
    first_step = run_investigation(repo, first, first_client, observe_provider(root))
    assert [] = Agent.get(first_script, & &1)
    first_summary = first_step["result"]["analysis"]["writer"]
    assert first_summary["resources"]["scheduled_states"] > 0
    assert (first_summary["resources"]["cache_hits"] || 0) == 0

    assert [[cache_rows_before, access_before]] =
             sql(
               repo,
               "SELECT count(*),COALESCE(sum(access_count),0)::bigint FROM analysis_measurement_results"
             )

    assert [[observations_before]] = sql(repo, "SELECT count(*) FROM analysis_observations")

    second =
      fixture_run(repo, "d03-second",
        root: root,
        request: first.request,
        persist: false,
        key: first.key
      )

    {second_client, second_script} =
      scripted_client([investigation_plan(), investigation_explanation()])

    second_step = run_investigation(repo, second, second_client, observe_provider(root))
    assert [] = Agent.get(second_script, & &1)
    second_summary = second_step["result"]["analysis"]["writer"]

    assert second_summary["resources"]["scheduled_states"] == 0
    assert second_summary["resources"]["cache_hits"] > 0
    assert {:ok, second_progress} = FountRun.progress(repo, second.run["id"], second.context)
    assert second_progress["resources"]["measurement_states"]["consumed"] == 0

    assert [[^cache_rows_before, access_after]] =
             sql(
               repo,
               "SELECT count(*),COALESCE(sum(access_count),0)::bigint FROM analysis_measurement_results"
             )

    assert access_after > access_before
    assert [[^observations_before]] = sql(repo, "SELECT count(*) FROM analysis_observations")

    changed =
      fixture_run(repo, "d03-changed",
        root: root,
        request: first.request,
        goal: "Inspect a deliberately changed semantic concern for the same selected pages",
        persist: false,
        key: first.key
      )

    {changed_client, changed_script} =
      scripted_client([investigation_plan(), investigation_explanation()])

    changed_step = run_investigation(repo, changed, changed_client, observe_provider(root))
    assert [] = Agent.get(changed_script, & &1)
    changed_summary = changed_step["result"]["analysis"]["writer"]

    assert changed_summary["resources"]["scheduled_states"] > 0
    assert (changed_summary["resources"]["cache_hits"] || 0) == 0
    assert {:ok, changed_progress} = FountRun.progress(repo, changed.run["id"], changed.context)
    assert changed_progress["resources"]["measurement_states"]["consumed"] > 0

    assert [[cache_rows_after]] = sql(repo, "SELECT count(*) FROM analysis_measurement_results")
    assert cache_rows_after > cache_rows_before
  end

  test "D05 pre-analysis crash replays one logical session without resetting measurement usage",
       %{repo: repo} do
    root = dialogue_root()
    fixture = fixture_run(repo, "d05-pre-analysis", root: root)
    observe = observe_provider(root)
    {client, script} = scripted_client([investigation_plan(), investigation_explanation()])

    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)

    {pid, ref} =
      spawn_monitor(fn ->
        FountRun.step(repo, fixture.run["id"], fixture.context,
          inference: client,
          observe: observe,
          lease_ms: 5_000,
          fault_injector: fn
            :after_pre_analysis_persisted -> exit(:phase02_pre_analysis_crash)
            _ -> :ok
          end
        )
      end)

    assert_receive {:DOWN, ^ref, :process, ^pid, :phase02_pre_analysis_crash}, 5_000
    assert [] = Agent.get(script, & &1)

    assert [[session_count_before]] =
             sql(
               repo,
               "SELECT count(*) FROM writing_sessions WHERE screenplay_id=$1::text::uuid AND workflow='investigate'",
               [root.id]
             )

    assert session_count_before == 1
    assert {:ok, crashed_progress} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    consumed_before = crashed_progress["resources"]["measurement_states"]["consumed"]
    assert consumed_before > 0

    expire_active_lease(repo, fixture.run["id"])
    {retry_client, retry_script} = scripted_client([])

    assert {:ok, %{"status" => "succeeded"}} =
             run_step(repo, fixture, retry_client, observe)

    assert [] = Agent.get(retry_script, & &1)
    assert {:ok, recovered} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    investigate = Enum.find(recovered["steps"], &(&1["stage"] == "investigate"))

    assert recovered["resources"]["measurement_states"]["consumed"] == consumed_before
    assert investigate["status"] == "succeeded"

    assert [[2]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_attempts WHERE step_id=$1::text::uuid",
               [investigate["id"]]
             )

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM writing_sessions WHERE screenplay_id=$1::text::uuid AND workflow='investigate'",
               [root.id]
             )

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM analysis_runs WHERE session_id=$1::text::uuid",
               [investigate["result"]["session_id"]]
             )
  end

  test "D05 candidate crash preserves one candidate and a policy-fenced analysis cannot attach",
       %{repo: repo} do
    root = dialogue_root()
    dialogue = Enum.find(root.ir.elements, &(&1.type == :dialogue))
    fixture = fixture_run(repo, "d05-candidate", root: root)
    observe = observe_provider(root)

    {client, script} =
      scripted_client([
        investigation_plan(),
        investigation_explanation(),
        dialogue_proposal(root, dialogue.id)
      ])

    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, at_gate} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    strategy = decision!(at_gate, "strategy")

    assert {:ok, _} =
             FountRun.submit_decision(
               repo,
               strategy["id"],
               decision_response(strategy, "route-a"),
               fixture.context
             )

    {pid, ref} =
      spawn_monitor(fn ->
        FountRun.step(repo, fixture.run["id"], fixture.context,
          inference: client,
          observe: observe,
          lease_ms: 5_000,
          fault_injector: fn
            :after_candidate_persisted -> exit(:phase02_candidate_crash)
            _ -> :ok
          end
        )
      end)

    assert_receive {:DOWN, ^ref, :process, ^pid, :phase02_candidate_crash}, 5_000
    assert [] = Agent.get(script, & &1)
    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM writing_candidates WHERE screenplay_id=$1::text::uuid",
               [root.id]
             )

    assert [[candidate_id_before]] =
             sql(
               repo,
               "SELECT id::text FROM writing_candidates WHERE screenplay_id=$1::text::uuid",
               [root.id]
             )

    expire_active_lease(repo, fixture.run["id"])
    {retry_client, retry_script} = scripted_client([])

    assert {:ok, %{"status" => "succeeded"}} =
             run_step(repo, fixture, retry_client, observe)

    assert [] = Agent.get(retry_script, & &1)
    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM writing_candidates WHERE screenplay_id=$1::text::uuid",
               [root.id]
             )

    assert [[^candidate_id_before]] =
             sql(
               repo,
               "SELECT id::text FROM writing_candidates WHERE screenplay_id=$1::text::uuid",
               [root.id]
             )

    assert {:ok, recovered} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    write_step = Enum.find(recovered["steps"], &(&1["stage"] == "write"))
    assert write_step["result"]["candidate_id"] == candidate_id_before
    assert is_binary(get_in(write_step, ["result", "analysis", "revision", "analysis_run_id"]))

    fenced_root = dialogue_root()
    fenced = fixture_run(repo, "d05-fenced", root: fenced_root)
    fenced_observe = observe_provider(fenced_root)
    {fenced_client, fenced_script} = scripted_client([investigation_plan(), investigation_explanation()])

    assert {:ok, _} = enqueue_intake(repo, fenced)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fenced, nil)

    policy = fenced.attrs["policy"]
    changed_policy = put_in(policy, ["limits", "max_measurement_states"], 499)

    assert {:error, :policy_invalidated} =
             FountRun.step(repo, fenced.run["id"], fenced.context,
               inference: fenced_client,
               observe: fenced_observe,
               lease_ms: 5_000,
               fault_injector: fn
                 :after_pre_analysis_persisted ->
                   assert {:ok, _} =
                            FountRun.update_policy(
                              repo,
                              fenced.run["id"],
                              changed_policy,
                              fenced.context,
                              expected_version: 1,
                              command_id: "phase02-fence-policy"
                            )

                   :ok

                 _ ->
                   :ok
               end
             )

    assert [] = Agent.get(fenced_script, & &1)
    assert {:ok, fenced_progress} = FountRun.progress(repo, fenced.run["id"], fenced.context)
    stale = Enum.find(fenced_progress["steps"], &(&1["stage"] == "investigate"))
    assert is_nil(stale["session_id"])
    assert is_nil(stale["result"])
    assert fenced_progress["run"]["current_policy_version"] == 2
  end

  test "D06 partial Revision Intelligence stays visible and check does not rerun semantics",
       %{repo: repo} do
    root = dialogue_root()
    dialogue = Enum.find(root.ir.elements, &(&1.type == :dialogue))
    fixture = fixture_run(repo, "d06-partial", root: root)
    observe = prewrite_only_observe_provider(root)

    {client, script} =
      scripted_client([
        investigation_plan(),
        investigation_explanation(),
        dialogue_proposal(root, dialogue.id)
      ])

    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, at_gate} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    strategy = decision!(at_gate, "strategy")

    assert {:ok, _} =
             FountRun.submit_decision(
               repo,
               strategy["id"],
               decision_response(strategy, "route-a"),
               fixture.context
             )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert [] = Agent.get(script, & &1)
    assert {:ok, before_check} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    write = Enum.find(before_check["steps"], &(&1["stage"] == "write"))
    revision = write["result"]["analysis"]["revision"]

    assert revision["status"] in ["partial", "failed"]
    refute revision["status"] == "complete"
    consumed_before = before_check["resources"]["measurement_states"]["consumed"]

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, after_check} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    check = Enum.find(after_check["steps"], &(&1["stage"] == "check"))

    assert get_in(check, ["result", "analysis", "revision", "status"]) == revision["status"]
    assert get_in(check, ["result", "analysis", "revision", "analysis_run_id"]) ==
             revision["analysis_run_id"]

    assert after_check["resources"]["measurement_states"]["consumed"] == consumed_before

    refute Enum.any?(check["result"]["checks"], fn item ->
             item["kind"] == "revision_intelligence" and item["status"] == "pass"
           end)

    assert Enum.any?(check["result"]["checks"], fn item ->
             item["kind"] == "scope" and item["severity"] == "required" and
               item["status"] == "pass"
           end)
  end

  test "D06/D07 layered check reuses revision evidence and iterate remeasures the child once",
       %{repo: repo} do
    root = train_root()
    action = Enum.find(root.ir.elements, &(&1.type == :action))
    dialogue = Enum.find(root.ir.elements, &(&1.type == :dialogue))

    fixture =
      fixture_run(repo, "d06-d07",
        root: root,
        protected_material: [%{"element_id" => action.id, "text" => action.text}],
        max_iterations: 1
      )

    observe = observe_provider(root)

    {client, script} =
      scripted_client([
        investigation_plan(),
        investigation_explanation(),
        violating_text_proposal(root, action.id),
        repair_extraction_response(),
        repair_strategy_response(),
        repaired_dialogue_proposal(root, dialogue.id)
      ])

    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, at_gate} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    strategy = decision!(at_gate, "strategy")

    assert {:ok, _} =
             FountRun.submit_decision(
               repo,
               strategy["id"],
               decision_response(strategy, "route-a"),
               fixture.context
             )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, before_check} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    write = Enum.find(before_check["steps"], &(&1["stage"] == "write"))
    revision_run_id = get_in(write, ["result", "analysis", "revision", "analysis_run_id"])
    measurement_before_check = before_check["resources"]["measurement_states"]["consumed"]

    assert is_binary(revision_run_id)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, after_check} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    first_check = Enum.find(after_check["steps"], &(&1["stage"] == "check" and &1["iteration"] == 0))

    assert after_check["resources"]["measurement_states"]["consumed"] == measurement_before_check
    assert get_in(first_check, ["result", "analysis", "revision", "analysis_run_id"]) == revision_run_id

    assert Enum.any?(first_check["result"]["checks"], fn check ->
             check["kind"] == "revision_intelligence" and check["severity"] == "advisory"
           end)

    assert Enum.any?(first_check["result"]["checks"], fn check ->
             check["kind"] == "protected_material" and check["severity"] == "required" and
               check["status"] == "fail"
           end)

    assert first_check["result"]["status"] == "repair_scheduled"
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, after_iterate} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    iterate = Enum.find(after_iterate["steps"], &(&1["stage"] == "iterate"))
    child_id = iterate["result"]["candidate_id"]
    child_revision_run_id = get_in(iterate, ["result", "analysis", "revision", "analysis_run_id"])

    assert is_binary(child_revision_run_id)
    refute child_revision_run_id == revision_run_id
    assert after_iterate["resources"]["measurement_states"]["consumed"] >= measurement_before_check
    assert {:ok, child} = Store.call(Store.new(repo), :candidate, [child_id])
    assert child["parent_candidate_id"] == first_check["result"]["candidate_id"]
    assert child["base_revision_id"] == root.revision.id
    assert get_in(child, ["provenance", "revision_intelligence", "source_revision"]) ==
             child["result_revision_id"]

    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_steps WHERE run_id=$1::text::uuid AND stage='check' AND iteration=1",
               [fixture.run["id"]]
             )

    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert [] = Agent.get(script, & &1)

    assert {:ok, final_progress} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    assert [[1]] =
             sql(
               repo,
               "SELECT count(*) FROM fount_run_steps WHERE run_id=$1::text::uuid AND stage='iterate' AND iteration=1",
               [fixture.run["id"]]
             )

    assert final_progress["resources"]["measurement_states"]["consumed"] <=
             final_progress["resources"]["measurement_states"]["limit"]
  end

  defp reach_strategy_gate(repo, fixture, client) do
    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client)
    assert {:ok, progress} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    decision!(progress, "strategy")
  end

  defp fixture_run(repo, suffix, opts \\ []) do
    root = Keyword.get(opts, :root, Screenplay.new(title: [{"Title", "Phase 04 #{suffix}"}]))
    key = Keyword.get(opts, :key, "phase04-#{suffix}")

    if Keyword.get(opts, :persist, true) do
      assert {:ok, _} = Persistence.create(repo, key, root)
    end
    {:ok, owner} = Principal.new(:human, "owner-#{suffix}")
    {:ok, context} = ActorContext.new(owner, owner, root.id, [:read_run, :manage_run])

    request =
      Keyword.get(
        opts,
        :request,
        request_for(root, "develop", %{"placement" => %{"kind" => "start"}})
      )

    limits = %{
      "max_iterations" => Keyword.get(opts, :max_iterations, 1),
      "max_malformed_repairs_per_call" => 1,
      "max_transient_retries" => 2,
      "max_inference_calls" => Keyword.get(opts, :max_inference_calls, 20),
      "max_measurement_states" => Keyword.get(opts, :max_measurement_states, 500),
      "money" => nil
    }

    policy = %{
      "gates" => %{
        "investigation_scope" => "automatic",
        "strategy_choice" => "human",
        "candidate_generation" => "automatic",
        "iteration" => "automatic"
      },
      "completion" => "candidate",
      "approver" => nil,
      "fallback_approver" => nil,
      "route_choice" => %{"rule" => "pause_on_material_tradeoff"},
      "limits" => limits
    }

    attrs = %{
      "screenplay_id" => root.id,
      "base_revision_id" => root.revision.id,
      "goal" =>
        Keyword.get(opts, :goal, "Produce a checked screenplay candidate without advancing canon"),
      "scope" => request["selection"],
      "constraints" => [],
      "protected_material" => Keyword.get(opts, :protected_material, []),
      "client_idempotency_key" => "run-#{suffix}",
      "operation_parameters" => %{"workflow" => "develop"},
      "policy" => policy
    }

    assert {:ok, run} = FountRun.start_run(repo, attrs, context)

    %{
      run: run,
      context: context,
      owner: owner,
      root: root,
      key: key,
      request: request,
      attrs: attrs
    }
  end

  defp enqueue_intake(repo, fixture) do
    {:ok, envelope} = PipelineRequest.new(fixture.request)

    FountRun.enqueue_step(
      repo,
      fixture.run["id"],
      %{
        "stage" => "intake",
        "iteration" => 0,
        "branch_id" => "main",
        "input_revision_id" => fixture.root.revision.id,
        "idempotency_key" => "pipeline-intake",
        "request" => envelope
      },
      fixture.context
    )
  end

  defp run_step(repo, fixture, nil),
    do: FountRun.step(repo, fixture.run["id"], fixture.context, lease_ms: 5_000)

  defp run_step(repo, fixture, client),
    do:
      FountRun.step(repo, fixture.run["id"], fixture.context, inference: client, lease_ms: 5_000)

  defp run_step(repo, fixture, client, observe),
    do:
      FountRun.step(repo, fixture.run["id"], fixture.context,
        inference: client,
        observe: observe,
        lease_ms: 5_000
      )

  defp run_investigation(repo, fixture, client, observe) do
    assert {:ok, _} = enqueue_intake(repo, fixture)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, nil)
    assert {:ok, %{"status" => "succeeded"}} = run_step(repo, fixture, client, observe)
    assert {:ok, progress} = FountRun.progress(repo, fixture.run["id"], fixture.context)
    Enum.find(progress["steps"], &(&1["stage"] == "investigate"))
  end

  defp writer_packet(repo, investigate_step) do
    assert {:ok, session} =
             Store.call(Store.new(repo), :session, [investigate_step["result"]["session_id"]])

    get_in(session, ["progress", "preparation", "context", "data", "writer_intelligence"])
  end

  defp expire_active_lease(repo, run_id) do
    assert [[1]] =
             sql(
               repo,
               "UPDATE fount_run_steps SET lease_expires_at=now()-interval '1 second' WHERE run_id=$1::text::uuid AND status='running' RETURNING 1",
               [run_id]
             )

    :ok
  end

  defp decision!(progress, kind),
    do:
      Enum.find(progress["decisions"], &(&1["kind"] == kind)) || flunk("missing #{kind} decision")

  defp decision_response(decision, choice) do
    %{
      "choice" => choice,
      "context_fingerprint" => decision["context_fingerprint"],
      "plan_version" => decision["plan_version"],
      "policy_version" => decision["policy_version"]
    }
  end

  defp scripted_client(responses) do
    {:ok, script} =
      Agent.start_link(fn ->
        Enum.map(responses, fn response -> fn _request -> response end end)
      end)

    client = Inference.Client.new!(adapter: ScriptedCompletion, adapter_opts: [script: script])
    {client, script}
  end

  defp observe_provider(root, credential_canary \\ nil) do
    scene_spec = CapabilityMeasurements.scene_engine()
    revision_spec = CapabilityMeasurements.revision_intelligence()

    fixtures =
      Enum.reduce(root.ir.scenes, %{}, fn scene, acc ->
        acc
        |> Map.put(
          "capability:scene_engine:scene:#{scene.id}",
          measurement_answers(scene_spec["questions"])
        )
        |> Map.put(
          "capability:revision_intelligence:scene:#{scene.id}",
          measurement_answers(revision_spec["questions"])
        )
      end)

    fixtures =
      if credential_canary,
        do: Map.put(fixtures, "provider-only-credential", %{"secret" => credential_canary}),
        else: fixtures

    Sandbox.new!(fixtures)
  end

  defp prewrite_only_observe_provider(root) do
    scene_spec = CapabilityMeasurements.scene_engine()

    fixtures =
      Enum.reduce(root.ir.scenes, %{}, fn scene, acc ->
        Map.put(
          acc,
          "capability:scene_engine:scene:#{scene.id}",
          measurement_answers(scene_spec["questions"])
        )
      end)

    Sandbox.new!(fixtures)
  end

  defp measurement_answers(questions) do
    Map.new(questions, fn {key, question} ->
      value =
        case question.kind do
          :noul ->
            0.9

          :score ->
            0

          :choice ->
            labels = Enum.map(question.criteria, &elem(&1, 0))
            selected = hd(labels)
            remainder = if length(labels) > 1, do: 0.1 / (length(labels) - 1), else: 0.0

            %{
              "probabilities" =>
                Map.new(labels, &{&1, if(&1 == selected, do: 0.9, else: remainder)}),
              "choice" => selected,
              "confidence" => 0.9
            }
        end

      {to_string(key), value}
    end)
  end

  defp investigation_plan do
    %{
      "hypotheses" => [
        %{
          "id" => "h1",
          "claim" => "A visible choice should trigger the reveal.",
          "reason" => "The brief asks for consequence.",
          "request_ids" => ["search-1"]
        }
      ],
      "requests" => [
        %{
          "id" => "search-1",
          "playbook" => "search",
          "params" => %{"query" => "choice", "selection" => %{"whole_screenplay" => true}}
        }
      ]
    }
  end

  defp investigation_explanation do
    %{
      "answer" => "The reveal should close an easy exit and create an immediate consequence.",
      "revised_hypotheses" => [
        %{
          "id" => "h1",
          "claim" => "Make the reveal causal.",
          "reason" => "A visible consequence keeps the turn dramatic.",
          "status" => "supported",
          "evidence_ids" => []
        }
      ],
      "uncertainties" => ["The antagonist's exact motive remains unstated."],
      "evidence_ids" => [],
      "strategies" => [
        %{
          "id" => "route-a",
          "title" => "Commit now",
          "dramatic_mechanism" => "The choice closes the exit.",
          "beats" => ["Choice", "Reveal", "Consequence"],
          "evidence_ids" => []
        },
        %{
          "id" => "route-b",
          "title" => "Delay the reveal",
          "dramatic_mechanism" => "Suspicion grows before confirmation.",
          "beats" => ["Suspicion", "Delay", "Reveal"],
          "evidence_ids" => []
        },
        %{
          "id" => "route-c",
          "title" => "Reverse the leverage",
          "dramatic_mechanism" => "The target weaponizes the reveal.",
          "beats" => ["Reveal", "Countermove", "Cost"],
          "evidence_ids" => []
        }
      ],
      "follow_up_requests" => []
    }
  end

  defp repair_strategy_response do
    %{
      "strategies" => [
        %{
          "id" => "repair",
          "title" => "Preserve then answer",
          "premise_of_change" =>
            "Keep the protected train beat and add its consequence afterward.",
          "dramatic_mechanism" => "Consequence rather than replacement",
          "entry_state" => "Reveal landed",
          "exit_state" => "Reveal has a cost",
          "beats" => ["Preserve train beat", "Add consequence"],
          "preserves" => ["train beat"],
          "changes" => ["aftermath"],
          "inventions" => [],
          "consequences" => ["evidence becomes harder to reach"],
          "evidence_ids" => [],
          "open_questions" => []
        }
      ]
    }
  end

  defp repair_extraction_response do
    %{"summary" => "The protected platform beat remains visible.", "records" => []}
  end

  defp opening_proposal(root) do
    proposal(root, "route-a", [
      %{
        "kind" => "insert_scene",
        "value" => %{
          "after_scene_id" => nil,
          "scene" => %{
            "local_id" => "new:opening",
            "heading" => "INT. LOCKED ROOM - NIGHT",
            "elements" => [
              %{
                "local_id" => "new:action",
                "type" => "action",
                "text" => "Mara turns the deadbolt before the footsteps reach the hall.",
                "attrs" => %{}
              }
            ]
          }
        }
      }
    ])
  end

  defp violating_reveal_proposal(root, action_id) do
    scene_id = hd(root.ir.scenes).id

    proposal(root, "route-a", [
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => action_id},
        "value" => "Nora abandons the platform and the protected beat disappears."
      },
      insert_consequence(scene_id)
    ])
  end

  defp violating_text_proposal(root, action_id) do
    proposal(root, "route-a", [
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => action_id},
        "value" => "Nora abandons the platform and the protected beat disappears."
      }
    ])
  end

  defp repaired_dialogue_proposal(root, dialogue_id) do
    proposal(root, "repair", [
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => dialogue_id},
        "value" => "Late enough to make the lock matter."
      }
    ])
  end

  defp repaired_reveal_proposal(root) do
    scene_id = hd(root.ir.scenes).id
    proposal(root, "repair", [insert_consequence(scene_id)])
  end

  defp insert_consequence(scene_id) do
    %{
      "kind" => "insert_scene",
      "value" => %{
        "after_scene_id" => scene_id,
        "scene" => %{
          "local_id" => "new:consequence",
          "heading" => "INT. STATION OFFICE - NIGHT",
          "elements" => [
            %{
              "local_id" => "new:consequence-action",
              "type" => "action",
              "text" => "The stationmaster locks the evidence cabinet.",
              "attrs" => %{}
            }
          ]
        }
      }
    }
  end

  defp proposal(root, strategy_id, operations) do
    %{
      "version" => 1,
      "base_revision_id" => root.revision.id,
      "strategy_id" => strategy_id,
      "summary" => "Play the selected dramatic route and its consequence.",
      "inventions" => [],
      "unresolved_questions" => [],
      "groups" => [
        %{
          "id" => "screenplay-change",
          "title" => "Screenplay change",
          "reason" => "Make the route visible on the page.",
          "depends_on" => [],
          "addresses_notes" => [],
          "evidence_ids" => [],
          "origin" => "generated_text",
          "operations" => operations
        }
      ]
    }
  end

  defp dialogue_root do
    Screenplay.new(
      title: [{"Title", "Selected Dialogue"}],
      body: [
        %{
          type: :scene,
          heading: "INT. INTERVIEW ROOM - NIGHT",
          elements: [
            %{type: :action, text: "Nora keeps her hands flat on the table."},
            %{type: :character, text: "NORA"},
            %{type: :dialogue, text: "I didn't miss anything."}
          ]
        }
      ]
    )
  end

  defp dialogue_proposal(root, dialogue_id) do
    proposal(root, "route-a", [
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => dialogue_id},
        "value" => "If you missed it, you were meant to."
      }
    ])
  end

  defp train_root do
    Screenplay.new(
      title: [{"Title", "Protected Train Reveal"}],
      body: [
        %{
          type: :scene,
          heading: "EXT. TRAIN PLATFORM - NIGHT",
          elements: [
            %{type: :action, text: "Nora waits under the departure board."},
            %{type: :character, text: "NORA"},
            %{type: :dialogue, text: "The train is late."}
          ]
        }
      ]
    )
  end

  defp request_for(root, workflow, options) do
    %{
      "version" => 1,
      "workflow" => workflow,
      "mode" => if(workflow == "investigate", do: "inspect", else: "revise"),
      "base_revision_id" => root.revision.id,
      "instruction" => "Make a causal screenplay change while preserving protected material.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 1,
      "options" => options
    }
  end

  defp sql(repo, statement, params \\ []),
    do: SQL.query!(repo, statement, params, log: false).rows

  defp restart_repo(prefix) do
    stop_supervised(Repo)

    start_supervised!(
      {Repo,
       url: System.fetch_env!("FOUNT_DATABASE_URL"),
       pool_size: 4,
       parameters: [search_path: prefix],
       migration_default_prefix: prefix}
    )
  end
end
