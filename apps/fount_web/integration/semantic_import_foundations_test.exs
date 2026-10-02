defmodule FountWeb.SI01SemanticImportIntegrationTest do
  use FountWeb.ConnCase, async: false

  alias FountWeb.{Launch, ProjectContext, SemanticContext, SemanticStore, Store}

  @source """
  Title: SI01 Fixture

  INT. NORTH STATION - PLATFORM - NIGHT(2030)

  !AUTHORIZED PERSONNEL ONLY
  DO NOT ENTER.

  GUARD
  Stop.

  INT. NORTH STATION - PLATFORM - LATE AFTERNOON

  GUARD (O.S.)
  Again.
  """

  test "SI01 import preserves source bytes, creates literal inventory, export provenance, and creates no synthetic Run",
       %{conn: conn} do
    before_runs = Store.list_project_runs(Fount.Repo, "test-owner", Fount.ID.v4(), limit: 50)

    assert {:ok, %{project: project, screenplay: screenplay}} =
             Launch.create_project("test-owner", %{
               "title" => "SI01 import",
               "kind" => "import",
               "source" => @source,
               "filename" => "si01.fountain"
             })

    assert screenplay.cast == %{}
    assert screenplay.import.bytes == @source
    assert before_runs == []
    assert Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 50) == []

    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    semantic = context.semantic
    assert semantic.assessment["origin"] == "manual"
    assert is_binary(semantic.assessment["source_artifact_id"])
    assert semantic.source_sha256 == Fount.ID.hash(@source)
    assert semantic.assessment["run_id"] == nil
    assert semantic.assessment["model"] == nil
    assert semantic.version == 0
    assert length(semantic.characters) == 2
    assert Enum.all?(semantic.characters, &(&1.review_state == "unreviewed"))
    assert Enum.all?(semantic.characters, &(&1.display_name == "GUARD"))
    assert length(semantic.locations) == 2

    assert Enum.any?(semantic.locations, fn location ->
             Enum.any?(
               location.entries,
               &(&1.date_or_era == "2030" and &1.parsed_time == "NIGHT")
             )
           end)

    assert {:ok, filtered} =
             FountWeb.ProductionTools.search(context.current, "Stop", %{
               "character_id" => "literal:GUARD",
               "limit" => "20"
             })

    assert filtered.returned_hit_count > 0

    assert {:ok, read_packet} =
             FountWorkshop.TableRead.packet(context.current, %{"whole_screenplay" => true})

    assert length(read_packet["turns"]) == 2
    assert Enum.all?(read_packet["roles"], &(&1["cue"] == "GUARD" and is_nil(&1["character_id"])))

    conn = FountWeb.ConnCase.login(conn)
    response = get(conn, "/p/#{project["key"]}/source-review/export.json")
    assert response.status == 200
    export = Jason.decode!(response.resp_body)
    assert export["kind"] == "fount.semantic_source_review_v1"
    assert export["source"]["revision_id"] == screenplay.revision.id
    assert export["source"]["source_sha256"] == semantic.source_sha256
    assert export["source"]["source_artifact_id"] == semantic.assessment["source_artifact_id"]

    assert {:ok, dialogue} =
             SemanticContext.character_dialogue(context.current, hd(semantic.characters))

    assert dialogue.total == 1
    assert hd(dialogue.rows).scene_heading =~ "NORTH STATION"
    assert export["assessment"]["origin"] == "manual"
    assert export["assessment"]["run_id"] == nil
    assert export["assessment"]["model"] == nil
    assert export["provenance"]["screenplay_accepted_by_review"] == false
  end

  test "manual review is owner/source bound, optimistic, append-only, and Run-independent" do
    assert {:ok, %{project: project}} =
             Launch.create_project("test-owner", %{
               "title" => "SI01 review",
               "kind" => "import",
               "source" => @source,
               "filename" => "review.fountain"
             })

    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    semantic = context.semantic
    [first, second] = semantic.characters
    before_runs = Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 50)

    assert {:ok, confirmed} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               project["id"],
               semantic.assessment_id,
               %{
                 "action" => "confirm",
                 "target_handle_id" => first.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => 0,
                 "command_id" => "confirm-1",
                 "actor" => "human:test-owner"
               }
             )

    assert confirmed["new_version"] == 1

    # Retrying the exact command is idempotent and returns the original durable outcome.
    assert {:ok, repeated} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               project["id"],
               semantic.assessment_id,
               %{
                 "action" => "confirm",
                 "target_handle_id" => first.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => 0,
                 "command_id" => "confirm-1",
                 "actor" => "human:test-owner"
               }
             )

    assert repeated["id"] == confirmed["id"]
    assert repeated["new_version"] == 1

    assert {:error, :command_id_conflict} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               project["id"],
               semantic.assessment_id,
               %{
                 "action" => "reject",
                 "target_handle_id" => first.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => 0,
                 "command_id" => "confirm-1",
                 "actor" => "human:test-owner"
               }
             )

    assert {:error, {:stale_review, stale}} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               project["id"],
               semantic.assessment_id,
               %{
                 "action" => "reject",
                 "target_handle_id" => second.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => 0,
                 "command_id" => "stale-1",
                 "actor" => "human:test-owner"
               }
             )

    assert stale["outcome"] == "conflict"
    assert stale["new_version"] == 1

    assert {:error, :not_found} =
             SemanticStore.review(
               Fount.Repo,
               "other-owner",
               project["id"],
               semantic.assessment_id,
               %{
                 "action" => "confirm",
                 "target_handle_id" => first.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => 1,
                 "command_id" => "cross-owner",
                 "actor" => "human:other-owner"
               }
             )

    assert {:ok, %{project: other_project}} =
             Launch.create_project("test-owner", %{
               "title" => "SI01 other project",
               "kind" => "import",
               "source" => @source,
               "filename" => "other-project.fountain"
             })

    assert {:error, :not_found} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               other_project["id"],
               semantic.assessment_id,
               %{
                 "action" => "confirm",
                 "target_handle_id" => first.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => 1,
                 "command_id" => "cross-project",
                 "actor" => "human:test-owner"
               }
             )

    assert Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 50) ==
             before_runs

    assert {:ok, reloaded} = ProjectContext.load("test-owner", project["key"])

    assert Enum.any?(
             reloaded.semantic.characters,
             &(&1.semantic_handle_id == first.semantic_handle_id and
                 &1.review_state == "confirmed")
           )
  end

  test "reviewed source identity promotion remains a proposal until typed Core acceptance" do
    assert {:ok, %{project: project}} =
             Launch.create_project("test-owner", %{
               "title" => "SI01 promotion",
               "kind" => "import",
               "source" => @source,
               "filename" => "promotion.fountain"
             })

    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    [first | _] = context.semantic.characters

    assert {:ok, _} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               project["id"],
               context.semantic.assessment_id,
               %{
                 "action" => "confirm",
                 "target_handle_id" => first.semantic_handle_id,
                 "payload" => %{},
                 "expected_version" => 0,
                 "command_id" => "promote-confirm",
                 "actor" => "human:test-owner"
               }
             )

    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])

    first =
      Enum.find(context.semantic.characters, &(&1.semantic_handle_id == first.semantic_handle_id))

    assert {:ok, proposal} =
             SemanticContext.save_character_promotion_candidate(
               Fount.Repo,
               "test-owner",
               project["id"],
               context.current.revision.id,
               context.semantic,
               first.semantic_handle_id
             )

    assert proposal.pointer["kind"] == "cast"

    assert Fount.Persistence.load(Fount.Repo, project["key"])
           |> elem(1)
           |> then(&map_size(&1.cast)) == 0

    assert {:ok, _accepted} =
             FountWeb.ProductionTools.accept_tool_candidate(
               Fount.Repo,
               "test-owner",
               proposal.candidate.id,
               Fount.ID.v4()
             )

    assert {:ok, accepted} = Fount.Persistence.load(Fount.Repo, project["key"])
    assert map_size(accepted.cast) == 1
    assert accepted.revision.render_hash == context.current.revision.render_hash
    refute accepted.revision.id == context.current.revision.id

    assert {:ok, historical} =
             SemanticContext.load(Fount.Repo, "test-owner", project, context.current)

    assert historical.assessment_state == :historical
    assert length(historical.review_history) == 1
    [character] = Map.values(accepted.cast)
    assert character.display_name == "GUARD"

    assert {:error, :semantic_revision_stale} =
             SemanticStore.review(
               Fount.Repo,
               "test-owner",
               project["id"],
               context.semantic.assessment_id,
               %{
                 "action" => "set_alias",
                 "target_handle_id" => first.semantic_handle_id,
                 "payload" => %{"alias" => "OLD TAB"},
                 "expected_version" => context.semantic.version,
                 "command_id" => "old-tab-after-accept",
                 "actor" => "human:test-owner"
               }
             )

    assert {:ok, refreshed} = ProjectContext.load("test-owner", project["key"])
    assert refreshed.current.revision.id == accepted.revision.id
    assert refreshed.semantic.revision_id == accepted.revision.id
    refute refreshed.semantic.assessment_id == context.semantic.assessment_id
  end

  test "manual alias, merge, split, occurrence, location hierarchy, time and undo stay source-bound" do
    assert {:ok, %{project: project}} =
             Launch.create_project("test-owner", %{
               "title" => "SI01 manual review actions",
               "kind" => "import",
               "source" => @source,
               "filename" => "manual-review.fountain"
             })

    assert {:ok, context} = ProjectContext.load("test-owner", project["key"])
    [guard_a, guard_b] = context.semantic.characters
    [place_a, place_b] = context.semantic.locations
    assessment_id = context.semantic.assessment_id

    review = fn version, command_id, action, target, payload ->
      SemanticStore.review(Fount.Repo, "test-owner", project["id"], assessment_id, %{
        "action" => action,
        "target_handle_id" => target,
        "payload" => payload,
        "expected_version" => version,
        "command_id" => command_id,
        "actor" => "human:test-owner"
      })
    end

    assert {:ok, alias_event} =
             review.(0, "alias-a", "set_alias", guard_a.semantic_handle_id, %{
               "alias" => "Station Guard"
             })

    assert {:ok, _} =
             review.(1, "merge-guards", "merge", guard_b.semantic_handle_id, %{
               "into_handle_id" => guard_a.semantic_handle_id
             })

    assert {:ok, merged} = ProjectContext.load("test-owner", project["key"])

    merged_guard =
      Enum.find(
        merged.semantic.characters,
        &(&1.semantic_handle_id == guard_a.semantic_handle_id)
      )

    assert merged_guard.aliases == ["Station Guard"]
    assert length(merged_guard.occurrences) == 2
    [moved | _] = Enum.drop(merged_guard.occurrences, 1)

    assert {:ok, split_event} =
             review.(2, "split-guard", "split", guard_a.semantic_handle_id, %{
               "local_ids" => [moved.local_id]
             })

    new_handle = split_event["payload"]["new_handle_id"]
    assert is_binary(new_handle)

    assert {:ok, _} =
             review.(3, "role-guard", "resolve_occurrence", new_handle, %{
               "local_id" => moved.local_id,
               "role" => "physical_presence"
             })

    assert {:ok, _} =
             review.(4, "retype-guard", "change_type", new_handle, %{"kind" => "document_text"})

    assert {:ok, _} = review.(5, "confirm-place", "confirm", place_a.handle_id, %{})

    assert {:ok, _} =
             review.(6, "place-alias", "set_alias", place_a.handle_id, %{
               "alias" => "North Station"
             })

    assert {:ok, _} =
             review.(7, "place-time", "set_time", place_a.handle_id, %{
               "value" => "Reviewed night"
             })

    assert {:ok, _} =
             review.(8, "place-parent", "set_location_parent", place_b.handle_id, %{
               "parent_handle_id" => place_a.handle_id
             })

    assert {:error, :location_parent_cycle} =
             review.(9, "place-cycle", "set_location_parent", place_a.handle_id, %{
               "parent_handle_id" => place_b.handle_id
             })

    assert {:ok, undo_event} =
             review.(9, "undo-alias", "undo", nil, %{"event_id" => alias_event["id"]})

    assert undo_event["new_version"] == 10

    assert {:ok, final} = ProjectContext.load("test-owner", project["key"])
    refute Enum.any?(final.semantic.characters, &("Station Guard" in &1.aliases))

    assert Enum.any?(
             final.semantic.entities,
             &(&1.handle_id == new_handle and &1.kind == "document_text" and
                 Enum.any?(&1.occurrences, fn occurrence ->
                   occurrence.role == "physical_presence"
                 end))
           )

    reviewed_place = Enum.find(final.semantic.locations, &(&1.handle_id == place_a.handle_id))
    child_place = Enum.find(final.semantic.locations, &(&1.handle_id == place_b.handle_id))
    assert reviewed_place.review_state == "confirmed"
    assert reviewed_place.aliases == ["North Station"]
    assert Enum.any?(reviewed_place.entries, &(&1.parsed_time == "Reviewed night"))
    assert child_place.parent_handle_id == place_a.handle_id
    assert Store.list_project_runs(Fount.Repo, "test-owner", project["id"], limit: 50) == []
  end

  test "database constraints reject forged owner, revision and artifact bindings" do
    {:ok, %{project: project}} =
      Launch.create_project("test-owner", %{
        "title" => "Constraint source",
        "kind" => "import",
        "source" => @source,
        "filename" => "constraints.fountain"
      })

    {:ok, %{project: other}} =
      Launch.create_project("other-owner", %{
        "title" => "Other constraint source",
        "kind" => "import",
        "source" => @source,
        "filename" => "other.fountain"
      })

    {:ok, context} = ProjectContext.load("test-owner", project["key"])
    {:ok, foreign} = ProjectContext.load("other-owner", other["key"])

    for {column, value, constraint} <- [
          {"owner_id", "other-owner", "semantic_assessment_project_source_fk"},
          {"revision_id", foreign.current.revision.id, "semantic_assessment_revision_fk"},
          {"source_artifact_id", foreign.semantic.assessment["source_artifact_id"],
           "semantic_assessment_artifact_fk"},
          {"source_sha256", "invalid", "semantic_assessment_source_hash"}
        ] do
      cast =
        if column in ["revision_id", "source_artifact_id"], do: "::text::uuid", else: "::text"

      {:error, %Postgrex.Error{postgres: %{constraint: ^constraint}}} =
        Ecto.Adapters.SQL.query(
          Fount.Repo,
          "UPDATE fount_web_semantic_assessments SET #{column}=$1#{cast} WHERE id=$2::text::uuid",
          [value, context.semantic.assessment_id]
        )
    end

    assert {:ok, reloaded} = ProjectContext.load("test-owner", project["key"])
    assert reloaded.semantic.assessment_id == context.semantic.assessment_id
  end

  test "16-byte owner and command text remain text when decoding UUID columns" do
    owner = "0123456789abcdef"
    command_id = "fedcba9876543210"

    {:ok, %{project: project}} =
      Launch.create_project(owner, %{
        "title" => "Text identities",
        "kind" => "import",
        "source" => @source,
        "filename" => "text.fountain"
      })

    {:ok, context} = ProjectContext.load(owner, project["key"])
    assert context.semantic.assessment["owner_id"] == owner

    attrs = %{
      "action" => "confirm",
      "target_handle_id" => hd(context.semantic.characters).semantic_handle_id,
      "payload" => %{},
      "expected_version" => 0,
      "command_id" => command_id,
      "actor" => "human:" <> owner
    }

    assert {:ok, event} =
             SemanticStore.review(
               Fount.Repo,
               owner,
               project["id"],
               context.semantic.assessment_id,
               attrs
             )

    assert event["owner_id"] == owner
    assert event["command_id"] == command_id

    assert {:ok, ^event} =
             SemanticStore.review(
               Fount.Repo,
               owner,
               project["id"],
               context.semantic.assessment_id,
               attrs
             )
  end

  test "persisted legacy literal cast remains unreviewed and writer-created cast stays confirmed" do
    legacy =
      @source |> Fount.parse!() |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    writer_root = Fount.Screenplay.new()
    {writer, _character} = Fount.Screenplay.add_character(writer_root, "Writer-authored Mara")

    for {root, model, origin, state} <- [
          {legacy, legacy, "legacy_literal", "unreviewed"},
          {writer_root, writer, "author_created", "confirmed"}
        ] do
      key = "si01-provenance-" <> Fount.ID.v4()
      assert {:ok, _} = Fount.Persistence.create(Fount.Repo, key, root)

      if root.revision.id != model.revision.id do
        {:ok, candidate} =
          Fount.Persistence.save_edit_candidate(Fount.Repo, key, model,
            expected_revision: root.revision.id,
            operations: []
          )

        {:ok, stored} = Fount.Persistence.candidate(Fount.Repo, candidate.id)
        {:ok, principal} = Fount.Writing.Principal.new(:human, "test-owner")
        {:ok, authority} = Fount.Writing.Authority.new(principal, model.id, [:approve])
        {:ok, approval} = Fount.Writing.Approval.direct(stored, principal, Fount.ID.v4())

        assert {:ok, _} =
                 Fount.Persistence.accept_candidate(Fount.Repo, candidate.id,
                   approval: approval,
                   authority: authority
                 )
      end

      assert {:ok, _} =
               Store.create_project(Fount.Repo, %{
                 owner_id: "test-owner",
                 screenplay_id: model.id,
                 key: key,
                 title: "Provenance",
                 import_fidelity: %{}
               })

      assert {:ok, context} = ProjectContext.load("test-owner", key)

      assert Enum.any?(
               context.semantic.characters,
               &(&1.representation == origin and &1.review_state == state)
             )

      if origin == "legacy_literal",
        do: assert(Enum.all?(context.semantic.characters, &(&1.review_state == "unreviewed")))

      assert context.current.cast == model.cast
    end
  end
end
