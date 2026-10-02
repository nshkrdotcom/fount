defmodule FountWeb.UX01ArrivalWorkspaceIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias FountWeb.{Authoring, ExampleProject, Launch, ProjectContext, Store}

  test "blank project opens real writing without creating a Run and saving does not advance canon",
       %{conn: conn} do
    assert {:ok, %{project: project, screenplay: created}} =
             Launch.create_project("test-owner", %{
               "kind" => "blank",
               "title" => "Untitled screenplay"
             })

    assert created.ir.elements == []
    assert run_count(project["id"]) == 0

    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, view, html} = live(conn, "/p/#{project["key"]}/write")
    assert html =~ "Writing"
    assert html =~ "Save working draft"
    assert html =~ "current screenplay"

    source = """
    Title: Untitled screenplay

    INT. EMPTY ROOM - DAY

    A WRITER starts with an actual page.
    """

    html = render_hook(view, "save_source", %{"source" => source, "client_seq" => 1})
    assert html =~ "saved"

    assert {:ok, workspace} = Authoring.open_workspace("test-owner", project["id"])
    assert workspace.draft["raw_source"] == source

    assert {:ok, canonical} = Fount.Persistence.load(Fount.Repo, project["key"])
    assert canonical.revision.id == created.revision.id
    assert Fount.Query.scenes(canonical) == []
    assert run_count(project["id"]) == 0
  end

  test "failed host project creation rolls back Core genesis and permits retry" do
    SQL.query!(Fount.Repo, """
    CREATE FUNCTION pg_temp.reject_import_project() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.title = 'Recoverable import' THEN
        RAISE EXCEPTION 'simulated host failure' USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$
    """)

    SQL.query!(Fount.Repo, """
    CREATE TRIGGER reject_import_project BEFORE INSERT ON fount_web_projects
    FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_import_project()
    """)

    attrs = %{
      "kind" => "import",
      "title" => "Recoverable import",
      "filename" => "recoverable.fountain",
      "source" => "INT. ROOM - DAY\n\nA writer opens a screenplay.\n"
    }

    assert {:error, :storage_error} = Launch.create_project("test-owner", attrs)

    assert SQL.query!(Fount.Repo, "SELECT id FROM screenplays WHERE key=$1", [
             "recoverable-import"
           ]).rows == []

    SQL.query!(Fount.Repo, "DROP TRIGGER reject_import_project ON fount_web_projects")
    assert {:ok, %{project: project}} = Launch.create_project("test-owner", attrs)
    assert project["key"] == "recoverable-import"
    assert run_count(project["id"]) == 0
  end

  test "Fountain and FDX import previews use the actual parser before persistence" do
    fountain = """
    Title: OPEN WINDOW

    INT. KITCHEN - NIGHT

    MARA opens the window.
    """

    assert {:ok, fountain_screenplay, fountain_notes} =
             Launch.preview_import(fountain, "open-window.fountain")

    assert fountain_notes["format"] == "fountain"
    assert length(Fount.Query.scenes(fountain_screenplay)) == 1

    fdx =
      "<FinalDraft><Content><Paragraph Type=\"Scene Heading\"><Text>EXT. PORCH - DAWN</Text></Paragraph><Paragraph Type=\"Action\"><Text>Eli waits.</Text></Paragraph></Content><TagData/></FinalDraft>"

    assert {:ok, fdx_screenplay, fdx_notes} = Launch.preview_import(fdx, "porch.fdx")
    assert fdx_notes["format"] == "fdx"
    assert length(Fount.Query.scenes(fdx_screenplay)) == 1
  end

  test "LAST RETURN is a normal provider-free project with real persisted pages and no task" do
    assert {:ok, %{project: project}} = ExampleProject.create("test-owner")
    assert project["project_kind"] == "example"
    assert run_count(project["id"]) == 0

    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    source = Fount.Screenplay.to_fountain(context.current)

    assert source =~ "LAST RETURN"
    assert source =~ "INT. VIDEO SHOP - NIGHT"
    assert source =~ "We stopped counting."
    assert context.facts.scene_count == 3
  end

  test "project routes remain owner-isolated and returning preferences are owner-bound", %{
    conn: conn
  } do
    assert {:ok, %{project: project}} =
             Launch.create_project("test-owner", %{
               "kind" => "blank",
               "title" => "Private Pages"
             })

    assert {:ok, prefs} = ProjectContext.remember("test-owner", project["key"], "writing")
    assert prefs["last_project_key"] == project["key"]
    assert prefs["last_view"] == "writing"

    outsider = Phoenix.ConnTest.init_test_session(conn, %{owner_id: "other-owner"})
    assert {:error, {kind, %{to: "/login"}}} = live(outsider, "/p/#{project["key"]}")
    assert kind in [:redirect, :live_redirect]

    assert Store.owner_preferences(Fount.Repo, "other-owner") == %{}
  end

  test "task scope remains operable through named task Sources and binds the exact task base", %{
    conn: conn
  } do
    assert {:ok, %{run: run, access: access}} =
             Launch.create("test-owner", %{
               "title" => "Scoped work",
               "key" => "scoped-work-#{System.unique_integer([:positive])}",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain()
             })

    conn = FountWeb.ConnCase.login(conn)
    assert {:ok, view, html} = live(conn, "/p/#{access["key"]}/source/#{access["display_key"]}")
    assert html =~ "Task scope"
    assert html =~ "Whole screenplay"

    html =
      view
      |> element("form[phx-submit='save_workflow_scope']")
      |> render_submit(%{"scope" => %{"whole_screenplay" => "true"}})

    assert html =~ "Task scope saved against this task&#39;s exact base screenplay."
    assert {:ok, saved} = Store.workflow_selection(Fount.Repo, "test-owner", run["id"])
    assert saved["selection"] == %{"whole_screenplay" => true}
    assert saved["base_revision_id"] == get_in(run, ["plan", "base_revision_id"])
  end

  test "existing durable work receives a named task reference while exact run identity stays internal",
       %{conn: conn} do
    assert {:ok, %{run: run, access: access}} =
             Launch.create("test-owner", %{
               "title" => "Named work",
               "key" => "named-work-#{System.unique_integer([:positive])}",
               "journey" => "opening",
               "source" => FountWeb.Journeys.fixture_fountain()
             })

    assert access["display_key"] == "task-1"
    assert access["display_label"] == "Task 1"
    refute access["display_key"] == run["id"]

    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, _view, html} =
             live(conn, "/p/#{access["key"]}/activity/#{access["display_key"]}")

    assert html =~ "Task 1"
    assert html =~ "Technical details"
  end

  defp run_count(project_id) do
    %{rows: [[count]]} =
      SQL.query!(
        Fount.Repo,
        "SELECT count(*)::bigint FROM fount_web_runs WHERE project_id=$1::text::uuid",
        [project_id]
      )

    count
  end
end
