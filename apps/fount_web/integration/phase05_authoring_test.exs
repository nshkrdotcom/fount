defmodule FountWeb.Phase05AuthoringIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias FountWeb.{Authoring, AuthoringStore}

  test "E01/E02 editor preserves raw invalid source and last-valid preview", %{conn: conn} do
    {:ok, %{run: run}} = launch("editor-preview")
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, view, html} = live(conn, "/runs/#{run["id"]}/edit")
    assert html =~ "Interactive Fountain authoring"
    assert html =~ "Fountain syntax assistance"
    assert html =~ "Candidate creation never advances canon"

    invalid = FountWeb.Journeys.fixture_fountain() <> "\n[[unfinished"

    html =
      render_hook(view, "preview_source", %{
        "source" => invalid,
        "client_seq" => 1,
        "line" => 3,
        "column" => 2
      })

    assert html =~ "last valid draft"

    html =
      render_hook(view, "save_source", %{
        "source" => invalid,
        "client_seq" => 1
      })

    assert html =~ "invalid-saved"

    {:ok, access} = FountWeb.Store.run_access(Fount.Repo, "test-owner", run["id"])
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    assert workspace.draft["raw_source"] == invalid
    assert workspace.draft["last_valid_source"] == FountWeb.Journeys.fixture_fountain()
  end

  test "E03/E04 validated structural edits retain unaffected IDs and structural undo uses screenplay snapshots" do
    {:ok, %{run: run, access: access}} = launch("structural")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    base = workspace.preview.screenplay
    actions = Fount.Query.elements(base, :action)
    [target, unaffected | _] = actions

    assert {:ok, draft, edited, changes} =
             Authoring.structural_edit(
               "test-owner",
               workspace.draft["id"],
               workspace.draft["version"],
               base,
               Fount.Edit.replace_text(target.id, "A precise writer edit.")
             )

    assert draft["version"] == workspace.draft["version"] + 1
    assert Enum.any?(changes.changed_targets, &(&1.id == target.id))
    assert Fount.Query.node(edited, unaffected.id).id == unaffected.id
    assert {:ok, undone} = Fount.Screenplay.undo(edited, base)
    assert Fount.Query.node(undone, unaffected.id).id == unaffected.id
    assert Fount.Screenplay.to_fountain(undone) == Fount.Screenplay.to_fountain(base)

    owner_scene = Fount.Query.scene_for(base, target.id)
    insert = %{
      "kind" => "insert_elements",
      "target" => %{"kind" => "scene", "id" => owner_scene.id},
      "value" => %{
        "position" => "after",
        "anchor_id" => target.id,
        "elements" => [%{"local_id" => "new:test-action", "type" => "action", "text" => "Inserted beat.", "attrs" => %{}}]
      }
    }
    assert {:ok, inserted, _} = Fount.Screenplay.apply(base, [insert], [])
    inserted_action = Enum.find(inserted.ir.elements, &(&1.type == :action and &1.text == "Inserted beat."))
    assert inserted_action
    assert {:ok, deleted, _} =
             Fount.Screenplay.apply(inserted, [%{"kind" => "delete_elements", "value" => %{"ids" => [inserted_action.id]}}], [])
    refute Fount.Query.node(deleted, inserted_action.id)
    assert {:error, _} = Fount.Screenplay.apply(base, [Fount.Edit.replace_text(Fount.ID.v4(), "stale")], [])

    {:ok, canonical} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert canonical.revision.id == workspace.base.revision.id
    assert canonical.revision.id != edited.revision.id
    assert run["plan"]["base_revision_id"] == canonical.revision.id
  end

  test "E05 optimistic conflicts fork safely, candidate save is noncanonical, restore is a new draft, and exact approval is separate" do
    {:ok, %{access: access}} = launch("durable-draft")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    draft = workspace.draft
    original_head = workspace.base.revision.id

    raw_a = String.replace(draft["raw_source"], "departure board", "departure display")
    raw_b = String.replace(draft["raw_source"], "departure board", "arrival board")

    assert {:ok, saved_a, _} = Authoring.save_draft("test-owner", draft["id"], draft["version"], raw_a, "tab-a")

    assert {:error, {:stale_draft, conflict}} =
             AuthoringStore.save(Fount.Repo, "test-owner", draft["id"], draft["version"], raw_b)

    assert conflict["version"] == saved_a["version"]
    assert conflict["raw_source"] == raw_a

    assert {:ok, forked} = AuthoringStore.fork(Fount.Repo, "test-owner", draft["id"], raw_b)
    assert forked["id"] != draft["id"]
    assert forked["raw_source"] == raw_b
    assert forked["base_revision_id"] == draft["base_revision_id"]

    assert {:ok, candidate_draft, candidate, fidelity} =
             Authoring.save_candidate("test-owner", draft["id"], saved_a["version"])

    assert fidelity["exact_source_round_trip"]
    assert candidate.screenplay.revision.parent_id == original_head
    assert candidate_draft["saved_candidate_id"] == candidate.id
    assert candidate_draft["saved_candidate_version"] == candidate_draft["version"]

    {:ok, unchanged} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert unchanged.revision.id == original_head

    history = AuthoringStore.history(Fount.Repo, "test-owner", draft["id"], 10)
    assert history != []
    assert {:ok, restored} = AuthoringStore.restore(Fount.Repo, "test-owner", draft["id"], hd(history)["id"])
    assert restored["id"] != draft["id"]
    assert restored["base_revision_id"] == original_head

    assert {:ok, _accepted} =
             Authoring.accept_candidate("test-owner", draft["id"], candidate.id, Fount.ID.v4())

    {:ok, accepted} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert accepted.revision.id == candidate.screenplay.revision.id
    assert Fount.Screenplay.to_fountain(accepted) == raw_a
  end

  test "E05 candidate replay is deterministic and save acknowledgement replay does not create another version" do
    {:ok, %{access: access}} = launch("replay")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    raw = String.replace(workspace.draft["raw_source"], "departure board", "blue departure board")

    assert {:ok, saved, _} =
             Authoring.save_draft("test-owner", workspace.draft["id"], workspace.draft["version"], raw, "first")

    assert {:ok, replay} =
             AuthoringStore.save(
               Fount.Repo,
               "test-owner",
               workspace.draft["id"],
               workspace.draft["version"],
               raw
             )

    assert replay["version"] == saved["version"]
    assert replay["save_replay"]

    assert {:ok, bound1, candidate1, _} = Authoring.save_candidate("test-owner", saved["id"], saved["version"])
    assert {:ok, bound2, candidate2, _} = Authoring.save_candidate("test-owner", saved["id"], saved["version"])
    assert candidate1.id == candidate2.id
    assert bound1["saved_candidate_id"] == bound2["saved_candidate_id"]
  end

  test "E06 AI assistance starts a durable Run from the saved candidate and does not advance canon" do
    {:ok, %{access: access}} = launch("ai-assist")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    original_head = workspace.base.revision.id
    raw = String.replace(workspace.draft["raw_source"], "departure board", "old departure board")

    {:ok, saved, _} = Authoring.save_draft("test-owner", workspace.draft["id"], workspace.draft["version"], raw)
    {:ok, bound, candidate, _} = Authoring.save_candidate("test-owner", saved["id"], saved["version"])

    command = Fount.ID.v5(bound["id"], "phase05-ai")
    assert {:ok, first} = Authoring.start_ai_assist("test-owner", bound["id"], command)
    assert {:ok, second} = Authoring.start_ai_assist("test-owner", bound["id"], command)
    assert first.run["id"] == second.run["id"]
    assert first.run["plan"]["base_revision_id"] == candidate.screenplay.revision.id

    {:ok, canonical} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert canonical.revision.id == original_head
    assert {:ok, run_access} = FountWeb.Store.run_access(Fount.Repo, "test-owner", first.run["id"])
    assert run_access["owner_id"] == "test-owner"
  end

  test "E07 authoring is owner scoped and bounded", %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("owner-scope")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])

    assert {:error, :not_found} = AuthoringStore.get(Fount.Repo, "other-owner", workspace.draft["id"])

    outsider = Phoenix.ConnTest.init_test_session(conn, %{owner_id: "other-owner"})
    assert {:error, {kind, %{to: "/login"}}} = live(outsider, "/runs/#{run["id"]}/edit")
    assert kind in [:redirect, :live_redirect]

    too_large = :binary.copy("x", AuthoringStore.limits().max_source_bytes + 1)

    assert {:error, {:source_too_large, _}} =
             AuthoringStore.save(
               Fount.Repo,
               "test-owner",
               workspace.draft["id"],
               workspace.draft["version"],
               too_large
             )
  end

  defp launch(key) do
    FountWeb.Launch.create("test-owner", %{
      "title" => "Phase 05 #{key}",
      "key" => "phase05-#{key}",
      "journey" => "opening",
      "source" => FountWeb.Journeys.fixture_fountain()
    })
  end
end
