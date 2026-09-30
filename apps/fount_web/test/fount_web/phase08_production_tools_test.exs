defmodule FountWeb.Phase08ProductionToolsTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWeb.ProductionTools

  @source """
  Title: Phase 08 Tools
  Author: Fount

  INT. CAFÉ - MORNING

  ALICE studies the ledger beside BOB.

  ALICE
  The café opens before dawn.

  BOB
  Then we count twice.

  EXT. TRAIN PLATFORM - NIGHT

  ALICE waits beneath the clock.

  ALICE
  The café receipt is still in my pocket.
  """

  test "S01 literal search stays on exact revision and reports inspected/returned/truncated filters" do
    model = fixture()
    [first_scene | _] = model.ir.scenes

    assert {:ok, result} =
             ProductionTools.search(model, "café", %{
               "element_type" => "dialogue",
               "limit" => "1"
             })

    assert result.screenplay_id == model.id
    assert result.revision_id == model.revision.id
    assert result.mode == :literal_phrase
    assert result.inspected_element_count >= result.returned_hit_count
    assert result.returned_hit_count == 1
    assert result.truncated?
    assert [%{type: :dialogue, scene_id: scene_id, anchor: "node-" <> _}] = result.hits
    assert scene_id == first_scene.id

    alice = Enum.find(ProductionTools.character_profiles(model), &(&1.display_name == "ALICE"))
    assert {:ok, scoped} = ProductionTools.search(model, "café", %{"scene_id" => first_scene.id, "character_id" => alice.id})
    assert Enum.all?(scoped.hits, &(&1.scene_id == first_scene.id))
    assert scoped.filters["scene_id"] == first_scene.id
    assert scoped.filters["character_id"] == alice.id

    assert {:ok, location_scoped} = ProductionTools.search(model, "café", %{"location" => "TRAIN PLATFORM"})
    assert Enum.all?(location_scoped.hits, &(&1.scene_id != first_scene.id))

    assert {:error, :empty_query} = ProductionTools.search(model, "   ")
    assert {:error, :unknown_scene} = ProductionTools.search(model, "café", %{"scene_id" => Fount.ID.v4()})
    assert {:error, :unknown_character} = ProductionTools.search(model, "café", %{"character_id" => Fount.ID.v4()})
    assert {:error, :unknown_location} = ProductionTools.search(model, "café", %{"location" => "NOWHERE"})
    assert {:error, :invalid_element_types} = ProductionTools.search(model, "café", %{"element_type" => "made_up"})
  end

  test "S02 cast profiles use real cast IDs, aliases, confirmed mentions, appearances and dialogue counts" do
    model = fixture()
    profiles = ProductionTools.character_profiles(model)
    alice = Enum.find(profiles, &(&1.display_name == "ALICE"))

    assert is_binary(alice.id)
    assert alice.confirmed_mentions >= 2
    assert alice.appearance_count == 2
    assert alice.dialogue_block_count == 2
    assert alice.dialogue_word_count > 0
    assert is_list(alice.aliases)
    assert alice.relationship_evidence == []
  end

  test "S03 location profiles retain parsed INT/EXT, time and scene order without inventing unknowns" do
    model = fixture()
    profiles = ProductionTools.location_profiles(model)
    cafe = Enum.find(profiles, &(&1.location == "CAFÉ"))
    platform = Enum.find(profiles, &(&1.location == "TRAIN PLATFORM"))

    assert [%{ordinal: 1, parsed_context: "INT", parsed_time: "MORNING"}] = cafe.entries
    assert [%{ordinal: 2, parsed_context: "EXT", parsed_time: "NIGHT"}] = platform.entries
  end

  test "S04 note projection distinguishes active, changed and unresolved targets" do
    base = fixture()
    element = Enum.find(base.ir.elements, &(&1.type == :action))

    operation = %{
      "kind" => "put_authored_item",
      "value" => %{
        "local_id" => "new:phase08-note",
        "namespace" => "fount.writer",
        "kind" => "note",
        "target" => %{"kind" => "element", "id" => element.id},
        "value" => %{
          "title" => "Source check",
          "text" => "Human note",
          "target_sha256" => String.duplicate("0", 64),
          "bound_revision_id" => base.revision.id
        },
        "dependencies" => [%{"kind" => "element", "id" => element.id}],
        "status" => "active",
        "provenance" => %{"producer" => "writer"}
      }
    }

    assert {:ok, with_note, _} = Screenplay.apply(base, [operation])
    assert [%{target_state: "stale_changed", text: "Human note"}] = ProductionTools.notes(with_note)

    note_id = Map.keys(with_note.authored_items) |> List.first()
    assert {:ok, without_target, _} =
             Screenplay.apply(with_note, [%{"kind" => "delete_elements", "value" => %{"ids" => [element.id]}}])

    assert [%{id: ^note_id, target_state: "unresolved"}] = ProductionTools.notes(without_target)
  end

  test "S05 optional TTS is explicitly unavailable unless configured" do
    previous = Application.get_env(:fount_web, :table_read_tts_enabled)
    Application.put_env(:fount_web, :table_read_tts_enabled, false)
    on_exit(fn -> restore_env(:fount_web, :table_read_tts_enabled, previous) end)

    assert %{available?: false, label: label} = ProductionTools.tts_status()
    assert label =~ "not configured"
  end

  test "S06 usefulness records keep human outcomes separate from engineering facts and allow kept-original" do
    attrs = %{
      "task_id" => "pure-usefulness",
      "condition" => "fount_assisted",
      "outcome" => "neutral",
      "kept_original" => true,
      "preference" => "original",
      "notes" => ["No change was preferable."],
      "engineering" => %{
        "completed" => true,
        "elapsed_ms" => nil,
        "errors" => [],
        "retries" => 0,
        "resource_usage" => %{"tokens" => 0}
      }
    }

    assert {:ok, record} = FountWorkshop.Usefulness.record(attrs)
    assert record["human_response"]["kept_original"] == true
    assert record["engineering"]["completed"] == true
    refute Map.has_key?(record["engineering"], "preference")
    assert {:ok, report} = FountWorkshop.Usefulness.report([record])
    assert report["claims"]["automatic_winner"] == false
    assert report["claims"]["representative_sample"] == false
  end

  test "S07 dashboard card filtering/sorting is descriptive and bounded-input only" do
    cards = [
      %{project: %{"title" => "Beta", "key" => "beta", "synopsis" => "writer supplied"}, scene_count: 2},
      %{project: %{"title" => "Alpha", "key" => "alpha", "synopsis" => nil}, scene_count: 5}
    ]

    assert [%{project: %{"key" => "beta"}}] = ProductionTools.filter_cards(cards, "writer", "recent")
    assert Enum.map(ProductionTools.filter_cards(cards, "", "title"), & &1.project["key"]) == ["alpha", "beta"]
    assert Enum.map(ProductionTools.filter_cards(cards, "", "scenes"), & &1.scene_count) == [5, 2]
  end

  test "S04 writer notes remain distinct from measured annotation provenance" do
    base = fixture()
    action = Enum.find(base.ir.elements, &(&1.type == :action))
    annotation = %Fount.Annotation{
      id: Fount.ID.v4(),
      namespace: "fount.core",
      kind: :measured_example,
      target: %Fount.Annotation.Target{node_id: action.id},
      value: %{recorded: true},
      provenance: %Fount.Annotation.Provenance{
        producer: "FountWeb.Phase08ProductionToolsTest",
        source_revision: base.revision.id
      },
      dependencies: [action.id]
    }
    model = %{base | annotations: Fount.Annotations.put(base.annotations, annotation)}
    annotations = ProductionTools.measured_annotations(model)

    assert [%{namespace: "fount.core", kind: :measured_example, source_revision: revision}] = annotations
    assert revision == base.revision.id
    refute Enum.any?(annotations, &(&1.namespace == "fount.writer"))
    assert ProductionTools.notes(model) == []
  end

  defp fixture do
    {:ok, doc} = Fount.parse(@source)
    Screenplay.from_document(doc, cast_resolution: :literal_cues)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
