defmodule FountWeb.Phase04ViewerIntegrationTest do
  use FountWeb.ConnCase, async: false

  test "U08 owner-authorized viewer loads exact Run base and rejects arbitrary/stale revision tokens",
       %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, %{run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Phase 04 viewer",
               "key" => "phase04-viewer-base",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain()
             })

    base_revision = get_in(run, ["plan", "base_revision_id"])
    assert {:ok, _view, html} = live(conn, "/runs/#{run["id"]}/viewer")
    assert html =~ "Screenplay reader"
    assert html =~ base_revision
    assert html =~ "Run base"
    assert html =~ "No Run-bound candidate is currently available"

    arbitrary = Fount.ID.v4()

    assert {:ok, _view, stale_html} =
             live(conn, "/runs/#{run["id"]}/viewer?view=accepted:#{arbitrary}")

    assert stale_html =~ "stale or is not bound to this Run"
    assert stale_html =~ base_revision
  end

  test "U08 viewer cannot cross owner boundary", %{conn: conn} do
    assert {:ok, %{run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Private viewer",
               "key" => "phase04-private-viewer",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain()
             })

    outsider = Phoenix.ConnTest.init_test_session(conn, %{owner_id: "other-owner"})
    assert {:error, {kind, %{to: "/login"}}} = live(outsider, "/runs/#{run["id"]}/viewer")
    assert kind in [:redirect, :live_redirect]
  end

  test "authenticated owner cannot load another owner's Run or revision query", %{conn: conn} do
    {:ok, %{run: foreign_run}} = launch("other-owner", "foreign-run")
    conn = FountWeb.ConnCase.login(conn)
    token = "base:" <> foreign_run["plan"]["base_revision_id"]

    assert {:error, {:redirect, %{to: "/"}}} =
             live(conn, "/runs/#{foreign_run["id"]}/viewer?view=#{token}")
  end

  test "viewer inspection preserves canon, rejects cross-screenplay candidates and never dispatches providers",
       %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("test-owner", "inspection")
    {:ok, %{run: foreign_run}} = launch("other-owner", "foreign-candidate")
    {:ok, base} = Fount.Persistence.load(Fount.Repo, "inspection")
    {:ok, foreign} = Fount.Persistence.load(Fount.Repo, "foreign-candidate")
    [action | _] = Fount.Query.elements(base, :action)

    {:ok, changed} =
      Fount.Screenplay.apply(base, Fount.Edit.replace_text(action.id, "Local candidate text."))

    {:ok, local_candidate} =
      Fount.Persistence.save_edit_candidate(Fount.Repo, "inspection", changed)

    [foreign_action | _] = Fount.Query.elements(foreign, :action)

    {:ok, foreign_changed} =
      Fount.Screenplay.apply(
        foreign,
        Fount.Edit.replace_text(foreign_action.id, "Foreign secret text.")
      )

    {:ok, foreign_candidate} =
      Fount.Persistence.save_edit_candidate(Fount.Repo, "foreign-candidate", foreign_changed)

    progress = %{
      "steps" => [
        %{"result" => %{"candidate_ids" => [local_candidate.id, foreign_candidate.id]}}
      ]
    }

    {:ok, options} = FountWeb.ScreenplayViews.options(Fount.Repo, access, run, progress)
    assert Enum.any?(options, &(&1[:candidate_id] == local_candidate.id))
    refute Enum.any?(options, &(&1[:candidate_id] == foreign_candidate.id))

    local_token =
      FountWeb.ScreenplayViews.token(%{
        kind: :candidate,
        candidate_id: local_candidate.id,
        revision_id: changed.revision.id
      })

    foreign_token =
      FountWeb.ScreenplayViews.token(%{
        kind: :candidate,
        candidate_id: foreign_candidate.id,
        revision_id: foreign_changed.revision.id
      })

    assert {:ok, %{screenplay: loaded_candidate}} =
             FountWeb.ScreenplayViews.load(Fount.Repo, access, run, progress, local_token)

    assert loaded_candidate.revision.id == changed.revision.id

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

    assert {:error, :stale_or_unbound_revision} =
             FountWeb.ScreenplayViews.load(
               Fount.Repo,
               access,
               run,
               progress,
               "base:" <> changed.revision.id
             )

    conn = FountWeb.ConnCase.login(conn)
    modules = [Inference, Fount.Observe, Fount.Observe.Providers.SystemOne]

    for module <- modules do
      Code.ensure_loaded!(module)
      :erlang.trace_pattern({module, :_, :_}, true, [:local])
    end

    :erlang.trace(:new, true, [:call, {:tracer, self()}])

    try do
      assert {:ok, view, html} = live(conn, "/runs/#{run["id"]}/viewer?view=#{foreign_token}")
      assert html =~ "stale or is not bound"
      refute html =~ "Foreign secret text."
      render_click(view, "open_identity_dialog")
      render_click(view, "close_identity_dialog")
      assert {:ok, canonical} = Fount.Persistence.load(Fount.Repo, "inspection")
      assert canonical.revision.id == base.revision.id
      refute_receive {:trace, _, :call, {_, _, _}}, 100
    after
      :erlang.trace(:new, false, [:call])
      for module <- modules, do: :erlang.trace_pattern({module, :_, :_}, false, [:local])
    end
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
