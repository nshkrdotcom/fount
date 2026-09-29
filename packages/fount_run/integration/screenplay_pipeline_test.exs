Code.require_file("../../fount_workshop/support/scripted_completion.ex", __DIR__)

defmodule FountRun.ScreenplayPipelineIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Fount.{ID, Persistence, Query, Screenplay}
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
    key = "phase04-#{suffix}"
    assert {:ok, _} = Persistence.create(repo, key, root)
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
      "max_inference_calls" => 20,
      "max_measurement_states" => 500,
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
      "goal" => "Produce a checked screenplay candidate without advancing canon",
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
