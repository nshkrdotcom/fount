defmodule FountWeb.Phase04ViewerIntegrationTest do
  use FountWeb.ConnCase, async: false

  test "U08 owner-authorized viewer loads exact Run base and rejects arbitrary/stale revision tokens", %{conn: conn} do
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
    assert html =~ "Read-only screenplay workspace"
    assert html =~ base_revision
    assert html =~ "Run base"
    assert html =~ "No Run-bound candidate is currently available"

    arbitrary = Fount.ID.v4()
    assert {:ok, _view, stale_html} = live(conn, "/runs/#{run["id"]}/viewer?view=accepted:#{arbitrary}")
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
    assert {:error, {kind, %{to: "/"}}} = live(outsider, "/runs/#{run["id"]}/viewer")
    assert kind in [:redirect, :live_redirect]
  end
end
