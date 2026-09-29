defmodule FountWeb.Phase06IntegrationTest do
  use FountWeb.ConnCase, async: false

  test "U01 project intake creates candidate-only Run and exact owner mapping", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, %{project: project, run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Opening",
               "key" => "u01-opening",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "fixture.fountain"
             })

    assert project["owner_id"] == "test-owner"
    assert get_in(run, ["policy", "policy", "completion"]) == "candidate"
    assert {:ok, _view, html} = live(conn, "/runs/#{run["id"]}/setup")
    assert html =~ "Candidate only"
    assert html =~ "accepted pages can change canon" or html =~ "Accepted pages can change canon"
  end

  test "U04 wrong run id and wrong owner are denied rather than widened", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, %{run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Owner scoped",
               "key" => "u04-owner-scope",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "fixture.fountain"
             })

    assert {:error, :not_found} = FountWeb.Store.run_access(Fount.Repo, "other-owner", run["id"])
    assert {:error, {kind, %{to: "/"}}} = live(conn, "/runs/#{Fount.ID.v4()}/timeline")
    assert kind in [:redirect, :live_redirect]
  end
end
