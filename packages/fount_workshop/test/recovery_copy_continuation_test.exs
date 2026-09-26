defmodule FountWorkshop.RecoveryCopyContinuationTest do
  alias FountWorkshop.Writing.RecoveryCopy
  use ExUnit.Case, async: true

  test "a deleted scene can be restored without an inference client or new scene identities" do
    base =
      Fount.Screenplay.new(
        scenes: [
          %{heading: "INT. OFFICE - DAY", elements: [%{type: :action, text: "The key falls."}]},
          %{heading: "EXT. ROAD - DAY", elements: [%{type: :action, text: "Mara leaves."}]}
        ]
      )

    [source, _] = base.ir.scenes

    {:ok, current, _} =
      Fount.Screenplay.apply(base, [
        %{"kind" => "delete_scene", "target" => %{"kind" => "scene", "id" => source.id}}
      ])

    req = %{
      "workflow" => "recover",
      "base_revision_id" => current.revision.id,
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "adapt" => false,
        "source_revision_id" => base.revision.id,
        "source_targets" => [%{"kind" => "scene", "id" => source.id}],
        "destination" => %{"kind" => "start"}
      }
    }

    registry =
      Map.new(
        base.ir.elements ++ base.ir.scenes ++ base.ir.dialogue_blocks ++ Map.values(base.cast),
        &{&1.id, &1}
      )

    context = %{
      selection: req["selection"],
      evidence: [],
      source_models: [base, current],
      restore_registry: registry,
      data: %{
        "historical_source" => %{
          "revision_id" => base.revision.id,
          "scene_specs" => [
            %{
              "id" => source.id,
              "heading" => "INT. OFFICE - DAY",
              "number" => nil,
              "omitted" => false,
              "elements" => Enum.map(tl(source.element_ids), &%{"keep" => &1})
            }
          ]
        }
      }
    }

    assert {:ok, candidate} =
             RecoveryCopy.propose(
               current,
               req,
               %{"id" => "copy", "title" => "Restore"},
               context,
               []
             )

    assert Fount.Query.scene(candidate["screenplay"], source.id).element_ids == source.element_ids
    assert candidate["provenance"]["recovery"]["source_revision_id"] == base.revision.id
  end

  test "exact scene recovery restores confirmed cue links through dialogue block targets" do
    source =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. SHED - NIGHT",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "The key is here."}
            ]
          },
          %{heading: "EXT. ROAD - NIGHT", elements: [%{type: :action, text: "Mara leaves."}]}
        ]
      )

    {source, character} = Fount.Screenplay.add_character(source, "Mara")
    cue = Enum.find(source.ir.elements, &(&1.type == :character))
    {:ok, source} = Fount.Screenplay.link_cue(source, cue.id, character.id)
    [lost | _] = source.ir.scenes

    {:ok, current, _} =
      Fount.Screenplay.apply(source, [
        %{"kind" => "delete_scene", "target" => %{"kind" => "scene", "id" => lost.id}}
      ])

    request = %{
      "workflow" => "recover",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "adapt" => false,
        "source_targets" => [%{"kind" => "scene", "id" => lost.id}],
        "destination" => %{"kind" => "start"}
      }
    }

    context = %{
      selection: request["selection"],
      evidence: [],
      source_models: [source, current],
      restore_registry: Map.new(source.ir.elements ++ source.ir.scenes, &{&1.id, &1}),
      data: %{
        "historical_source" => %{
          "revision_id" => source.revision.id,
          "speaker_links" => %{cue.id => character.id},
          "scene_specs" => [
            %{
              "id" => lost.id,
              "heading" => "INT. SHED - NIGHT",
              "number" => nil,
              "omitted" => false,
              "elements" => Enum.map(tl(lost.element_ids), &%{"keep" => &1})
            }
          ]
        }
      }
    }

    assert {:ok, candidate} =
             RecoveryCopy.propose(
               current,
               request,
               %{"id" => "copy", "title" => "Restore"},
               context,
               []
             )

    assert Fount.Query.scene(candidate["screenplay"], lost.id)

    assert Enum.any?(Map.values(candidate["screenplay"].mentions), fn mention ->
             mention.element_id == cue.id and mention.character_id == character.id and
               mention.status == :confirmed
           end)
  end

  test "a scene copied from another screenplay gets fresh scene and element IDs" do
    source =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. FOREIGN ROOM - DAY",
            elements: [%{type: :action, text: "The brass key falls."}]
          }
        ]
      )

    base =
      Fount.Screenplay.new(
        scenes: [%{heading: "EXT. ROAD - DAY", elements: [%{type: :action, text: "Mara waits."}]}]
      )

    [foreign] = source.ir.scenes
    [existing] = base.ir.scenes

    request = %{
      "workflow" => "recover",
      "base_revision_id" => base.revision.id,
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "adapt" => false,
        "source_revision_id" => source.revision.id,
        "source_screenplay_id" => source.id,
        "cast_mapping" => %{},
        "source_targets" => [%{"kind" => "scene", "id" => foreign.id}],
        "destination" => %{"kind" => "after_scene", "after_scene_id" => existing.id}
      }
    }

    registry = Map.new(source.ir.elements ++ source.ir.scenes, &{&1.id, &1})

    context = %{
      selection: request["selection"],
      evidence: [],
      source_models: [base, source],
      restore_registry: registry,
      data: %{
        "historical_source" => %{
          "screenplay_id" => source.id,
          "revision_id" => source.revision.id,
          "scene_specs" => [
            %{
              "id" => foreign.id,
              "heading" => "INT. FOREIGN ROOM - DAY",
              "number" => nil,
              "omitted" => false,
              "elements" => Enum.map(tl(foreign.element_ids), &%{"keep" => &1})
            }
          ]
        }
      }
    }

    assert {:ok, candidate} =
             RecoveryCopy.propose(
               base,
               request,
               %{"id" => "copy", "title" => "Copy"},
               context,
               []
             )

    [_, copied] = candidate["screenplay"].ir.scenes
    assert copied.id != foreign.id
    assert Enum.all?(copied.element_ids, &(&1 not in foreign.element_ids))
    assert Enum.any?(candidate["screenplay"].ir.elements, &(&1.text == "The brass key falls."))
    assert candidate["provenance"]["recovery"]["source_screenplay_id"] == source.id
  end

  test "cross-screenplay cue links require and use explicit cast mapping" do
    source =
      Fount.Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [%{type: :character, text: "MARA"}, %{type: :dialogue, text: "Open it."}]
          }
        ]
      )

    {source, source_character} = Fount.Screenplay.add_character(source, "Mara")
    cue = Enum.find(source.ir.elements, &(&1.type == :character))
    {:ok, source} = Fount.Screenplay.link_cue(source, cue.id, source_character.id)

    base =
      Fount.Screenplay.new(
        scenes: [%{heading: "EXT. ROAD - DAY", elements: [%{type: :action, text: "Waiting."}]}]
      )

    {base, destination_character} = Fount.Screenplay.add_character(base, "Mara")
    scene = hd(source.ir.scenes)
    registry = Map.new(source.ir.elements ++ source.ir.scenes, &{&1.id, &1})

    req = %{
      "workflow" => "recover",
      "base_revision_id" => base.revision.id,
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "adapt" => false,
        "source_revision_id" => source.revision.id,
        "source_screenplay_id" => source.id,
        "source_targets" => [%{"kind" => "scene", "id" => scene.id}],
        "cast_mapping" => %{source_character.id => destination_character.id},
        "destination" => %{"kind" => "start"}
      }
    }

    context = %{
      selection: req["selection"],
      evidence: [],
      source_models: [base],
      restore_registry: registry,
      data: %{
        "historical_source" => %{
          "screenplay_id" => source.id,
          "revision_id" => source.revision.id,
          "speaker_links" => %{cue.id => source_character.id},
          "scene_specs" => [
            %{
              "id" => scene.id,
              "heading" => "INT. ROOM - DAY",
              "number" => nil,
              "omitted" => false,
              "elements" => Enum.map(tl(scene.element_ids), &%{"keep" => &1})
            }
          ]
        }
      }
    }

    assert {:ok, candidate} =
             RecoveryCopy.propose(
               base,
               req,
               %{"id" => "copy", "title" => "Copy"},
               context,
               []
             )

    copied_cue = Enum.find(candidate["screenplay"].ir.elements, &(&1.type == :character))
    assert copied_cue.id != cue.id

    assert Enum.any?(
             Map.values(candidate["screenplay"].mentions),
             &(&1.element_id == copied_cue.id and &1.character_id == destination_character.id)
           )

    assert {:error, :missing_cast_mapping} =
             RecoveryCopy.propose(
               base,
               put_in(req, ["options", "cast_mapping"], %{}),
               %{"id" => "copy", "title" => "Copy"},
               context,
               []
             )
  end
end
