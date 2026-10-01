defmodule FountWeb.Phase05BoundaryRaceTest do
  use FountWeb.ConnCase, async: false
  alias FountWeb.{Authoring, AuthoringStore}

  test "E06 unsaved raw refuses immediate AI action before preview debounce", %{conn: conn} do
    {:ok, %{run: run, access: access}} =
      FountWeb.Launch.create("test-owner", %{
        "key" => "phase05-immediate-ai",
        "title" => "Boundary",
        "journey" => "opening",
        "source" => FountWeb.Journeys.fixture_fountain()
      })

    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    {:ok, _, _, _} = Authoring.save_candidate("test-owner", workspace.draft["id"], 1)
    {:ok, view, _} = live(FountWeb.ConnCase.login(conn), editor_path(run))

    html =
      render_hook(view, "start_ai_assist", %{
        "source" => workspace.draft["raw_source"] <> "\nUnsaved text.",
        "client_seq" => 1
      })

    assert html =~ "Save the draft and candidate"
  end

  test "E05 unsaved raw refuses immediate acceptance before preview debounce", %{conn: conn} do
    {:ok, %{run: run, access: access}} =
      FountWeb.Launch.create("test-owner", %{
        "key" => "phase05-immediate-accept",
        "title" => "Boundary",
        "journey" => "opening",
        "source" => FountWeb.Journeys.fixture_fountain()
      })

    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    {:ok, _, _, _} = Authoring.save_candidate("test-owner", workspace.draft["id"], 1)
    {:ok, view, _} = live(FountWeb.ConnCase.login(conn), editor_path(run))

    html =
      render_hook(view, "accept_candidate", %{
        "source" => workspace.draft["raw_source"] <> "\nUnsaved text.",
        "client_seq" => 1
      })

    assert html =~ "Unsaved text cannot be accepted"
    {:ok, canon} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert canon.revision.id == workspace.base.revision.id
  end

  test "E05 discarded draft cannot approve a bound candidate" do
    {:ok, %{access: access}} =
      FountWeb.Launch.create("test-owner", %{
        "key" => "phase05-discard-accept",
        "title" => "Boundary",
        "journey" => "opening",
        "source" => FountWeb.Journeys.fixture_fountain()
      })

    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    {:ok, draft, candidate, _} = Authoring.save_candidate("test-owner", workspace.draft["id"], 1)
    {:ok, _} = AuthoringStore.discard(Fount.Repo, "test-owner", draft["id"], 1)

    assert {:error, :draft_not_active} =
             Authoring.accept_candidate("test-owner", draft["id"], candidate.id, Fount.ID.v4())

    {:ok, canon} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert canon.revision.id == workspace.base.revision.id
  end

  defp editor_path(run) do
    {:ok, access} = FountWeb.Store.run_access(Fount.Repo, "test-owner", run["id"])
    "/p/#{access["key"]}/write"
  end
end
