defmodule FountWeb.UX03ReadingReviewFinishIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias FountWeb.{ProductionStore, ProductionTools, ReadingArtifacts, Store}

  test "UX03 Reading is calm by default and literal search stays bound to the selected revision", %{conn: conn} do
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

    attrs = %{"response" => "addressed", "comment" => "Handled in the current pages.", "version" => "0"}

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
             ProductionTools.note_reviews(Fount.Repo, "test-owner", project["id"], note_result.note_id),
             &(&1["reviewed_revision_id"] == accepted_revision)
           )

    assert Fount.Persistence.load(Fount.Repo, access["key"]) |> elem(1) |> then(& &1.revision.id) == accepted_revision
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
               %{"observer" => "human", "reader_id" => "Mara reader", "reaction" => "Pause landed."}
             )

    assert length(reacted["packet"]["reactions"]) == 1
    assert length(Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 50)) == length(before_runs)
  end

  test "UX03 cast facts and rename preview separate confirmed cue edits from suggested prose review" do
    assert {:ok, %{access: access}} = launch("cast")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])
    [character | _] = ProductionTools.character_profiles(current)

    assert character.dialogue_block_count > 0
    assert {:ok, plan} = ProductionTools.cast_rename_preview(current, character.id, "NEW NAME")
    assert is_list(plan.cue_operations)
    assert is_list(plan.review)
  end

  test "UX03 deterministic Fountain and FDX project artifacts are exact owner-bound sources" do
    assert {:ok, %{project: project, access: access}} = launch("exports")
    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])

    assert {:ok, fountain} =
             ReadingArtifacts.build_source(Fount.Repo, "test-owner", project, current, "fountain")

    assert fountain["state"] == "ready"
    assert fountain["revision_id"] == current.revision.id

    assert {:ok, fdx} = ReadingArtifacts.build_source(Fount.Repo, "test-owner", project, current, "fdx")
    assert fdx["state"] == "ready"
    assert fdx["output_checksum"] != fountain["output_checksum"]

    assert {:error, :not_found} =
             ProductionStore.project_artifact_by_ref(
               Fount.Repo,
               "other-owner",
               project["id"],
               "artifact-1"
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
               %{"target" => "scene:#{scene.id}", "title" => "Studio note", "text" => "Keep this exact wording."}
             )

    assert {:ok, _} =
             ProductionTools.accept_tool_candidate(Fount.Repo, "test-owner", result.candidate.id, Fount.ID.v4())

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

    path = Path.join(Application.fetch_env!(:fount_web, :artifact_root), artifact["output_location"])
    body = File.read!(path)
    assert body =~ "Keep this exact wording."
    assert body =~ "not addressed"
    assert body =~ "Still open."
    refute body =~ accepted.revision.id
    refute body =~ "coverage score"
  end

  test "UX03 project destinations are direct, discoverable and do not restore the old tools route", %{conn: conn} do
    assert {:ok, %{access: access}} = launch("destinations")
    conn = FountWeb.ConnCase.login(conn)

    for {path, text} <- [
          {"notes", "Notes"},
          {"cast", "Cast & locations"},
          {"read", "Table read"},
          {"feedback", "Feedback"},
          {"exports", "Exports"}
        ] do
      assert {:ok, _view, html} = live(conn, "/p/#{access["key"]}/#{path}")
      assert html =~ text
    end
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
