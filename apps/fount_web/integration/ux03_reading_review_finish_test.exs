defmodule FountWeb.UX03ReadingReviewFinishIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias FountWeb.{ProductionStore, ProductionTools, ProjectContext, ReadingArtifacts, Store}

  test "UX03 Reading is calm by default and literal search stays bound to the selected revision",
       %{conn: conn} do
    assert {:ok, %{access: access}} = launch("reading")
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, view, html} = live(conn, "/p/#{access["key"]}")
    assert html =~ "Responsive reading view"
    assert html =~ ">Notes<"
    assert html =~ ">Export<"
    refute html =~ "context-help"
    refute html =~ "Settings"

    html =
      render_submit(view, "search_script", %{
        "search" => %{
          "query" => "coffee maker",
          "scene_id" => "",
          "character_id" => "",
          "location" => "",
          "element_type" => "",
          "limit" => "50"
        }
      })

    assert html =~ "literal phrase search only"
    assert html =~ "coffee maker"
    assert html =~ "result(s)"
  end

  test "UX03 named note remap search is exact and note review is versioned independently of acceptance" do
    assert {:ok, %{project: project, access: access}} = launch("note-review")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])
    [scene | _] = current.ir.scenes

    assert {:ok, note_result} =
             ProductionTools.save_note_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               current.revision.id,
               %{
                 "target" => "scene:#{scene.id}",
                 "title" => "Protect the silence",
                 "text" => "Hold the answer until the elevator opens."
               }
             )

    assert {:ok, _} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               note_result.candidate.id,
               Fount.ID.v4()
             )

    assert {:ok, accepted} = Fount.Persistence.load(Fount.Repo, access["key"])
    accepted_revision = accepted.revision.id

    assert {:ok, results} = ProductionTools.target_search(accepted, "coffee maker", 80)
    assert results != []
    assert Enum.all?(results, &String.starts_with?(&1.value, "element:"))

    attrs = %{
      "response" => "addressed",
      "comment" => "Handled in the current pages.",
      "version" => "0"
    }

    assert {:ok, first} =
             ProductionTools.save_note_review(
               Fount.Repo,
               "test-owner",
               project,
               note_result.note_id,
               accepted_revision,
               accepted_revision,
               attrs
             )

    assert first["version"] == 1
    assert first["response"] == "addressed"

    assert {:ok, second} =
             ProductionTools.save_note_review(
               Fount.Repo,
               "test-owner",
               project,
               note_result.note_id,
               accepted_revision,
               accepted_revision,
               %{attrs | "response" => "deferred", "version" => "1"}
             )

    assert second["version"] == 2

    assert {:error, {:stale_note_review, stale}} =
             ProductionTools.save_note_review(
               Fount.Repo,
               "test-owner",
               project,
               note_result.note_id,
               accepted_revision,
               accepted_revision,
               %{attrs | "version" => "1"}
             )

    assert stale["version"] == 2

    assert {:ok, nil} =
             ProductionTools.save_note_review(
               Fount.Repo,
               "test-owner",
               project,
               note_result.note_id,
               accepted_revision,
               accepted_revision,
               %{"response" => "open", "comment" => "", "version" => "2"}
             )

    refute Enum.any?(
             ProductionTools.note_reviews(
               Fount.Repo,
               "test-owner",
               project["id"],
               note_result.note_id
             ),
             &(&1["reviewed_revision_id"] == accepted_revision)
           )

    assert Fount.Persistence.load(Fount.Repo, access["key"]) |> elem(1) |> then(& &1.revision.id) ==
             accepted_revision
  end

  test "UX03 manual table read stores human navigation without creating a synthetic Run" do
    assert {:ok, %{project: project, access: access}} = launch("manual-read")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])
    before_runs = Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 50)

    assert {:ok, read} =
             ProductionTools.create_project_table_read(
               Fount.Repo,
               "test-owner",
               project,
               current,
               %{"whole_screenplay" => true},
               %{"title" => "Act One read"}
             )

    assert get_in(read, ["packet", "display_title"]) == "Act One read"
    assert is_nil(read["run_id"])
    assert get_in(read, ["packet", "claims", "audience_response_measured"]) == false

    assert {:ok, saved} =
             ProductionTools.update_table_read(
               Fount.Repo,
               "test-owner",
               read["id"],
               read["version"],
               %{bookmark_index: 1, elapsed_ms: 3_500, scroll_mode: "paused"}
             )

    assert saved["bookmark_index"] == 1
    assert saved["elapsed_ms"] == 3_500

    assert {:ok, reacted} =
             ProductionTools.record_table_reaction(
               Fount.Repo,
               "test-owner",
               saved["id"],
               saved["version"],
               %{
                 "observer" => "human",
                 "reader_id" => "Mara reader",
                 "reaction" => "Pause landed."
               }
             )

    assert length(reacted["packet"]["reactions"]) == 1

    assert length(Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 50)) ==
             length(before_runs)
  end

  test "UX03 cast facts keep literal cues distinct from confirmed people and prose presence" do
    assert {:ok, %{access: access}} = launch("cast")
    assert {:ok, context} = ProjectContext.load("test-owner", access["key"])
    [character | _] = context.semantic.characters

    assert character.dialogue_block_count > 0
    assert character.review_state == "unreviewed"
    assert character.speaking_occurrences > 0
    assert character.presence_occurrences == 0
    assert character.mention_occurrences == 0
    assert character.core_character_id == nil
    assert context.current.cast == %{}
  end

  test "UX03 deterministic Fountain and FDX project artifacts are exact owner-bound sources" do
    assert {:ok, %{project: project, access: access}} = launch("exports")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])

    assert {:ok, fountain} =
             ReadingArtifacts.build_source(Fount.Repo, "test-owner", project, current, "fountain")

    assert fountain["state"] == "ready"
    assert fountain["revision_id"] == current.revision.id

    assert {:ok, fdx} =
             ReadingArtifacts.build_source(Fount.Repo, "test-owner", project, current, "fdx")

    assert fdx["state"] == "ready"
    assert fdx["output_checksum"] != fountain["output_checksum"]

    assert {:ok, original} =
             ProductionStore.project_artifact_by_ref(
               Fount.Repo,
               "test-owner",
               project["id"],
               ReadingArtifacts.artifact_ref([fountain], fountain)
             )

    assert original["id"] == fountain["id"]
    assert original["kind"] == "fountain"

    assert {:error, :not_found} =
             ProductionStore.project_artifact_by_ref(
               Fount.Repo,
               "other-owner",
               project["id"],
               "artifact-#{fountain["id"]}"
             )
  end

  test "UX03 notes memo uses verbatim selected notes and actual saved responses only" do
    assert {:ok, %{project: project, access: access}} = launch("memo")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])
    [scene | _] = current.ir.scenes

    assert {:ok, result} =
             ProductionTools.save_note_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               current.revision.id,
               %{
                 "target" => "scene:#{scene.id}",
                 "title" => "Studio note",
                 "text" => "Keep this exact wording."
               }
             )

    assert {:ok, _} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               result.candidate.id,
               Fount.ID.v4()
             )

    assert {:ok, accepted} = Fount.Persistence.load(Fount.Repo, access["key"])
    [note] = ProductionTools.notes(accepted)

    assert {:ok, response} =
             ProductionTools.save_note_review(
               Fount.Repo,
               "test-owner",
               project,
               note.id,
               accepted.revision.id,
               accepted.revision.id,
               %{"response" => "not_addressed", "comment" => "Still open.", "version" => "0"}
             )

    assert {:ok, artifact} =
             ReadingArtifacts.build_notes_memo(
               Fount.Repo,
               "test-owner",
               project,
               accepted,
               [note],
               %{
                 "from" => "A. Reader",
                 "to" => "Writer",
                 "include_responses" => true,
                 "responses" => %{note.id => response}
               }
             )

    path =
      Path.join(Application.fetch_env!(:fount_web, :artifact_root), artifact["output_location"])

    body = File.read!(path)
    assert body =~ "Keep this exact wording."
    assert body =~ "not addressed"
    assert body =~ "Still open."
    refute body =~ accepted.revision.id
    refute body =~ "coverage score"
  end

  test "UX03 project destinations are direct, discoverable and do not restore the old tools route",
       %{conn: conn} do
    assert {:ok, %{access: access}} = launch("destinations")
    conn = FountWeb.ConnCase.login(conn)

    for {path, text} <- [
          {"notes", "Notes"},
          {"cast", "Cast"},
          {"locations", "Locations"},
          {"read", "Table read"},
          {"feedback", "Feedback"},
          {"exports", "Exports"}
        ] do
      assert {:ok, _view, html} = live(conn, "/p/#{access["key"]}/#{path}")
      assert html =~ Phoenix.HTML.html_escape(text) |> Phoenix.HTML.safe_to_string()
    end
  end

  test "UX03 reviewer saves reject a different owner before persisting any response" do
    assert {:ok, %{project: project, access: access}} = launch("owner-review")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])

    assert {:error, :not_found} =
             ProductionTools.save_note_review(
               Fount.Repo,
               "other-owner",
               project,
               "missing-note",
               current.revision.id,
               current.revision.id,
               %{"response" => "addressed"}
             )
  end

  test "UX03 reader record constraints reject cross-owner and cross-screenplay identities" do
    assert {:ok, %{project: project, access: access}} = launch("bindings")
    assert {:ok, %{access: other_access}} = launch("other-bindings")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert {:ok, other} = Fount.Persistence.load(Fount.Repo, other_access["key"])

    attrs = %{
      owner_id: "test-owner",
      project_id: project["id"],
      screenplay_id: current.id,
      revision_id: current.revision.id,
      kind: "fountain",
      source_label: "Current draft",
      filename: "bound.fountain"
    }

    for invalid <- [
          Map.put(attrs, :owner_id, "other-owner"),
          Map.put(attrs, :revision_id, other.revision.id)
        ] do
      assert {:error, _} =
               Fount.Repo.transaction(fn ->
                 case ProductionStore.create_project_artifact(Fount.Repo, invalid) do
                   {:error, reason} -> Fount.Repo.rollback(reason)
                   value -> value
                 end
               end)
    end
  end

  test "UX03 actual PDF metadata feeds dated checks, and failed builds preserve source and remain retryable" do
    assert {:ok, %{project: project, access: access}} = launch("pdf-runtime")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])

    assert {:error, message} =
             ReadingArtifacts.build_source(Fount.Repo, "test-owner", project, current, "pdf",
               pdf_options: [renderer: "/nonexistent/ux03-renderer"]
             )

    assert message =~ "renderer is not installed"

    assert {:ok, artifact} =
             ReadingArtifacts.build_source(Fount.Repo, "test-owner", project, current, "pdf")

    assert artifact["state"] == "ready"
    assert artifact["revision_id"] == current.revision.id

    path =
      Path.join(Application.fetch_env!(:fount_web, :artifact_root), artifact["output_location"])

    assert "%PDF-" <> _ = File.read!(path)
    metadata = artifact["metadata"]

    report = %{
      source_revision: artifact["revision_id"],
      pages: metadata["pages"],
      blank_pages: metadata["blank_pages"],
      page_size: :us_letter,
      courier_prime?: metadata["courier_prime"]
    }

    assert {:ok, profile} = FountWorkshop.Submission.profile(:nicholl_2026_27)
    checks = FountWorkshop.Submission.check(current, report, profile)
    assert checks.checked_on == ~D[2026-09-23]
    refute :pdf_source_revision_mismatch in checks.mechanical_problems
    assert :authorship_rights_and_current_rules in checks.requires_writer_review
    assert {:ok, unchanged} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert unchanged.revision.id == current.revision.id
  end

  test "UX03 an altered in-memory source cannot borrow a persisted revision for export or reading" do
    assert {:ok, %{project: project, access: access}} = launch("forged-source")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])
    [action | _] = Fount.Query.elements(current, :action)

    assert {:ok, changed} =
             Fount.Screenplay.apply(
               current,
               Fount.Edit.replace_text(action.id, "Different unpersisted writing.")
             )

    forged = %{changed | revision: current.revision}

    assert {:error, :source_content_mismatch} =
             ReadingArtifacts.build_source(Fount.Repo, "test-owner", project, forged, "fountain")

    assert {:error, :source_content_mismatch} =
             ProductionTools.create_project_table_read(
               Fount.Repo,
               "test-owner",
               project,
               forged,
               %{"whole_screenplay" => true}
             )
  end

  defp launch(suffix) do
    FountWeb.Launch.create("test-owner", %{
      "title" => "UX03 #{suffix}",
      "key" => "ux03-#{suffix}-#{System.unique_integer([:positive])}",
      "journey" => "opening",
      "source" => FountWeb.Journeys.fixture_fountain(),
      "filename" => "ux03.fountain"
    })
  end
end
