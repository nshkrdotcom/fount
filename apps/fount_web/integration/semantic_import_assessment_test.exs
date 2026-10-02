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
             Launch.assess_project("test-owner", project["id"], %{"command_id" => "disabled-command"})

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
    assert length(Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20)) == 1

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

    mira = Enum.find(semantic.characters, &(String.contains?(&1.display_name, "MIRA VALE")))
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

    assert {:ok, %{run: first_run}} = Launch.assess_project("test-owner", project["id"], %{"command_id" => "assessment-a"})
    _ = complete_semantic_run(first_run)
    assert {:ok, first} = ProjectContext.load("test-owner", project["key"])

    mira = Enum.find(first.semantic.characters, &(String.contains?(&1.display_name, "MIRA VALE")))
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

    runs_before_reassessment = Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 20)
    assert length(runs_before_reassessment) == 1

    assert {:ok, %{run: second_run}} = Launch.assess_project("test-owner", project["id"], %{"command_id" => "assessment-b"})
    _ = complete_semantic_run(second_run)

    assert {:ok, current} = ProjectContext.load("test-owner", project["key"])
    mira_after = Enum.find(current.semantic.characters, &(&1.semantic_handle_id == mira.semantic_handle_id))
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

    assert saved_read["packet"]["semantic_roster_claim"] =~ "source cue/dialogue text is unchanged"
    assert Enum.any?(saved_read["packet"]["semantic_roster"], &(&1["handle_id"] == mira.semantic_handle_id))
    assert Enum.all?(saved_read["packet"]["turns"], &is_binary(&1["cue"]))
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
