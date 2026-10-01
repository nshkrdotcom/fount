defmodule FountWeb.UX02WritingWorkshopIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias FountWeb.{CreativeWorkspace, ProductionTools, WorkflowManagement}

  test "UX02 Work stays question-first while the complete validated catalog is reachable", %{
    conn: conn
  } do
    assert {:ok, %{access: access}} = launch("brief")
    conn = FountWeb.ConnCase.login(conn)

    assert {:ok, _view, html} = live(conn, "/p/#{access["key"]}/work")
    assert html =~ ~s(id="creative-brief")
    assert html =~ "What do you want to change or understand?"
    assert html =~ "All tasks"
    assert html =~ "Let the dialogue imply more"
    assert html =~ "Look for exposition"
    assert html =~ "Explore who has the upper hand"
    assert html =~ ~s(name="task[multi_launch]")

    for label <- [
          "Develop pages",
          "Rewrite selected pages",
          "Focused pass",
          "Explore alternatives",
          "Rebuild sequence",
          "Character work",
          "Carry a change through",
          "Work from notes",
          "Recover earlier material",
          "Investigate a concern"
        ] do
      assert html =~ label
    end
  end

  test "UX02 ordinary currency converts exactly to the existing microunit policy contract" do
    assert {:ok, %{run: run}} = launch("money")
    assert {:ok, context} = FountWeb.Actors.owner_context("test-owner", run["screenplay_id"])

    params = %{
      "investigation_scope" => "automatic",
      "strategy_choice" => "human",
      "candidate_generation" => "automatic",
      "iteration" => "automatic",
      "completion" => "candidate",
      "approver" => "owner",
      "owner_fallback_enabled" => "false",
      "route_choice" => "pause_on_material_tradeoff",
      "route_reviewer_key" => "",
      "max_iterations" => "2",
      "max_malformed_repairs_per_call" => "1",
      "max_transient_retries" => "2",
      "max_inference_calls" => "8",
      "max_measurement_states" => "500",
      "money_enabled" => "true",
      "currency" => "USD",
      "max_currency_units" => "12.500001"
    }

    assert {:ok, policy, _fingerprint} =
             WorkflowManagement.policy_from_form(params, context, "test-owner")

    assert get_in(policy, ["limits", "money"]) == %{
             "currency" => "USD",
             "max_microunits" => 12_500_001
           }

    assert WorkflowManagement.money_units(12_500_001) == "12.500001"

    assert {:error, :invalid_money_limit} =
             WorkflowManagement.policy_from_form(
               %{params | "max_currency_units" => "12.5000001"},
               context,
               "test-owner"
             )
  end

  test "UX02 exact source and protections validate the supported creative families" do
    assert {:ok, %{run: run}} = launch("catalog")

    assert {:ok, model} =
             Fount.Persistence.load_revision(
               Fount.Repo,
               run["screenplay_id"],
               get_in(run, ["plan", "base_revision_id"])
             )

    [scene | _] = model.ir.scenes
    [element | _] = Enum.reject(model.ir.elements, &(&1.type == :blank))
    [character_id | _] = Map.keys(model.cast)

    assert {:ok, selection} =
             CreativeWorkspace.selection_from_values(model, ["scene:#{scene.id}"])

    assert {:ok, protected} =
             CreativeWorkspace.protected_text(model, ["element:#{element.id}"])

    assert hd(protected)["text"] == element.text

    action_attrs = [
      {"develop", %{"placement" => %{"kind" => "start"}, "brief" => "Open with more pressure."}},
      {"rewrite", %{"direction" => "Make the scene more oblique."}},
      {"pass", %{"profile" => "dialogue_subtext", "direction" => "Let the dialogue imply more."}},
      {"alternatives",
       %{
         "alternatives" => 3,
         "approaches" => ["quiet", "hostile", "comic"],
         "allow_brief_departure" => false
       }},
      {"sequence", %{"target_scene_count" => 2}},
      {"character",
       %{"character_id" => character_id, "direction" => "Clarify the character's leverage."}},
      {"propagate", %{"repair_scope" => selection}},
      {"investigate",
       %{"concern" => "Where is exposition doing too much work?", "write_fixes" => false}}
    ]

    for {action, attrs} <- action_attrs do
      attrs = Map.put(attrs, "protected_text", protected)

      assert {:ok, request} =
               WorkflowManagement.build_workshop_request(
                 model,
                 action,
                 "Validate #{action} against this exact source.",
                 selection,
                 attrs
               )

      assert request["base_revision_id"] == model.revision.id
      assert request["selection"] == selection
    end

    [first, second | _] = Enum.reject(model.ir.elements, &(&1.type == :blank))

    multi_selection = %{
      "targets" => [
        %{"kind" => "element", "id" => first.id},
        %{"kind" => "element", "id" => second.id}
      ]
    }

    assert {:ok, context} = FountWeb.Actors.owner_context("test-owner", model.id)
    [%{"policy" => policy} | _] = WorkflowManagement.built_in_presets("test-owner", context)

    assert {:ok, preview} =
             WorkflowManagement.launch_preview(
               model,
               "rewrite",
               "Give each selected beat a quieter threat.",
               multi_selection,
               policy,
               true,
               %{"direction" => "Give each selected beat a quieter threat."}
             )

    assert length(preview["entries"]) == 2
    assert Enum.all?(preview["entries"], &(length(&1["selection"]["targets"]) == 1))
    assert Enum.all?(preview["entries"], &(&1["passages"] != []))
  end

  test "UX02 accepted note work persists an owner/source/run relation and recovery uses real history" do
    assert {:ok, %{project: project, run: seed_run, access: access}} = launch("notes-recover")

    assert {:ok, original} =
             Fount.Persistence.load_revision(
               Fount.Repo,
               seed_run["screenplay_id"],
               get_in(seed_run, ["plan", "base_revision_id"])
             )

    [scene | _] = original.ir.scenes

    assert {:ok, note_result} =
             ProductionTools.save_note_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               original.revision.id,
               %{
                 "target" => "scene:#{scene.id}",
                 "title" => "Hold back the explanation",
                 "text" => "Keep this beat source-bound and let the turn land later."
               }
             )

    assert {:ok, _accepted} =
             ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               note_result.candidate.id,
               Fount.ID.v4()
             )

    assert {:ok, current} = Fount.Persistence.load(Fount.Repo, access["key"])
    assert current.authored_items[note_result.note_id]["kind"] == "note"

    current_scene = hd(current.ir.scenes)
    selection = %{"targets" => [%{"kind" => "scene", "id" => current_scene.id}]}

    assert {:ok, notes_request} =
             WorkflowManagement.build_workshop_request(
               current,
               "notes",
               "Work on this accepted note.",
               selection,
               %{"note_ids" => [note_result.note_id], "external_notes" => []}
             )

    assert notes_request["options"]["note_ids"] == [note_result.note_id]

    assert {:ok, context} = FountWeb.Actors.owner_context("test-owner", current.id)
    [%{"policy" => policy} | _] = WorkflowManagement.built_in_presets("test-owner", context)

    assert {:ok, %{run: note_run}} =
             FountWeb.Launch.create_action_from_base(
               "test-owner",
               project["id"],
               current.revision.id,
               %{
                 "command_id" => "ux02-note-link",
                 "action" => "notes",
                 "instruction" => "Work on this accepted note.",
                 "selection" => selection,
                 "policy" => policy,
                 "request_attrs" => %{"note_ids" => [note_result.note_id], "external_notes" => []}
               }
             )

    assert {:ok, link} =
             ProductionTools.link_note_work(
               Fount.Repo,
               "test-owner",
               project["id"],
               current.id,
               current.revision.id,
               note_result.note_id,
               note_run["id"]
             )

    assert link["source_revision_id"] == current.revision.id
    assert link["source_fingerprint"] == current.revision.content_hash
    assert link["note_id"] == note_result.note_id

    # Recovery must use persisted pipeline requests, including a missing host link.
    Ecto.Adapters.SQL.query!(
      Fount.Repo,
      "DELETE FROM fount_web_note_work_links WHERE run_id=$1::text::uuid",
      [note_run["id"]]
    )

    assert :ok =
             ProductionTools.reconcile_note_work_links(
               Fount.Repo,
               "test-owner",
               project["id"],
               current.id
             )

    assert [recovered] =
             ProductionTools.note_work_links(
               Fount.Repo,
               "test-owner",
               project["id"],
               note_result.note_id
             )

    assert recovered["run_id"] == note_run["id"]
    assert recovered["source_fingerprint"] == current.revision.content_hash

    assert :ok =
             ProductionTools.reconcile_note_work_links(
               Fount.Repo,
               "test-owner",
               project["id"],
               current.id
             )

    assert length(
             ProductionTools.note_work_links(
               Fount.Repo,
               "test-owner",
               project["id"],
               note_result.note_id
             )
           ) == 1

    assert {:error, :note_not_found} =
             ProductionTools.link_note_work(
               Fount.Repo,
               "test-owner",
               project["id"],
               current.id,
               original.revision.id,
               note_result.note_id,
               note_run["id"]
             )

    assert {:error, _} =
             ProductionTools.link_note_work(
               Fount.Repo,
               "other-owner",
               project["id"],
               current.id,
               current.revision.id,
               note_result.note_id,
               note_run["id"]
             )

    assert {:ok, recover_attrs} =
             CreativeWorkspace.action_attrs(
               Fount.Repo,
               current,
               "recover",
               %{
                 "source_revision_id" => original.revision.id,
                 "source_targets" => ["scene:#{scene.id}"],
                 "destination" => "start",
                 "adapt" => "true"
               },
               selection,
               []
             )

    assert {:ok, recover_request} =
             WorkflowManagement.build_workshop_request(
               current,
               "recover",
               "Recover the earlier scene at the start.",
               selection,
               recover_attrs
             )

    assert recover_request["options"]["source_revision_id"] == original.revision.id
  end

  defp launch(suffix) do
    FountWeb.Launch.create("test-owner", %{
      "title" => "UX02 #{suffix}",
      "key" => "ux02-#{suffix}-#{System.unique_integer([:positive])}",
      "journey" => "opening",
      "source" => FountWeb.Journeys.fixture_fountain(),
      "filename" => "ux02.fountain"
    })
  end
end
