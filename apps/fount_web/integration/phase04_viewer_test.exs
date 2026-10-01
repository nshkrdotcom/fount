defmodule FountWeb.Phase04ViewerIntegrationTest do
  use FountWeb.ConnCase, async: false

  test "U08 named task source loads the exact owner-authorized base and keeps machine identity technical", %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("test-owner", "phase04-viewer-base")
    conn = FountWeb.ConnCase.login(conn)

    path = "/p/#{access["key"]}/source/#{access["display_key"]}"
    assert {:ok, _view, html} = live(conn, path)
    assert html =~ "Task base"
    assert html =~ "exact saved task source"
    assert html =~ "Technical details"
    assert html =~ get_in(run, ["plan", "base_revision_id"])

    arbitrary = Fount.ID.v4()
    assert {:ok, view, _html} = live(conn, path)
    stale_html = render_patch(view, path <> "?view=accepted:#{arbitrary}")
    assert stale_html =~ "stale or no longer bound"
  end

  test "U08 task source cannot cross the owner boundary", %{conn: conn} do
    {:ok, %{access: access}} = launch("test-owner", "phase04-private-viewer")
    outsider = Phoenix.ConnTest.init_test_session(conn, %{owner_id: "other-owner"})
    path = "/p/#{access["key"]}/source/#{access["display_key"]}"

    assert {:error, {kind, %{to: destination}}} = live(outsider, path)
    assert kind in [:redirect, :live_redirect]
    assert destination == "/p/#{access["key"]}"
  end

  test "viewer inspection preserves canon and excludes cross-screenplay candidates" do
    {:ok, %{run: run, access: access}} = launch("test-owner", "phase04-inspection")
    {:ok, %{run: foreign_run, access: foreign_access}} = launch("other-owner", "phase04-foreign")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, access["key"])
    {:ok, foreign} = Fount.Persistence.load(Fount.Repo, foreign_access["key"])
    [action | _] = Fount.Query.elements(base, :action)

    {:ok, changed} = Fount.Screenplay.apply(base, Fount.Edit.replace_text(action.id, "Local candidate text."))
    {:ok, local_candidate} = Fount.Persistence.save_edit_candidate(Fount.Repo, access["key"], changed)

    [foreign_action | _] = Fount.Query.elements(foreign, :action)
    {:ok, foreign_changed} = Fount.Screenplay.apply(foreign, Fount.Edit.replace_text(foreign_action.id, "Foreign secret text."))
    {:ok, foreign_candidate} = Fount.Persistence.save_edit_candidate(Fount.Repo, foreign_access["key"], foreign_changed)

    progress = %{"steps" => [%{"result" => %{"candidate_ids" => [local_candidate.id, foreign_candidate.id]}}]}
    assert {:ok, options} = FountWeb.ScreenplayViews.options(Fount.Repo, access, run, progress)
    assert Enum.any?(options, &(&1[:candidate_id] == local_candidate.id))
    refute Enum.any?(options, &(&1[:candidate_id] == foreign_candidate.id))

    local = Enum.find(options, &(&1[:candidate_id] == local_candidate.id))
    assert {:ok, %{screenplay: loaded}} =
             FountWeb.ScreenplayViews.load(Fount.Repo, access, run, progress, local.display_ref)
    assert loaded.revision.id == changed.revision.id

    foreign_token = "candidate:#{foreign_candidate.id}:#{foreign_changed.revision.id}"
    assert {:error, :stale_or_unbound_revision} =
             FountWeb.ScreenplayViews.load(Fount.Repo, access, run, progress, foreign_token)

    assert {:error, :stale_or_unbound_revision} =
             FountWeb.ScreenplayViews.load(
               Fount.Repo,
               access,
               run,
               progress,
               "accepted:" <> foreign_run["plan"]["base_revision_id"]
             )

    assert {:ok, canonical} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert canonical.revision.id == base.revision.id
  end

  defp launch(owner, key) do
    FountWeb.Launch.create(owner, %{
      "title" => "Phase 04 #{key}",
      "key" => key,
      "journey" => "opening",
      "source" => FountWeb.Journeys.fixture_fountain()
    })
  end
end
