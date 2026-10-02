defmodule FountWeb.SI02SemanticImportAssessmentIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias FountWeb.{Launch, ProductionTools, ProjectContext, SemanticStore, Services, Store}

  @source """
  Title: SI02 Fixture

  INT. MERCY HOSPITAL - RECORDS WINDOW - LATE NIGHT (2031)

  !WORK ORDER
  AUTHORIZED STAFF ONLY

  DR. MIRA VALE (O.S.)
  Bring me the chart.

  MIRA VALE
  Thank you.

  GUARD
  West door.

  GUARD
  East door.

  EVELYN enters carrying a sealed envelope.
  """

  setup do
    previous = Application.get_env(:fount_web, :semantic_assessment)
    on_exit(fn -> Application.put_env(:fount_web, :semantic_assessment, previous) end)
    :ok
  end

  test "missing assessment service stays honest and manual import remains zero-Run" do
    Application.put_env(:fount_web, :semantic_assessment, mode: :disabled)

    assert {:ok, %{project: project}} = create_import("SI02 disabled")
    assert Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20) == []

    assert {:error, :semantic_assessment_not_configured} =
             Launch.assess_project("test-owner", project["id"], %{
               "command_id" => "disabled-command"
             })

    assert Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20) == []
    assert Services.assessment_service_summary()["configured"] == false
  end

  test "requested fixture assessment is exactly one durable non-mutating Run with source-bound suggestions" do
    fixture_service!()
    assert {:ok, %{project: project, screenplay: imported}} = create_import("SI02 assessed")
    base_revision = imported.revision.id
    assert imported.import.bytes == @source
    assert Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20) == []

    assert {:ok, %{assessment: queued, run: run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "assessment-1"})

    assert queued["status"] == "queued"
    assert queued["model"] == "gpt-6.1-sol"
    assert queued["reasoning_effort"] == "low"
    assert queued["origin"] == "deterministic_fixture"

    assert length(Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20)) ==
             1

    completed = complete_semantic_run(run)
    assert completed["status"] == "completed_nonmutating"
    assert completed["selected_candidate_id"] == nil

    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    assert context.current.revision.id == base_revision
    assert context.current.import.bytes == @source

    semantic = context.semantic
    assert semantic.assessment_state == :ready
    assert semantic.latest_assessment["run_id"] == run["id"]
    assert semantic.latest_assessment["model"] == "gpt-6.1-sol"
    assert semantic.latest_assessment["reasoning_effort"] == "low"
    assert semantic.latest_assessment["provider_returned_model"] == "gpt-6.1-sol"
    assert semantic.coverage["processed_span_ids"] != []

    refute Enum.any?(semantic.characters, &(&1.display_name == "WORK ORDER"))
    assert Enum.all?(semantic.characters, &(&1.review_state == "suggested"))

    mira = Enum.find(semantic.characters, &String.contains?(&1.display_name, "MIRA VALE"))
    assert mira
    assert mira.speaking_occurrences == 2
    assert "DR. MIRA VALE" in [mira.display_name | mira.aliases]
    assert "MIRA VALE" in [mira.display_name | mira.aliases]
    assert mira.presence_occurrences == 0

    guards = Enum.filter(semantic.characters, &(&1.display_name == "GUARD"))
    assert length(guards) == 2
    assert Enum.all?(guards, &(&1.speaking_occurrences == 1))

    evelyn = Enum.find(semantic.characters, &(&1.display_name == "EVELYN"))
    assert evelyn
    assert evelyn.speaking_occurrences == 0
    assert evelyn.presence_occurrences == 1

    assert {:ok, progress_before} = FountRun.progress(Fount.Repo, run["id"], owner_context(run))
    assert Enum.all?(progress_before["steps"], &is_nil(get_in(&1, ["result", "candidate_id"])))
  end

  test "review precedence survives reassessment and new table reads use resolved roster without creating a Run" do
    fixture_service!()
    assert {:ok, %{project: project}} = create_import("SI02 review carry-forward")

    assert {:ok, %{run: first_run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "assessment-a"})

    _ = complete_semantic_run(first_run)
    assert {:ok, first} = ProjectContext.load("test-owner", project["key"])

    mira = Enum.find(first.semantic.characters, &String.contains?(&1.display_name, "MIRA VALE"))
    assert mira

    assert {:ok, _event} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               project["id"],
               first.semantic.assessment_id,
               %{
                 "action" => "confirm",
                 "target_handle_id" => mira.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => first.semantic.version,
                 "command_id" => "confirm-mira",
                 "actor" => "human:test-owner"
               }
             )

    runs_before_reassessment =
      Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20)

    assert length(runs_before_reassessment) == 1

    assert {:ok, %{run: second_run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "assessment-b"})

    _ = complete_semantic_run(second_run)

    assert {:ok, current} = ProjectContext.load("test-owner", project["key"])

    mira_after =
      Enum.find(current.semantic.characters, &(&1.semantic_handle_id == mira.semantic_handle_id))

    assert mira_after.review_state == "confirmed"
    assert current.semantic.version == 1
    assert length(current.semantic.assessment_history) >= 3

    assert {:error, {:stale_review, conflict}} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               project["id"],
               current.semantic.assessment_id,
               %{
                 "action" => "confirm",
                 "target_handle_id" => mira.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => 0,
                 "command_id" => "stale-after-reassessment",
                 "actor" => "human:test-owner"
               }
             )

    assert conflict["outcome"] == "conflict"
    assert conflict["new_version"] == 1

    before_read_runs = Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20)

    assert {:ok, saved_read} =
             ProductionTools.create_project_table_read(
               Fount.Repo,
               "test-owner",
               project,
               current.current,
               %{"whole_screenplay" => true},
               %{"title" => "Semantic roster read"}
             )

    assert length(Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20)) ==
             length(before_read_runs)

    assert saved_read["packet"]["semantic_roster_claim"] =~
             "source cue/dialogue text is unchanged"

    assert Enum.any?(
             saved_read["packet"]["semantic_roster"],
             &(&1["handle_id"] == mira.semantic_handle_id)
           )

    assert Enum.all?(saved_read["packet"]["turns"], &is_binary(&1["cue"]))
  end

  test "launch replay after lost acknowledgement reuses the assessment and Run" do
    fixture_service!()
    assert {:ok, %{project: project}} = create_import("SI02 replay")
    attrs = %{"command_id" => "lost-ack"}
    assert {:ok, first} = Launch.assess_project("test-owner", project["id"], attrs)
    assert {:ok, replay} = Launch.assess_project("test-owner", project["id"], attrs)
    assert replay.run["id"] == first.run["id"]
    assert replay.assessment["id"] == first.assessment["id"]

    assert length(Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20)) ==
             1

    complete_semantic_run(first.run)
    assert {:ok, completed_replay} = Launch.assess_project("test-owner", project["id"], attrs)
    assert completed_replay.run["id"] == first.run["id"]
  end

  test "cancellation before final persistence leaves no result and a new command can retry" do
    fixture_service!()
    assert {:ok, %{project: project}} = create_import("SI02 cancel")

    assert {:ok, %{run: run, assessment: assessment}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "cancel"})

    context = owner_context(run)
    assert {:ok, opts} = Services.worker_step_opts("test-owner", run["screenplay_id"], run)
    for _ <- 1..5, do: assert({:ok, _} = FountRun.step(Fount.Repo, run["id"], context, opts))
    assert {:ok, current} = FountRun.get_run(Fount.Repo, run["id"], context)
    assert current["stage"] == "semantic_persist"
    assert {:ok, _} = FountRun.stop_run(Fount.Repo, run["id"], context)

    assert {:ok, row} =
             SemanticStore.assessment(Fount.Repo, "test-owner", project["id"], assessment["id"])

    assert row["result"] == %{}

    assert {:ok, %{run: retry}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "retry"})

    assert retry["id"] != run["id"]
    complete_semantic_run(retry)
  end

  test "missing SI02 schema fails actionably and rolls back the assessment and Run" do
    fixture_service!()
    assert {:ok, %{project: project}} = create_import("SI02 schema absent")

    Ecto.Adapters.SQL.query!(
      Fount.Repo,
      "ALTER TABLE fount_web_semantic_assessments DROP COLUMN command_id CASCADE",
      []
    )

    assert {:error, :semantic_schema_missing} =
             Launch.assess_project("test-owner", project["id"], %{
               "command_id" => "missing-schema"
             })

    assert Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20) == []

    assert {:ok, rows} =
             Ecto.Adapters.SQL.query(
               Fount.Repo,
               "SELECT count(*) FROM fount_web_semantic_assessments WHERE origin='deterministic_fixture'",
               []
             )

    assert rows.rows == [[0]]
  end

  test "JSON-text fallback uses the same trusted validator and exact request policy" do
    Application.put_env(:fount_web, :semantic_assessment,
      mode: :deterministic_fixture,
      client_factory:
        {FountWeb.SemanticFixtureAdapter, :client, [[json_text: true, capture_to: self()]]}
    )

    assert {:ok, %{project: project}} = create_import("SI02 text fallback")

    assert {:ok, %{run: run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "text"})

    complete_semantic_run(run)
    assert_receive {:semantic_fixture_request, request}
    assert request.model == "gpt-6.1-sol"
    assert request.options[:reasoning_effort] == :low
    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    assert context.semantic.assessment_state == :ready
  end

  test "missing and mismatched returned models fail before result persistence" do
    for model <- [nil, "wrong-model"] do
      Application.put_env(:fount_web, :semantic_assessment,
        mode: :deterministic_fixture,
        client_factory: {FountWeb.SemanticFixtureAdapter, :client, [[returned_model: model]]}
      )

      assert {:ok, %{project: project}} = create_import("SI02 returned model #{inspect(model)}")

      assert {:ok, %{run: run, assessment: assessment}} =
               Launch.assess_project("test-owner", project["id"], %{"command_id" => "wrong-model"})

      context = owner_context(run)
      assert {:ok, opts} = Services.worker_step_opts("test-owner", run["screenplay_id"], run)
      for _ <- 1..2, do: assert({:ok, _} = FountRun.step(Fount.Repo, run["id"], context, opts))
      assert {:error, _} = FountRun.step(Fount.Repo, run["id"], context, opts)

      assert {:ok, row} =
               SemanticStore.assessment(Fount.Repo, "test-owner", project["id"], assessment["id"])

      assert row["result"] == %{}
    end
  end

  test "large Unicode CRLF source reaches late evidence without changing exact bytes" do
    fixture_service!()

    source =
      "INT. CAFÉ - DAY\r\n\r\n" <>
        String.duplicate("The café remains quiet.\r\n", 6_000) <>
        "\r\nEVELYN enters carrying a sealed envelope.\r\n"

    assert byte_size(source) > 100_000

    assert {:ok, %{project: project}} =
             Launch.create_project("test-owner", %{
               "title" => "SI02 large",
               "kind" => "import",
               "source" => source,
               "filename" => "large.fountain"
             })

    assert {:ok, %{run: run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "large"})

    complete_semantic_run(run)
    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    assert context.current.import.bytes == source
    assert context.semantic.coverage["completed_chunks"] > 1

    assert Enum.any?(
             context.semantic.characters,
             &(&1.display_name == "EVELYN" and &1.presence_occurrences == 1)
           )
  end

  test "expired worker is fenced and a restarted worker finishes the same Run" do
    fixture_service!()
    assert {:ok, %{project: project}} = create_import("SI02 fencing")

    assert {:ok, %{run: run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "fenced"})

    context = owner_context(run)

    assert {:ok, claim} =
             FountRun.ExecutionStore.claim(Fount.Repo, run["id"], "crashed-worker", context)

    Ecto.Adapters.SQL.query!(
      Fount.Repo,
      "UPDATE fount_run_steps SET lease_expires_at=now()-interval '1 second' WHERE id=$1::text::uuid",
      [claim["step_id"]]
    )

    complete_semantic_run(run)

    assert {:error, _} =
             FountRun.ExecutionStore.complete(Fount.Repo, claim, %{"changes_canon" => false})

    assert length(Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20)) ==
             1
  end

  test "database rejects terminal result, usage, identity and review-history mutation" do
    fixture_service!()
    assert {:ok, %{project: project}} = create_import("SI02 immutable")

    assert {:ok, %{run: run, assessment: assessment}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "immutable"})

    complete_semantic_run(run)

    for field <- ~w(result usage coverage) do
      assert {:error, %Postgrex.Error{}} =
               Ecto.Adapters.SQL.query(
                 Fount.Repo,
                 "UPDATE fount_web_semantic_assessments SET " <>
                   field <> "='{}'::jsonb WHERE id=$1::text::uuid",
                 [assessment["id"]],
                 mode: :savepoint
               )
    end

    assert {:error, %Postgrex.Error{}} =
             Ecto.Adapters.SQL.query(
               Fount.Repo,
               "UPDATE fount_web_semantic_assessments SET source_sha256=$2 WHERE id=$1::text::uuid",
               [assessment["id"], String.duplicate("a", 64)],
               mode: :savepoint
             )

    assert {:error, :not_found} =
             SemanticStore.assessment(
               Fount.Repo,
               "another-owner",
               project["id"],
               assessment["id"]
             )

    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    person = hd(context.semantic.characters)

    assert {:ok, _} =
             SemanticStore.review(Fount.Repo, "test-owner", project["id"], assessment["id"], %{
               "action" => "confirm",
               "target_handle_id" => person.semantic_handle_id,
               "payload" => %{},
               "expected_version" => 0,
               "command_id" => "immutable-review",
               "actor" => "human:test-owner"
             })

    assert {:error, %Postgrex.Error{}} =
             Ecto.Adapters.SQL.query(
               Fount.Repo,
               "UPDATE fount_web_semantic_review_events SET payload='{}'::jsonb WHERE assessment_id=$1::text::uuid",
               [assessment["id"]],
               mode: :savepoint
             )
  end

  test "unknown dispatch acknowledgement pauses without replaying the provider call" do
    Application.put_env(:fount_web, :semantic_assessment,
      mode: :deterministic_fixture,
      client_factory: {FountWeb.SemanticFixtureAdapter, :client, [[capture_to: self()]]}
    )

    assert {:ok, %{project: project}} = create_import("SI02 unknown acknowledgement")

    assert {:ok, %{run: run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "unknown-ack"})

    context = owner_context(run)
    assert {:ok, opts} = Services.worker_step_opts("test-owner", run["screenplay_id"], run)
    for _ <- 1..2, do: assert({:ok, _} = FountRun.step(Fount.Repo, run["id"], context, opts))

    fault = fn
      :after_provider_call_before_response_persist -> raise "fixture acknowledgement lost"
      _ -> :ok
    end

    assert_raise RuntimeError, "fixture acknowledgement lost", fn ->
      FountRun.step(Fount.Repo, run["id"], context, Keyword.put(opts, :fault_injector, fault))
    end

    assert_receive {:semantic_fixture_request, _}

    Ecto.Adapters.SQL.query!(
      Fount.Repo,
      "UPDATE fount_run_steps SET lease_expires_at=now()-interval '1 second' WHERE run_id=$1::text::uuid AND status='running'",
      [run["id"]]
    )

    assert {:error, :ambiguous_provider_outcome} =
             FountRun.step(Fount.Repo, run["id"], context, opts)

    refute_receive {:semantic_fixture_request, _}

    assert {:ok, result} =
             Ecto.Adapters.SQL.query(
               Fount.Repo,
               "SELECT status FROM fount_run_provider_requests WHERE run_id=$1::text::uuid",
               [run["id"]]
             )

    assert result.rows == [["unknown"]]
  end

  test "forged durable chunk source is rejected before provider dispatch" do
    Application.put_env(:fount_web, :semantic_assessment,
      mode: :deterministic_fixture,
      client_factory: {FountWeb.SemanticFixtureAdapter, :client, [[capture_to: self()]]}
    )

    assert {:ok, %{project: project}} = create_import("SI02 forged checkpoint")

    assert {:ok, %{run: run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "forged"})

    context = owner_context(run)
    assert {:ok, opts} = Services.worker_step_opts("test-owner", run["screenplay_id"], run)
    for _ <- 1..2, do: assert({:ok, _} = FountRun.step(Fount.Repo, run["id"], context, opts))

    assert {:ok, claim} =
             FountRun.ExecutionStore.claim(Fount.Repo, run["id"], "forged-worker", context)

    forged =
      put_in(
        claim,
        [
          "request",
          "semantic_runtime",
          "plan",
          "chunks",
          Access.at(0),
          "spans",
          Access.at(0),
          "text"
        ],
        "INJECTED PERSON"
      )

    assert {:error, :semantic_checkpoint_plan_mismatch} =
             FountRun.SemanticAssessmentHandler.execute(
               forged,
               Keyword.merge(opts, repo: Fount.Repo, actor_context: context)
             )

    refute_receive {:semantic_fixture_request, _}
  end

  test "saved dispatch response survives worker crash without a second model call" do
    Application.put_env(:fount_web, :semantic_assessment,
      mode: :deterministic_fixture,
      client_factory: {FountWeb.SemanticFixtureAdapter, :client, [[capture_to: self()]]}
    )

    assert {:ok, %{project: project}} = create_import("SI02 saved acknowledgement")

    assert {:ok, %{run: run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "saved-ack"})

    context = owner_context(run)
    assert {:ok, opts} = Services.worker_step_opts("test-owner", run["screenplay_id"], run)
    for _ <- 1..2, do: assert({:ok, _} = FountRun.step(Fount.Repo, run["id"], context, opts))

    fault = fn
      :after_provider_response_persisted -> raise "fixture worker crashed after saved response"
      _ -> :ok
    end

    assert_raise RuntimeError, "fixture worker crashed after saved response", fn ->
      FountRun.step(Fount.Repo, run["id"], context, Keyword.put(opts, :fault_injector, fault))
    end

    assert_receive {:semantic_fixture_request, _}

    Ecto.Adapters.SQL.query!(
      Fount.Repo,
      "UPDATE fount_run_steps SET lease_expires_at=now()-interval '1 second' WHERE run_id=$1::text::uuid AND status='running'",
      [run["id"]]
    )

    assert {:ok, _} = FountRun.step(Fount.Repo, run["id"], context, opts)
    refute_receive {:semantic_fixture_request, _}
    complete_semantic_run(run)
  end

  test "explicit omissions persist partial coverage without source mutation", %{conn: conn} do
    Application.put_env(:fount_web, :semantic_assessment,
      mode: :deterministic_fixture,
      client_factory: {FountWeb.SemanticFixtureAdapter, :client, [[omit_payload: true]]}
    )

    assert {:ok, %{project: project, screenplay: source}} = create_import("SI02 partial coverage")

    assert {:ok, %{run: run}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "partial"})

    complete_semantic_run(run)
    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    assert context.semantic.assessment_state == :partial
    assert context.semantic.locations != []
    assert context.semantic.characters != []
    conn = FountWeb.ConnCase.login(conn)

    for section <- ["cast", "locations"] do
      assert {:ok, _view, html} = live(conn, "/p/#{project["key"]}/#{section}")
      assert html =~ "Partial suggestions"
    end

    assert context.semantic.coverage["complete"] == false
    assert context.semantic.coverage["omitted"] != []
    assert context.current.revision.id == source.revision.id
    assert context.current.import.bytes == @source
  end

  test "reconciliation validation failure receives only one bounded repair and retains usage" do
    Application.put_env(:fount_web, :semantic_assessment,
      mode: :deterministic_fixture,
      client_factory:
        {FountWeb.SemanticFixtureAdapter, :client,
         [[invalid_reconciliation: true, capture_to: self()]]}
    )

    assert {:ok, %{project: project, screenplay: source}} =
             create_import("SI02 invalid reconciliation")

    assert {:ok, %{run: run, assessment: assessment}} =
             Launch.assess_project("test-owner", project["id"], %{
               "command_id" => "invalid-reconciliation"
             })

    context = owner_context(run)
    assert {:ok, opts} = Services.worker_step_opts("test-owner", run["screenplay_id"], run)
    for _ <- 1..3, do: assert({:ok, _} = FountRun.step(Fount.Repo, run["id"], context, opts))

    assert {:error, {:invalid_completion, :invalid_reconciliation}} =
             FountRun.step(Fount.Repo, run["id"], context, opts)

    for _ <- 1..3, do: assert_receive({:semantic_fixture_request, _})
    refute_receive {:semantic_fixture_request, _}

    assert {:ok, row} =
             SemanticStore.assessment(Fount.Repo, "test-owner", project["id"], assessment["id"])

    assert row["status"] == "failed"
    assert row["result"] == %{}

    assert {:ok, usage} =
             Ecto.Adapters.SQL.query(
               Fount.Repo,
               "SELECT count(*) FROM fount_run_provider_requests WHERE run_id=$1::text::uuid",
               [run["id"]]
             )

    assert usage.rows == [[3]]
    fixture_service!()

    assert {:ok, %{run: retry}} =
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "retry-failed"})

    complete_semantic_run(retry)
    assert {:ok, current} = ProjectContext.load("test-owner", project["key"])
    assert current.current.revision.id == source.revision.id
  end

  defp create_import(title) do
    Launch.create_project("test-owner", %{
      "title" => title,
      "kind" => "import",
      "source" => @source,
      "filename" => "si02.fountain"
    })
  end

  defp fixture_service! do
    Application.put_env(:fount_web, :semantic_assessment,
      mode: :deterministic_fixture,
      client_factory: {FountWeb.SemanticFixtureAdapter, :client, []}
    )

    assert Services.assessment_service_summary()["configured"] == true
  end

  defp complete_semantic_run(run) do
    context = owner_context(run)
    assert {:ok, opts} = Services.worker_step_opts("test-owner", run["screenplay_id"], run)

    Enum.reduce_while(1..20, nil, fn _, _acc ->
      assert {:ok, _step} = FountRun.step(Fount.Repo, run["id"], context, opts)
      assert {:ok, current} = FountRun.get_run(Fount.Repo, run["id"], context)

      if current["status"] == "completed_nonmutating" do
        {:halt, current}
      else
        {:cont, nil}
      end
    end) || flunk("semantic assessment did not reach completed_nonmutating")
  end

  defp owner_context(run) do
    assert {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])
    context
  end
end
