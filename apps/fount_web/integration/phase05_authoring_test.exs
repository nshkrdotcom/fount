defmodule FountWeb.Phase05AuthoringIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias FountWeb.{Authoring, AuthoringStore}

  test "E01/E02 editor preserves raw invalid source and last-valid preview", %{conn: conn} do
    {:ok, %{run: run}} = launch("editor-preview")
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, view, html} = live(conn, "/runs/#{run["id"]}/edit")
    assert html =~ "Screenplay editor"
    assert html =~ "Fountain syntax assistance"
    assert html =~ "Saving a proposed revision leaves the approved screenplay unchanged"

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
        "elements" => [
          %{
            "local_id" => "new:test-action",
            "type" => "action",
            "text" => "Inserted beat.",
            "attrs" => %{}
          }
        ]
      }
    }

    assert {:ok, inserted, _} = Fount.Screenplay.apply(base, [insert], [])

    inserted_action =
      Enum.find(inserted.ir.elements, &(&1.type == :action and &1.text == "Inserted beat."))

    assert inserted_action

    assert {:ok, deleted, _} =
             Fount.Screenplay.apply(
               inserted,
               [%{"kind" => "delete_elements", "value" => %{"ids" => [inserted_action.id]}}],
               []
             )

    refute Fount.Query.node(deleted, inserted_action.id)

    assert {:error, _} =
             Fount.Screenplay.apply(base, [Fount.Edit.replace_text(Fount.ID.v4(), "stale")], [])

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

    assert {:ok, saved_a, _} =
             Authoring.save_draft("test-owner", draft["id"], draft["version"], raw_a, "tab-a")

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

    assert {:ok, restored} =
             AuthoringStore.restore(Fount.Repo, "test-owner", draft["id"], hd(history)["id"])

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
             Authoring.save_draft(
               "test-owner",
               workspace.draft["id"],
               workspace.draft["version"],
               raw,
               "first"
             )

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

    assert {:ok, bound1, candidate1, _} =
             Authoring.save_candidate("test-owner", saved["id"], saved["version"])

    assert {:ok, bound2, candidate2, _} =
             Authoring.save_candidate("test-owner", saved["id"], saved["version"])

    assert candidate1.id == candidate2.id
    assert bound1["saved_candidate_id"] == bound2["saved_candidate_id"]
  end

  test "E06 AI assistance starts a durable Run from the saved candidate and does not advance canon" do
    {:ok, %{access: access}} = launch("ai-assist")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    original_head = workspace.base.revision.id

    assert {:error, :saved_candidate_required} =
             Authoring.start_ai_assist("test-owner", workspace.draft["id"], Fount.ID.v4())

    raw = String.replace(workspace.draft["raw_source"], "departure board", "old departure board")

    {:ok, saved, _} =
      Authoring.save_draft("test-owner", workspace.draft["id"], workspace.draft["version"], raw)

    {:ok, bound, candidate, _} =
      Authoring.save_candidate("test-owner", saved["id"], saved["version"])

    command = Fount.ID.v5(bound["id"], "phase05-ai")
    assert {:ok, first} = Authoring.start_ai_assist("test-owner", bound["id"], command)
    assert {:ok, second} = Authoring.start_ai_assist("test-owner", bound["id"], command)
    assert first.run["id"] == second.run["id"]

    %{rows: [[1]]} =
      Ecto.Adapters.SQL.query!(
        Fount.Repo,
        "SELECT count(*) FROM fount_runs WHERE id=$1::text::uuid",
        [first.run["id"]]
      )

    %{rows: [[1]]} =
      Ecto.Adapters.SQL.query!(
        Fount.Repo,
        "SELECT count(*) FROM fount_run_steps WHERE run_id=$1::text::uuid AND stage='intake'",
        [first.run["id"]]
      )

    assert first.run["plan"]["base_revision_id"] == candidate.screenplay.revision.id

    {:ok, canonical} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert canonical.revision.id == original_head

    assert {:ok, run_access} =
             FountWeb.Store.run_access(Fount.Repo, "test-owner", first.run["id"])

    assert run_access["owner_id"] == "test-owner"
  end

  test "E07 authoring is owner scoped and bounded", %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("owner-scope")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])

    assert {:error, :not_found} =
             AuthoringStore.get(Fount.Repo, "other-owner", workspace.draft["id"])

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

  test "E01 invalid draft reload renders last-valid preview and later valid input", %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("invalid-reload")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    invalid = workspace.draft["raw_source"] <> "\n[[unfinished"
    {:ok, saved, _} = Authoring.save_draft("test-owner", workspace.draft["id"], 1, invalid)
    {:ok, view, html} = live(FountWeb.ConnCase.login(conn), "/runs/#{run["id"]}/edit")
    assert html =~ "last valid draft"
    assert html =~ "unclosed_note"
    assert saved["last_valid_source"] == workspace.draft["raw_source"]

    html =
      render_hook(view, "preview_source", %{
        "source" => workspace.draft["raw_source"],
        "client_seq" => 2
      })

    assert html =~ "No blocking source diagnostics"
    render_hook(view, "preview_source", %{"source" => invalid, "client_seq" => 1})
    refute render(view) =~ "unclosed_note"
  end

  test "E05 stale base and owner boundaries reject candidate and AI work" do
    {:ok, %{access: access}} = launch("stale-base")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    draft = workspace.draft
    {:ok, bound, candidate, _} = Authoring.save_candidate("test-owner", draft["id"], 1)
    {:ok, other} = AuthoringStore.fork(Fount.Repo, "test-owner", draft["id"], draft["raw_source"])
    {:ok, _, other_candidate, _} = Authoring.save_candidate("test-owner", other["id"], 1)

    for action <- [
          fn -> Authoring.save_draft("other-owner", draft["id"], 1, "foreign") end,
          fn -> Authoring.save_candidate("other-owner", draft["id"], 1) end,
          fn -> AuthoringStore.fork(Fount.Repo, "other-owner", draft["id"], "foreign") end,
          fn -> AuthoringStore.restore(Fount.Repo, "other-owner", draft["id"], Fount.ID.v4()) end,
          fn ->
            Authoring.accept_candidate("other-owner", draft["id"], candidate.id, Fount.ID.v4())
          end,
          fn -> Authoring.start_ai_assist("other-owner", draft["id"], Fount.ID.v4()) end
        ],
        do: assert({:error, _} = action.())

    assert {:ok, _} =
             Authoring.accept_candidate(
               "test-owner",
               other["id"],
               other_candidate.id,
               Fount.ID.v4()
             )

    {:ok, reopened} = Authoring.open_workspace("test-owner", access["project_id"])
    assert reopened.base.revision.id == draft["base_revision_id"]
    assert reopened.preview.screenplay.revision.parent_id == draft["base_revision_id"]
    assert {:error, _} = Authoring.start_ai_assist("test-owner", bound["id"], Fount.ID.v4())

    assert {:error, _} =
             Authoring.accept_candidate("test-owner", bound["id"], candidate.id, Fount.ID.v4())

    {:ok, edited, _} =
      Authoring.save_draft(
        "test-owner",
        draft["id"],
        1,
        draft["raw_source"] <> "\nA stale edit.\n"
      )

    assert {:error, {:stale_base, _}} =
             Authoring.save_candidate("test-owner", draft["id"], edited["version"])

    assert {:ok, rebased} = Authoring.rebase("test-owner", draft["id"], edited["version"])

    assert {:ok, _, current, _} =
             Authoring.save_candidate("test-owner", draft["id"], rebased["version"])

    assert current.screenplay.revision.parent_id == other_candidate.screenplay.revision.id
    {:ok, canonical} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert canonical.revision.id == other_candidate.screenplay.revision.id
  end

  test "E05 configured history and draft bounds prune deterministically and discard blocks saves" do
    previous = Application.get_env(:fount_web, :authoring)
    Application.put_env(:fount_web, :authoring, history_limit: 2, draft_limit: 2)
    on_exit(fn -> Application.put_env(:fount_web, :authoring, previous) end)
    {:ok, %{access: access}} = launch("bounds")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])

    final =
      Enum.reduce(1..4, workspace.draft, fn n, draft ->
        {:ok, saved, _} =
          Authoring.save_draft(
            "test-owner",
            draft["id"],
            draft["version"],
            workspace.draft["raw_source"] <> "\nBeat #{n}.\n"
          )

        saved
      end)

    history = AuthoringStore.history(Fount.Repo, "test-owner", final["id"], 50)
    assert length(history) == 2
    assert Enum.map(history, & &1["draft_version"]) == [4, 3]

    {:ok, restored} =
      AuthoringStore.restore(Fount.Repo, "test-owner", final["id"], hd(history)["id"])

    assert restored["id"] != final["id"]

    assert {:error, _} =
             AuthoringStore.fork(Fount.Repo, "test-owner", final["id"], final["raw_source"])

    assert {:ok, _} = AuthoringStore.discard(Fount.Repo, "test-owner", restored["id"], 1)

    assert {:error, :draft_not_active} =
             AuthoringStore.save(Fount.Repo, "test-owner", restored["id"], 1, "discarded")

    {:ok, canonical} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert canonical.revision.id == workspace.base.revision.id
  end

  test "E04 all seven structural commands, stale targets, reload and undo redo", %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("all-commands")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    {:ok, view, _} = live(FountWeb.ConnCase.login(conn), "/runs/#{run["id"]}/edit")
    base = workspace.base
    [first_scene, second_scene | _] = base.ir.scenes
    action = Enum.find(base.ir.elements, &(&1.type == :action))
    cue = Enum.find(base.ir.elements, &(&1.type == :character))
    unaffected = List.last(base.ir.elements).id

    for {kind, target, value} <- [
          {"replace_text", action.id, "A changed beat."},
          {"set_character_cue", cue.id, "NORA"},
          {"insert_scene", first_scene.id, "INT. NEW ROOM - DAY"},
          {"move_scene", first_scene.id, second_scene.id},
          {"insert_element_after", action.id, "Inserted runtime action."}
        ] do
      html =
        render_hook(view, "structural_edit", %{
          "edit" => %{"kind" => kind, "target" => target, "value" => value}
        })

      assert html =~ "Affected stable IDs"
      {:ok, current} = Authoring.open_workspace("test-owner", access["project_id"])
      assert current.preview.screenplay.id == base.id
      assert Fount.Query.node(current.preview.screenplay, unaffected)

      assert Fount.Screenplay.to_fountain(current.preview.screenplay) ==
               current.draft["raw_source"]

      assert render_hook(view, "structural_edit", %{
               "edit" => %{"kind" => kind, "target" => Fount.ID.v4(), "value" => value}
             }) =~ "Authoring notice"
    end

    {:ok, current} = Authoring.open_workspace("test-owner", access["project_id"])

    inserted =
      Enum.find(current.preview.screenplay.ir.elements, &(&1.text == "Inserted runtime action."))

    before_delete = current.draft["raw_source"]

    render_hook(view, "structural_edit", %{
      "edit" => %{"kind" => "delete_element", "target" => inserted.id}
    })

    render_hook(view, "structural_undo", %{})
    {:ok, undone} = Authoring.open_workspace("test-owner", access["project_id"])
    assert undone.draft["raw_source"] == before_delete
    render_hook(view, "structural_redo", %{})
    {:ok, redone} = Authoring.open_workspace("test-owner", access["project_id"])
    refute Fount.Query.node(redone.preview.screenplay, inserted.id)

    new_scene =
      Enum.find(
        redone.preview.screenplay.ir.scenes,
        &(&1.id not in Enum.map(base.ir.scenes, fn x -> x.id end))
      )

    render_hook(view, "structural_undo", %{})

    render_hook(view, "structural_edit", %{
      "edit" => %{"kind" => "delete_scene", "target" => new_scene.id}
    })

    assert has_element?(view, "button[phx-click=structural_redo][disabled]")

    assert render_hook(view, "structural_edit", %{
             "edit" => %{"kind" => "delete_scene", "target" => new_scene.id}
           }) =~ "Authoring notice"

    refute has_element?(view, "option[value=move_element]")
    refute has_element?(view, "option[value=split_scene]")
    {:ok, head} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert head.revision.id == base.revision.id
  end

  test "E02 near 1 MiB raw source succeeds and over-limit preview and store reject before persistence" do
    {:ok, %{access: access}} = launch("large-source")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    maximum = AuthoringStore.limits().max_source_bytes
    prefix = "INT. LARGE ROOM - DAY\n\n"
    raw = prefix <> :binary.copy("x", maximum - byte_size(prefix))

    assert {:ok, saved, preview} =
             Authoring.save_draft("test-owner", workspace.draft["id"], 1, raw)

    assert preview.valid?
    assert Fount.Screenplay.to_fountain(preview.screenplay) == raw
    assert {:error, {:source_too_large, ^maximum}} = Authoring.preview(workspace.base, raw <> "x")

    assert {:error, {:source_too_large, ^maximum}} =
             Authoring.save_draft("test-owner", saved["id"], saved["version"], raw <> "x")

    {:ok, reloaded} = AuthoringStore.get(Fount.Repo, "test-owner", saved["id"])
    assert reloaded["version"] == saved["version"]
    assert reloaded["raw_source"] == raw
  end

  test "E03 structural snapshot history stays at 50 and autosave success and failure are visible",
       %{conn: conn} do
    {:ok, %{run: run, access: access}} = launch("history-autosave")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    target = Enum.find(workspace.base.ir.elements, &(&1.type == :action)).id
    {:ok, view, _} = live(FountWeb.ConnCase.login(conn), "/runs/#{run["id"]}/edit")

    for n <- 1..52 do
      render_hook(view, "structural_edit", %{
        "edit" => %{"kind" => "replace_text", "target" => target, "value" => "Beat #{n}."}
      })
    end

    for _ <- 1..50, do: render_hook(view, "structural_undo", %{})
    assert has_element?(view, "button[phx-click=structural_undo][disabled]")
    for _ <- 1..50, do: render_hook(view, "structural_redo", %{})
    assert has_element?(view, "button[phx-click=structural_redo][disabled]")
    raw = workspace.draft["raw_source"] <> "\nAutosaved action.\n"
    render_hook(view, "preview_source", %{"source" => raw, "client_seq" => 1})
    send(view.pid, :autosave)
    assert render(view) =~ "Draft synchronized"
    {:ok, saved} = AuthoringStore.get(Fount.Repo, "test-owner", workspace.draft["id"])
    assert saved["raw_source"] == raw

    assert {:ok, _} =
             AuthoringStore.discard(Fount.Repo, "test-owner", saved["id"], saved["version"])

    render_hook(view, "preview_source", %{"source" => raw <> "\nChanged.\n", "client_seq" => 2})
    send(view.pid, :autosave)
    assert render(view) =~ "save-failed"
  end

  test "E01 persisted draft-created IDs survive source shifts and invalid recovery forks" do
    {:ok, %{access: access}} = launch("identity-recovery")
    {:ok, workspace} = Authoring.open_workspace("test-owner", access["project_id"])
    raw = workspace.draft["raw_source"] <> "\nA new cable sparks.\n"
    {:ok, saved, first} = Authoring.save_draft("test-owner", workspace.draft["id"], 1, raw)
    created = Enum.find(first.screenplay.ir.elements, &(&1.text == "A new cable sparks."))
    shifted = String.replace(raw, "Title:", "Title: Longer Unicode café 🙂")

    {:ok, later, next} =
      Authoring.save_draft("test-owner", saved["id"], saved["version"], shifted)

    assert Fount.Query.node(next.screenplay, created.id).text == created.text
    {:ok, reloaded} = Authoring.open_workspace("test-owner", access["project_id"])
    assert Fount.Query.node(reloaded.preview.screenplay, created.id).text == created.text
    invalid = shifted <> "\n[[unfinished"

    {:ok, invalid_saved, _} =
      Authoring.save_draft("test-owner", later["id"], later["version"], invalid)

    assert invalid_saved["last_valid_source"] == shifted
    {:ok, forked} = AuthoringStore.fork(Fount.Repo, "test-owner", later["id"], invalid)
    assert forked["last_valid_source"] == shifted
    assert forked["raw_source"] == invalid
    {:ok, recovered} = Authoring.open_workspace("test-owner", access["project_id"])
    refute recovered.preview.valid?
    assert Fount.Query.node(recovered.preview.screenplay, created.id).text == created.text
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
