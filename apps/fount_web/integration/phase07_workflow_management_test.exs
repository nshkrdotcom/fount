defmodule FountWeb.Phase07WorkflowManagementIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias FountWeb.WorkflowManagement, as: Workflow

  defp create_run(suffix) do
    FountWeb.Launch.create("test-owner", %{
      "title" => "Phase 07 #{suffix}",
      "key" => "phase07-#{suffix}",
      "journey" => "opening",
      "source" => FountWeb.Journeys.fixture_fountain(),
      "filename" => "phase07.fountain"
    })
  end

  test "W01 complete policy UI uses trusted principals and versioned owner presets", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, %{run: run}} = create_run("policy")
    assert {:ok, view, html} = live(conn, "/runs/#{run["id"]}/setup")

    for gate <- ~w(investigation_scope strategy_choice candidate_generation iteration) do
      assert html =~ ~s(name="policy[#{gate}]")
    end

    assert html =~ "Max microunits"
    assert html =~ "Authenticated owner"
    assert html =~ "Versioned policy presets"
    assert html =~ "registered_reviewer"
    assert html =~ "Registered route reviewer"

    render_submit(element(view, "form[phx-submit=save_current_preset]"), %{
      "preset" => %{"name" => "Writer safe"}
    })

    [saved] = FountWeb.Store.list_policy_presets(Fount.Repo, "test-owner")
    assert saved["name"] == "Writer safe"
    assert saved["version"] == 1

    render_submit(element(view, "form[phx-submit=save_current_preset]"), %{
      "preset" => %{"name" => "Writer safe"}
    })

    [newer, older] = FountWeb.Store.list_policy_presets(Fount.Repo, "test-owner")
    assert {newer["version"], older["version"]} == {2, 1}

    assert FountWeb.Store.list_policy_presets(Fount.Repo, "other-owner") == []

    {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])

    assert {:error, :owner_context_mismatch} =
             Workflow.save_preset(
               Fount.Repo,
               "other-owner",
               "Cross owner",
               get_in(run, ["policy", "policy"]),
               context
             )
  end

  test "W02/W03 exact-base scope feeds only enabled durable action requests and duplicate launch replays" do
    assert {:ok, %{project: project, run: run}} = create_run("scope-action")
    {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])

    {:ok, model} =
      Fount.Persistence.load_revision(
        Fount.Repo,
        run["screenplay_id"],
        get_in(run, ["plan", "base_revision_id"])
      )

    [scene | _] = model.ir.scenes

    selection = %{"targets" => [%{"kind" => "scene", "id" => scene.id}]}

    assert {:ok, saved} =
             Workflow.save_selection(Fount.Repo, "test-owner", run, selection, context)

    assert saved["base_revision_id"] == get_in(run, ["plan", "base_revision_id"])
    assert saved["selection"] == selection

    assert {:error, :owner_context_mismatch} =
             Workflow.save_selection(Fount.Repo, "other-owner", run, selection, context)

    assert {:error, _} =
             Workflow.build_workshop_request(
               model,
               "develop",
               "Invalid deleted target.",
               %{"targets" => [%{"kind" => "scene", "id" => Fount.ID.v4()}]}
             )

    Ecto.Adapters.SQL.query!(
      Fount.Repo,
      "UPDATE fount_web_workflow_selections SET base_revision_id=$2::text::uuid WHERE run_id=$1::text::uuid",
      [run["id"], Fount.ID.v4()]
    )

    assert {:error, :selection_base_stale} =
             Workflow.load_selection(Fount.Repo, "test-owner", run, context)

    assert {:ok, _} = Workflow.save_selection(Fount.Repo, "test-owner", run, selection, context)

    attrs = %{
      "command_id" => "same-command",
      "action" => "develop",
      "instruction" => "Tighten the selected scene.",
      "selection" => selection,
      "policy" => get_in(run, ["policy", "policy"])
    }

    assert {:ok, %{run: first}} =
             FountWeb.Launch.create_action_from_base(
               "test-owner",
               project["id"],
               model.revision.id,
               attrs
             )

    assert {:ok, %{run: replay}} =
             FountWeb.Launch.create_action_from_base(
               "test-owner",
               project["id"],
               model.revision.id,
               attrs
             )

    assert first["id"] == replay["id"]

    for action <- ~w(develop pass propagate) do
      command_id = "handler-" <> action

      assert {:ok, %{run: action_run}} =
               FountWeb.Launch.create_action_from_base(
                 "test-owner",
                 project["id"],
                 model.revision.id,
                 %{
                   attrs
                   | "command_id" => command_id,
                     "action" => action,
                     "instruction" => "Verify the durable #{action} intake path."
                 }
               )

      assert {:ok, completed_step} = FountRun.step(Fount.Repo, action_run["id"], context, [])
      assert completed_step["stage"] == "intake"
      assert completed_step["status"] == "succeeded"
    end

    assert {:error, :unsupported_run_action} =
             FountWeb.Launch.create_action_from_base(
               "test-owner",
               project["id"],
               model.revision.id,
               %{attrs | "command_id" => "unsupported", "action" => "investigate"}
             )

    assert {:error, :not_found} =
             FountWeb.Store.workflow_selection(Fount.Repo, "other-owner", run["id"])
  end

  test "W04 contextual decision cards keep recorded Intelligence and exact approval bindings" do
    decision_id = Fount.ID.v4()
    step_id = Fount.ID.v4()
    candidate_id = Fount.ID.v4()
    base_id = Fount.ID.v4()
    check_fingerprint = String.duplicate("a", 64)

    decision = %{
      "id" => decision_id,
      "step_id" => step_id,
      "candidate_id" => candidate_id,
      "base_revision_id" => base_id,
      "check_set_fingerprint" => check_fingerprint,
      "plan_version" => 3,
      "policy_version" => 4
    }

    progress = %{
      "steps" => [
        %{
          "id" => step_id,
          "result" => %{
            "analysis" => %{"analysis_run_id" => "analysis-1", "packet_id" => "packet-1"},
            "report_ids" => ["report-1"]
          }
        }
      ],
      "analysis" => []
    }

    candidate_revision_id = Fount.ID.v4()

    context =
      Workflow.decision_context(progress, decision, %{
        "candidate_id" => candidate_id,
        "base_revision_id" => base_id,
        "candidate_revision_id" => candidate_revision_id,
        "check_set_fingerprint" => check_fingerprint
      })

    assert context["analysis_lineage"]["analysis_run_id"] == "analysis-1"
    assert context["report_ids"] == ["report-1"]
    assert context["candidate_id"] == candidate_id
    assert context["base_revision_id"] == base_id
    assert context["candidate_revision_id"] == candidate_revision_id
    assert context["check_set_fingerprint"] == check_fingerprint

    unrelated_progress = %{
      "steps" => [%{"id" => step_id, "result" => %{}}],
      "analysis" => [%{"analysis_run_id" => "unrelated-latest"}]
    }

    mismatched =
      Workflow.decision_context(unrelated_progress, decision, %{
        "candidate_id" => Fount.ID.v4(),
        "base_revision_id" => base_id,
        "candidate_revision_id" => Fount.ID.v4(),
        "check_set_fingerprint" => String.duplicate("b", 64)
      })

    assert is_nil(mismatched["analysis_lineage"])
    assert is_nil(mismatched["candidate_revision_id"])
    assert mismatched["check_set_fingerprint"] == check_fingerprint
  end

  test "W06 export preview identifies candidate truthfully and exposes only supported options", %{
    conn: conn
  } do
    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, %{run: run, access: access}} = create_run("exports")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])
    [action | _] = Fount.Query.elements(base, :action)

    {:ok, changed} =
      Fount.Screenplay.apply(
        base,
        Fount.Edit.replace_text(action.id, "A deterministic Phase 07 edit.")
      )

    {:ok, candidate} = Fount.Persistence.save_edit_candidate(Fount.Repo, access["key"], changed)

    Ecto.Adapters.SQL.query!(
      Fount.Repo,
      "UPDATE fount_runs SET selected_candidate_id=$2::text::uuid,status='completed_candidate' WHERE id=$1::text::uuid",
      [run["id"], candidate.id]
    )

    {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])
    {:ok, durable_run} = FountRun.get_run(Fount.Repo, run["id"], context)
    {:ok, progress} = FountRun.progress(Fount.Repo, run["id"], context)
    assert {:ok, preview} = Workflow.export_preview(Fount.Repo, durable_run, progress, context)
    assert preview["completion"] == "candidate"
    assert preview["candidate_id"] == candidate.id
    assert is_list(preview["fdx_losses"])
    assert preview["fountain_bytes"] > 0

    assert {:ok, _view, html} = live(conn, "/runs/#{run["id"]}/exports")
    assert html =~ "Standard bundle formats are Fountain, FDX"
    assert html =~ "Optional formats are only PDF and table-read"
    assert html =~ "explicitly fails/partials"
    refute html =~ "DOCX"
  end

  test "W05 pause/resume and plan/policy updates fence versions; stop is terminal and replay-safe" do
    assert {:ok, %{run: run}} = create_run("controls")
    {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])

    assert {:ok, paused} = FountRun.pause_run(Fount.Repo, run["id"], context)
    assert paused["run"]["status"] == "paused"
    assert {:ok, resumed} = FountRun.resume_run(Fount.Repo, run["id"], context)
    refute resumed["run"]["status"] == "paused"

    assert {:ok, plan} = Workflow.plan_update(run["plan"], "Updated owner goal")

    assert {:ok, plan_result} =
             FountRun.update_plan(Fount.Repo, run["id"], plan, context,
               expected_version: run["current_plan_version"],
               command_id: "phase07-plan"
             )

    assert plan_result["plan"]["version"] == run["current_plan_version"] + 1

    assert {:error, {:stale_plan_version, _}} =
             FountRun.update_plan(Fount.Repo, run["id"], plan, context,
               expected_version: run["current_plan_version"],
               command_id: "phase07-stale-plan"
             )

    {:ok, after_plan} = FountRun.get_run(Fount.Repo, run["id"], context)

    assert {:ok, policy_result} =
             FountRun.update_policy(
               Fount.Repo,
               run["id"],
               get_in(run, ["policy", "policy"]),
               context,
               expected_version: after_plan["current_policy_version"],
               command_id: "phase07-policy"
             )

    assert policy_result["policy"]["version"] == after_plan["current_policy_version"] + 1

    assert {:ok, stopped} = FountRun.stop_run(Fount.Repo, run["id"], context)
    assert stopped["run"]["status"] == "stopped"
    assert {:ok, replay} = FountRun.stop_run(Fount.Repo, run["id"], context)
    assert replay["replay"]
    assert {:error, :terminal_run} = FountRun.pause_run(Fount.Repo, run["id"], context)
  end

  test "W07 bounded multi-launch preserves partial results and duplicate-safe retry" do
    assert {:ok, %{project: project, run: run}} = create_run("multi")

    {:ok, model} =
      Fount.Persistence.load_revision(
        Fount.Repo,
        run["screenplay_id"],
        get_in(run, ["plan", "base_revision_id"])
      )

    [first_scene, second_scene | _] = model.ir.scenes

    selection = %{
      "targets" => [
        %{"kind" => "scene", "id" => first_scene.id},
        %{"kind" => "scene", "id" => second_scene.id}
      ]
    }

    assert {:ok, preview} =
             Workflow.launch_preview(
               model,
               "pass",
               "Sharpen dialogue.",
               selection,
               get_in(run, ["policy", "policy"]),
               true
             )

    [valid, invalid] = preview["entries"]

    invalid =
      put_in(invalid, ["selection", "targets"], [%{"kind" => "scene", "id" => Fount.ID.v4()}])

    preview = %{preview | "entries" => [valid, invalid]}

    first = Workflow.execute_launch_preview("test-owner", project["id"], preview)
    summary = Workflow.launch_summary(first)
    assert length(summary["created"]) == 1
    assert length(summary["failed"]) == 1
    assert summary["partial"]

    second = Workflow.execute_launch_preview("test-owner", project["id"], preview)
    assert hd(first)["run_id"] == hd(second)["run_id"]
    assert Enum.at(second, 1)["state"] == "failed"

    rows = Workflow.list_owner_runs(Fount.Repo, "test-owner", limit: 2)
    assert length(rows) <= 2

    assert Enum.all?(
             rows,
             &(&1["screenplay_id"] == run["screenplay_id"] or is_binary(&1["screenplay_id"]))
           )

    assert Workflow.list_owner_runs(Fount.Repo, "other-owner", limit: 50) == []

    created_id = hd(first)["run_id"]

    assert {:ok, comparison} =
             Workflow.compare_owner_runs(Fount.Repo, "test-owner", run["id"], created_id)

    assert is_list(comparison["facts"])

    assert {:error, :not_found} =
             Workflow.compare_owner_runs(Fount.Repo, "other-owner", run["id"], created_id)
  end

  test "W08 PubSub is a reload hint and reconnect projection is deterministic and owner scoped" do
    assert {:ok, %{run: run}} = create_run("notifications")
    {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])

    Phoenix.PubSub.subscribe(FountWeb.PubSub, FountWeb.RunEvents.topic(run["id"]))
    FountWeb.RunEvents.notify(run["id"])
    assert_receive {:run_changed, received}, 500
    assert received == run["id"]

    assert {:ok, durable_run} = FountRun.get_run(Fount.Repo, run["id"], context)
    assert {:ok, progress} = FountRun.progress(Fount.Repo, run["id"], context)

    assert Workflow.notifications(durable_run, progress) ==
             Workflow.notifications(durable_run, progress)

    assert {:error, :not_found} = FountWeb.Store.run_access(Fount.Repo, "other-owner", run["id"])
  end
end
