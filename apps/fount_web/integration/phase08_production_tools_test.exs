defmodule FountWeb.Phase08ProductionToolsIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias FountWeb.{
    Launch,
    ProductionStore,
    ProductionTools,
    ProjectContext,
    SemanticContext,
    SemanticStore
  }

  alias Fount.Writing.{Approval, Authority, Principal}

  test "S01/S02/S03 production tools load only an owner-authorized exact revision", %{conn: conn} do
    {:ok, %{project: project, run: run}} = create_run("inspect")
    assert {:ok, workspace} = ProductionTools.workspace(Fount.Repo, "test-owner", run["id"])
    assert workspace.screenplay.revision.id == get_in(run, ["plan", "base_revision_id"])

    assert {:ok, result} =
             ProductionTools.search(workspace.screenplay, "coffee", %{"limit" => "10"})

    assert result.revision_id == workspace.screenplay.revision.id
    assert result.returned_hit_count > 0
    assert Enum.all?(result.hits, &String.starts_with?(&1.anchor, "node-"))

    assert ProductionTools.character_profiles(workspace.screenplay) != []
    assert ProductionTools.location_profiles(workspace.screenplay) != []
    assert {:error, :not_found} = ProductionTools.workspace(Fount.Repo, "other-owner", run["id"])

    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, _view, html} = live(conn, "/p/#{project["key"]}")
    assert html =~ "Search this screenplay"
    assert html =~ "Current draft"
  end

  test "S04 note candidate persists separately, exact approval advances canon, and changed/deleted targets are explicit" do
    {:ok, %{project: project, run: run}} = create_run("notes")
    {:ok, workspace} = ProductionTools.workspace(Fount.Repo, "test-owner", run["id"])
    base = workspace.screenplay
    action = Enum.find(base.ir.elements, &(&1.type == :action))

    assert {:ok, %{candidate: candidate, note_id: note_id}} =
             ProductionTools.save_note_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               base.revision.id,
               %{
                 "title" => "Continuity",
                 "text" => "Check the coffee maker before accepting changes.",
                 "target" => "element:#{action.id}"
               }
             )

    assert {:ok, unchanged} = Fount.Persistence.load(Fount.Repo, project["key"])
    assert unchanged.revision.id == base.revision.id
    assert unchanged.authored_items == base.authored_items
    assert {:ok, pointer} = ProductionStore.candidate(Fount.Repo, "test-owner", candidate.id)
    assert pointer["resource_id"] == note_id

    assert {:error, :not_found} =
             ProductionStore.candidate(Fount.Repo, "other-owner", candidate.id)

    assert {:ok, accepted} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               candidate.id,
               Fount.ID.v4()
             )

    assert accepted.revision.id != base.revision.id
    assert {:ok, accepted_head} = Fount.Persistence.load(Fount.Repo, project["key"])
    assert get_in(accepted_head.authored_items, [note_id, "value", "text"]) =~ "coffee maker"
    assert [%{id: ^note_id, target_state: "active"}] = ProductionTools.notes(accepted_head)

    assert {:ok, changed, _} =
             Fount.Screenplay.apply(
               accepted_head,
               [Fount.Edit.replace_text(action.id, "MARA moves the coffee maker to the window.")],
               actor: "writer:test-owner"
             )

    assert {:ok, changed_candidate} =
             Fount.Persistence.save_edit_candidate(
               Fount.Repo,
               project["key"],
               changed,
               expected_revision: accepted_head.revision.id,
               operations: [
                 Fount.Edit.replace_text(action.id, "MARA moves the coffee maker to the window.")
               ]
             )

    assert {:ok, _changed_accepted} = accept_direct(changed_candidate, "test-owner")
    assert {:ok, changed_head} = Fount.Persistence.load(Fount.Repo, project["key"])
    assert [%{id: ^note_id, target_state: "stale_changed"}] = ProductionTools.notes(changed_head)

    assert {:ok, removed, _} =
             Fount.Screenplay.apply(
               changed_head,
               [%{"kind" => "delete_elements", "value" => %{"ids" => [action.id]}}],
               actor: "writer:test-owner"
             )

    assert {:ok, removed_candidate} =
             Fount.Persistence.save_edit_candidate(
               Fount.Repo,
               project["key"],
               removed,
               expected_revision: changed_head.revision.id
             )

    assert {:ok, _} = accept_direct(removed_candidate, "test-owner")
    assert {:ok, removed_head} = Fount.Persistence.load(Fount.Repo, project["key"])
    assert [%{id: ^note_id, target_state: "unresolved"}] = ProductionTools.notes(removed_head)

    replacement = Enum.find(removed_head.ir.elements, &(&1.type == :dialogue))

    assert {:ok, %{candidate: remap_candidate}} =
             ProductionTools.save_note_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               removed_head.revision.id,
               %{
                 "id" => note_id,
                 "title" => "Continuity",
                 "text" => "Explicitly remapped after the old target was deleted.",
                 "target" => "screenplay:#{removed_head.id}",
                 "target_override" => "element:#{replacement.id}"
               }
             )

    assert {:ok, remapped} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               remap_candidate.id,
               Fount.ID.v4()
             )

    assert [%{id: ^note_id, target_state: "active", target: %{"id" => replacement_id}}] =
             ProductionTools.notes(remapped)

    assert replacement_id == replacement.id
  end

  test "S04 stale concurrent tool candidates cannot both advance canon" do
    {:ok, %{project: project, run: run}} = create_run("candidate-conflict")
    {:ok, workspace} = ProductionTools.workspace(Fount.Repo, "test-owner", run["id"])
    base = workspace.screenplay

    target = "screenplay:#{base.id}"

    assert {:ok, %{candidate: first}} =
             ProductionTools.save_note_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               base.revision.id,
               %{
                 "title" => "A",
                 "text" => "First candidate",
                 "target" => target
               }
             )

    assert {:ok, %{candidate: second}} =
             ProductionTools.save_note_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               base.revision.id,
               %{
                 "title" => "B",
                 "text" => "Second candidate",
                 "target" => target
               }
             )

    assert {:ok, _} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               first.id,
               Fount.ID.v4()
             )

    assert {:error, :candidate_base_stale} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               second.id,
               Fount.ID.v4()
             )
  end

  test "S02 cast rename is candidate-only and records suggested mentions without accepting them" do
    {:ok, %{project: project, run: run}} = create_run("cast")
    {:ok, workspace} = ProductionTools.workspace(Fount.Repo, "test-owner", run["id"])
    [character | _] = ProductionTools.character_profiles(workspace.screenplay)

    assert {:ok, %{candidate: candidate, plan: plan}} =
             ProductionTools.save_cast_rename_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               workspace.screenplay.revision.id,
               character.id,
               "RENAMED"
             )

    assert is_list(plan.review)
    assert {:ok, head} = Fount.Persistence.load(Fount.Repo, project["key"])
    refute Enum.any?(Map.values(head.cast), &(&1.display_name == "RENAMED"))

    assert {:ok, _accepted} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               candidate.id,
               Fount.ID.v4()
             )

    assert {:ok, renamed} = Fount.Persistence.load(Fount.Repo, project["key"])
    assert renamed.cast[character.id].display_name == "RENAMED"

    assert Enum.any?(
             renamed.ir.elements,
             &(&1.type == :character and String.starts_with?(&1.text, "RENAMED"))
           )
  end

  test "S05 table reads persist exact packet/revision state, reactions, conflicts and owner isolation" do
    {:ok, %{project: project, run: run}} = create_run("table-read")
    {:ok, workspace} = ProductionTools.workspace(Fount.Repo, "test-owner", run["id"])

    assert {:ok, read} =
             ProductionTools.create_table_read(
               Fount.Repo,
               "test-owner",
               workspace,
               %{"whole_screenplay" => true}
             )

    assert read["revision_id"] == workspace.screenplay.revision.id
    assert read["packet"]["kind"] == "fount.human_table_read"
    assert read["packet"]["turns"] != []

    assert get_in(read, ["packet", "claims", "synthesized_voice_is_performance_validation"]) ==
             false

    assert {:ok, state} =
             ProductionTools.update_table_read(Fount.Repo, "test-owner", read["id"], 1, %{
               bookmark_index: 1,
               elapsed_ms: 1_250,
               scroll_mode: "paused"
             })

    assert state["version"] == 2
    assert state["bookmark_index"] == 1

    assert {:error, :bookmark_out_of_range} =
             ProductionTools.update_table_read(
               Fount.Repo,
               "test-owner",
               read["id"],
               state["version"],
               %{
                 bookmark_index: 99_999,
                 elapsed_ms: 1_500,
                 scroll_mode: "paused"
               }
             )

    assert {:error, {:stale_table_read, current}} =
             ProductionTools.update_table_read(Fount.Repo, "test-owner", read["id"], 1, %{
               bookmark_index: 0,
               elapsed_ms: 0,
               scroll_mode: "manual"
             })

    assert current["version"] == 2

    assert {:ok, reacted} =
             ProductionTools.record_table_reaction(
               Fount.Repo,
               "test-owner",
               read["id"],
               state["version"],
               %{"reader_id" => "reader-a", "reaction" => "The handoff landed clearly."}
             )

    assert [reaction] = reacted["packet"]["reactions"]
    assert reaction["observer"] == "human"
    assert reaction["source"]["revision_id"] == workspace.screenplay.revision.id

    assert {:error, :not_found} =
             ProductionStore.table_read(Fount.Repo, "other-owner", read["id"])

    assert [%{"id" => id}] = ProductionTools.table_reads(Fount.Repo, "test-owner", project["id"])
    assert id == read["id"]
  end

  test "S05 a same-owner read from another project cannot be selected", %{conn: conn} do
    {:ok, %{run: first_run}} = create_run("read-first")
    {:ok, workspace} = ProductionTools.workspace(Fount.Repo, "test-owner", first_run["id"])

    {:ok, read} =
      ProductionTools.create_table_read(Fount.Repo, "test-owner", workspace, %{
        "whole_screenplay" => true
      })

    {:ok, %{project: other_project}} = create_run("read-other")
    conn = FountWeb.ConnCase.login(conn)
    {:ok, view, _html} = live(conn, "/p/#{other_project["key"]}/read")
    html = render_click(view, "select_table_read", %{"id" => read["id"]})
    assert html =~ "no longer available"
    refute has_element?(view, "#table-read-workspace")
  end

  test "S06 usefulness persistence keeps human response separate from engineering facts, kept-original is valid, export/delete are owner-scoped",
       %{conn: conn} do
    {:ok, %{project: project, run: run}} = create_run("usefulness")
    {:ok, workspace} = ProductionTools.workspace(Fount.Repo, "test-owner", run["id"])

    assert {:ok, row} =
             ProductionTools.create_usefulness(Fount.Repo, "test-owner", workspace, %{
               "task_id" => "dialogue-pass-1",
               "condition" => "fount_assisted",
               "outcome" => "neutral",
               "kept_original" => "true",
               "preference" => "original",
               "notes" => "The existing line was clearer.",
               "dimensions" => %{
                 "task_completion" => "completed with original",
                 "agency" => "high",
                 "rejection_time_ms" => "375",
                 "unsupported" => "discard me"
               }
             })

    assert get_in(row, ["record", "human_response", "kept_original"]) == true

    assert get_in(row, ["record", "human_response", "dimensions"]) == %{
             "task_completion" => "completed with original",
             "agency" => "high",
             "rejection_time_ms" => 375
           }

    assert get_in(row, ["record", "engineering", "resource_usage", "run_id"]) == run["id"]

    assert {:ok, report} =
             ProductionTools.usefulness_report(Fount.Repo, "test-owner", project["id"])

    assert report["sample_size"] == 1
    assert report["claims"]["automatic_winner"] == false
    assert report["sample_label"] =~ "no representativeness claim"

    assert {:error, :not_found} =
             ProductionTools.delete_usefulness(Fount.Repo, "other-owner", row["id"])

    conn = FountWeb.ConnCase.login(conn)
    response = get(conn, "/p/#{project["key"]}/feedback/export.json")
    assert response.status == 200
    assert response.resp_body =~ "fount.writer_usefulness_export"
    assert response.resp_body =~ "kept_original"

    assert :ok = ProductionTools.delete_usefulness(Fount.Repo, "test-owner", row["id"])

    assert {:ok, empty_report} =
             ProductionTools.usefulness_report(Fount.Repo, "test-owner", project["id"])

    assert empty_report["sample_size"] == 0
  end

  test "S07 project dashboard exposes only supplied synopsis/thumbnail data, actual import fidelity and bounded activity" do
    assert {:ok, %{project: project, run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Phase 08 dashboard",
               "key" => "phase08-dashboard",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "phase08.fountain",
               "synopsis" => "Supplied by the writer.",
               "thumbnail_ref" => "writer://board/thumbnail-1"
             })

    projects = FountWeb.Store.list_projects(Fount.Repo, "test-owner", limit: 24)
    runs = FountWeb.WorkflowManagement.list_owner_runs(Fount.Repo, "test-owner", limit: 50)
    [card] = ProductionTools.project_cards(Fount.Repo, "test-owner", projects, runs)

    assert card.project["id"] == project["id"]
    assert card.project["synopsis"] == "Supplied by the writer."
    assert card.project["thumbnail_ref"] == "writer://board/thumbnail-1"
    assert card.import_fidelity["format"] == "fountain"
    assert card.import_fidelity["loss_count"] == 0
    assert card.import_fidelity["original_bytes_preserved_when_unchanged"] == true
    assert card.scene_count > 0
    assert card.latest_run["id"] == run["id"]
    assert length(card.recent_activity) <= 6
    assert FountWeb.Store.list_projects(Fount.Repo, "other-owner", limit: 24) == []
  end

  test "S07 FDX imports retain actual adapter fidelity and unchanged original bytes; unsupported formats fail closed" do
    fdx =
      "<FinalDraft><Content><Paragraph Type=\"Scene Heading\"><Text>INT. FDX ROOM - DAY</Text></Paragraph><Paragraph Type=\"Action\"><Text>Mara checks the imported page.</Text></Paragraph><Paragraph Type=\"Character\"><Text>MARA</Text></Paragraph><Paragraph Type=\"Dialogue\"><Text>The import is visible.</Text></Paragraph></Content><TagData/></FinalDraft>"

    assert {:ok, %{project: project}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Phase 08 FDX",
               "key" => "phase08-fdx",
               "journey" => "opening",
               "source" => fdx,
               "filename" => "phase08.fdx"
             })

    assert project["import_format"] == "fdx"
    assert is_list(project["import_fidelity"]["adapter_losses"])

    assert project["import_fidelity"]["loss_count"] ==
             length(project["import_fidelity"]["adapter_losses"])

    assert project["import_fidelity"]["original_bytes_preserved_when_unchanged"] == true

    assert {:ok, head} = Fount.Persistence.load(Fount.Repo, project["key"])
    assert {:ok, export} = Fount.Screenplay.to_fdx(head)
    assert export.data == fdx

    assert {:error, :unsupported_screenplay_format} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Unsupported",
               "key" => "phase08-unsupported",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "screenplay.txt"
             })
  end

  test "S04/S05 owner-scoped JSON exports retain exact revision identity", %{conn: conn} do
    {:ok, %{project: project, run: run}} = create_run("exports")
    {:ok, workspace} = ProductionTools.workspace(Fount.Repo, "test-owner", run["id"])
    action = Enum.find(workspace.screenplay.ir.elements, &(&1.type == :action))

    assert {:ok, %{candidate: candidate}} =
             ProductionTools.save_note_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               workspace.screenplay.revision.id,
               %{"text" => "Export me", "title" => "Export", "target" => "element:#{action.id}"}
             )

    assert {:ok, accepted} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               candidate.id,
               Fount.ID.v4()
             )

    token = "accepted:#{accepted.revision.id}"

    assert {:ok, accepted_workspace} =
             ProductionTools.workspace(Fount.Repo, "test-owner", run["id"], token)

    assert accepted_workspace.editable?

    assert {:ok, read} =
             ProductionTools.create_table_read(Fount.Repo, "test-owner", accepted_workspace, %{
               "whole_screenplay" => true
             })

    conn = FountWeb.ConnCase.login(conn)
    notes = get(conn, "/p/#{project["key"]}/notes/export.json")
    assert notes.status == 200
    assert notes.resp_body =~ accepted.revision.id
    assert notes.resp_body =~ "Export me"

    read_export = get(conn, "/p/#{project["key"]}/table-reads/read-#{read["id"]}/export.json")
    assert read_export.status == 200
    assert read_export.resp_body =~ accepted.revision.id
    assert read_export.resp_body =~ read["packet_id"]
  end

  defp create_run(suffix) do
    assert {:ok, %{project: project}} =
             Launch.create_project("test-owner", %{
               "title" => "Phase 08 #{suffix}",
               "kind" => "import",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "phase08.fountain"
             })

    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    [source_character | _] = context.semantic.characters

    assert {:ok, _} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               project["id"],
               context.semantic.assessment_id,
               %{
                 "action" => "confirm",
                 "target_handle_id" => source_character.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => context.semantic.version,
                 "command_id" => "phase08-confirm-#{suffix}",
                 "actor" => "human:test-owner"
               }
             )

    assert {:ok, reviewed} = ProjectContext.load("test-owner", project["key"])

    source_character =
      Enum.find(
        reviewed.semantic.characters,
        &(&1.semantic_handle_id == source_character.semantic_handle_id)
      )

    assert {:ok, proposal} =
             SemanticContext.save_character_promotion_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               reviewed.current.revision.id,
               reviewed.semantic,
               source_character.semantic_handle_id
             )

    assert {:ok, _} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               proposal.candidate.id,
               Fount.ID.v4()
             )

    Launch.create_from_project("test-owner", project["id"], %{
      "journey" => "opening",
      "command_id" => "phase08-run-#{suffix}-#{System.unique_integer([:positive])}"
    })
  end

  defp accept_direct(candidate, owner) do
    with {:ok, principal} <- Principal.new(:human, owner),
         {:ok, stored} <- Fount.Persistence.candidate(Fount.Repo, candidate.id),
         {:ok, authority} <- Authority.new(principal, stored["screenplay"].id, [:approve]),
         {:ok, approval} <- Approval.direct(stored, principal, Fount.ID.v4()) do
      Fount.Persistence.accept_candidate(Fount.Repo, candidate.id,
        approval: approval,
        authority: authority
      )
    end
  end
end
