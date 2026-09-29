defmodule FountWeb.Phase06IntegrationTest do
  use FountWeb.ConnCase, async: false

  test "new project form mounts with Fountain upload enabled", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, _view, html} = live(conn, "/projects/new")
    assert html =~ "Upload Fountain/FDX"
  end

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
    assert project["id"] =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    assert project["screenplay_id"] == run["screenplay_id"]
    assert get_in(run, ["policy", "policy", "completion"]) == "candidate"
    assert {:ok, _view, html} = live(conn, "/runs/#{run["id"]}/setup")
    assert html =~ "Produce a checked opening candidate without advancing canon"
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

  test "U04 unauthenticated and wrong-owner sessions cannot view any run surface or artifact", %{
    conn: conn
  } do
    assert {:ok, %{project: project, run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Private",
               "key" => "u04-private-surfaces",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "fixture.fountain"
             })

    assert project["screenplay_id"] == run["screenplay_id"]

    for session <- [%{}, %{owner_id: "other-owner"}],
        path <- [
          "/",
          "/projects/new",
          "/runs/#{run["id"]}/setup",
          "/runs/#{run["id"]}/timeline",
          "/runs/#{run["id"]}/decisions",
          "/runs/#{run["id"]}/review",
          "/runs/#{run["id"]}/exports"
        ] do
      private_conn = Phoenix.ConnTest.init_test_session(conn, session)
      assert {:error, {kind, %{to: "/login"}}} = live(private_conn, path)
      assert kind in [:redirect, :live_redirect]
    end

    for session <- [%{}, %{owner_id: "other-owner"}] do
      private_conn = Phoenix.ConnTest.init_test_session(conn, session)
      response = get(private_conn, "/artifacts/#{run["id"]}/#{Fount.ID.v4()}")
      assert redirected_to(response) == "/login"
      refute response.resp_body =~ "departure board"
    end
  end

  test "standard export form submits without optional checkboxes", %{conn: conn} do
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, %{run: run}} =
             FountWeb.Launch.create("test-owner", %{
               "title" => "Export form",
               "key" => "u01-export-form",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain(),
               "filename" => "fixture.fountain"
             })

    assert {:ok, view, _html} = live(conn, "/runs/#{run["id"]}/exports")
    assert render_submit(element(view, "form[phx-submit=deliver]")) =~ "Export failed"
  end

  test "storage errors are not shown as an empty project or a missing run" do
    assert {:error, :storage_error} =
             FountWeb.Store.project(Fount.Repo, "test-owner", "invalid-uuid")

    assert {:error, :storage_error} =
             FountWeb.Store.run_access(Fount.Repo, "test-owner", "invalid-uuid")
  end
end
