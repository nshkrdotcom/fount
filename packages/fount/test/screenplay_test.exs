defmodule Fount.ScreenplayTest do
  use ExUnit.Case, async: true

  alias Fount.Adapter.JSON
  alias Fount.Screenplay

  test "typed screenplay creation, editing and export need no Fountain input" do
    screenplay =
      Screenplay.new(
        title: [{"Title", "Untitled"}],
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara waits."},
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "Come in."}
            ]
          }
        ]
      )

    assert screenplay.import == nil
    scene = hd(screenplay.ir.scenes)
    dialogue = Enum.find(screenplay.ir.elements, &(&1.type == :dialogue))
    assert length(screenplay.ir.dialogue_blocks) == 1
    assert Fount.parse!(Screenplay.to_fountain(screenplay)).ir.scenes |> length() == 1

    assert {:ok, edited} = Screenplay.apply(screenplay, Fount.Edit.replace_text(dialogue.id, "Please come in."))
    assert Screenplay.node(edited, dialogue.id).text == "Please come in."
    assert edited.revision.parent_id == screenplay.revision.id
    assert Screenplay.scene(edited, scene.id).id == scene.id
    assert String.contains?(Screenplay.to_fountain(edited), "Please come in.")

    assert {:ok, omitted} = Screenplay.apply(edited, Fount.Edit.omit_scene(scene.id))
    assert Screenplay.scene(omitted, scene.id).omitted?
    assert String.contains?(Screenplay.to_fountain(omitted), "/*")
  end

  test "untouched Fountain import remains byte-identical; model edit changes export" do
    source = "INT. ROOM - DAY\r\n\r\nMARA\r\nHello."
    imported = source |> Fount.parse!() |> Screenplay.from_document()
    assert Screenplay.to_fountain(imported) == source
    assert {:ok, unchanged} = Screenplay.export_fountain(imported)
    assert unchanged.data == source
    assert unchanged.losses == []
    dialogue = Enum.find(imported.ir.elements, &(&1.type == :dialogue))
    assert {:ok, changed} = Screenplay.apply(imported, Fount.Edit.replace_text(dialogue.id, "Goodbye."))
    refute Screenplay.to_fountain(changed) == source
    assert String.contains?(Screenplay.to_fountain(changed), "Goodbye.")
    assert {:ok, regenerated} = Screenplay.export_fountain(changed)
    assert regenerated.losses != []
  end

  test "cast links are stable and named references expose ambiguity with byte offsets" do
    screenplay =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Élodie sees Alex and Alexandra."},
              %{type: :character, text: "ALEX"},
              %{type: :dialogue, text: "Alex, wait for Élodie."}
            ]
          }
        ]
      )

    {screenplay, alex} = Screenplay.add_character(screenplay, "Alex")
    {screenplay, other} = Screenplay.add_character(screenplay, "Alexandra", aliases: ["Alex"])
    cue = Enum.find(screenplay.ir.elements, &(&1.type == :character))
    assert {:ok, linked} = Screenplay.link_cue(screenplay, cue.id, alex.id)
    assert hd(Screenplay.mentions_for(linked, alex.id)).role == :speaker_cue

    suggestions = Screenplay.suggest_mentions(linked)
    action = Enum.find(linked.ir.elements, &(&1.type == :action))
    alex_mention = Enum.find(suggestions, &(&1.element_id == action.id and &1.surface == "Alex"))
    assert alex_mention.status == :ambiguous
    assert Enum.sort(alex_mention.candidate_ids) == Enum.sort([alex.id, other.id])
    assert binary_part(action.text, alex_mention.byte_start, alex_mention.byte_end - alex_mention.byte_start) == "Alex"
    assert Enum.count(suggestions, &(&1.element_id == action.id and &1.surface == "Alex")) == 1

    dialogue = Enum.find(linked.ir.elements, &(&1.type == :dialogue))
    assert {:ok, edited} = Screenplay.apply(linked, Fount.Edit.replace_text(dialogue.id, "Go."))
    assert hd(Screenplay.mentions_for(edited, alex.id)).model_revision_id == edited.revision.id
  end

  test "moving a scene preserves identities and leaves adjacent outline elements in place" do
    model =
      Screenplay.new(
        scenes: [
          %{heading: "INT. ONE - DAY", elements: [%{type: :action, text: "One."}]},
          %{heading: "INT. TWO - DAY", elements: [%{type: :character, text: "MARA"}, %{type: :dialogue, text: "Two."}]},
          %{heading: "INT. THREE - DAY", elements: [%{type: :action, text: "Three."}]}
        ]
      )

    [one, two, three] = model.ir.scenes
    section = %Fount.IR.Element{id: Fount.ID.v4(), type: :section, text: "Act Two", attrs: %{level: 1}}
    elements = List.insert_at(model.ir.elements, 2, section)
    model = %{model | ir: %{model.ir | elements: elements}}

    assert {:ok, moved} = Screenplay.apply(model, Fount.Edit.move_scene(two.id, three.id))
    assert Enum.map(moved.ir.scenes, & &1.id) == [one.id, three.id, two.id]
    assert Enum.map(moved.ir.elements, & &1.id) |> Enum.find_index(&(&1 == section.id)) == 2

    assert Enum.find_index(moved.ir.elements, &(&1.id == section.id)) <
             Enum.find_index(moved.ir.elements, &(&1.id == three.heading_id))

    assert Enum.map(moved.ir.dialogue_blocks, & &1.cue_id) ==
             Enum.map(model.ir.dialogue_blocks, & &1.cue_id)
  end

  test "editing one element invalidates only derived claims that depend on it" do
    model =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara waits."},
              %{type: :action, text: "John arrives."}
            ]
          }
        ]
      )

    [first, second] = Enum.filter(model.ir.elements, &(&1.type == :action))

    claims =
      for element <- [first, second], into: %{} do
        id = Fount.ID.v4()

        {id,
         %Fount.Annotation{
           id: id,
           namespace: "analysis",
           kind: :beat,
           target: %Fount.Annotation.Target{node_id: element.id},
           value: %{"label" => "arrival"},
           provenance: %Fount.Annotation.Provenance{producer: "test_analyzer", source_revision: model.revision.id}
         }}
      end

    model = %{model | annotations: claims}
    assert {:ok, changed} = Screenplay.apply(model, Fount.Edit.replace_text(first.id, "Mara leaves."))
    assert Fount.Annotations.for_node(changed.annotations, first.id) == []
    assert length(Fount.Annotations.for_node(changed.annotations, second.id)) == 1
  end

  test "typed body generation places sections and synopses outside scenes" do
    model =
      Screenplay.new(
        body: [
          %{type: :section, text: "ACT ONE", attrs: %{level: 1}},
          %{type: :synopsis, text: "Mara comes home."},
          %{
            type: :scene,
            heading: "INT. HOME - NIGHT",
            elements: [
              %{type: :action, text: "Mara enters."},
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "Hello."}
            ]
          }
        ]
      )

    assert Enum.map(model.ir.elements, & &1.type) ==
             [:section, :synopsis, :scene_heading, :action, :character, :dialogue]

    assert length(model.ir.scenes) == 1
    assert length(model.ir.dialogue_blocks) == 1
    assert Enum.map(model.ir.outline, & &1.title) == ["ACT ONE"]
    assert length(Fount.parse!(Screenplay.to_fountain(model)).ir.scenes) == 1
  end

  test "scene insertion and removal retain neighboring identities and ordered dialogue" do
    model =
      Screenplay.new(
        scenes: [
          %{heading: "INT. FIRST - DAY", elements: [%{type: :action, text: "First."}]},
          %{heading: "INT. LAST - NIGHT", elements: [%{type: :action, text: "Last."}]}
        ]
      )

    [first, last] = model.ir.scenes

    insert =
      Fount.Edit.insert_scene_after(first.id, "EXT. ROAD - DAY", [
        %{type: :character, text: "MARA"},
        %{type: :dialogue, text: "Go."}
      ])

    assert {:ok, expanded} = Screenplay.apply(model, insert)
    assert [^first, inserted, ^last] = expanded.ir.scenes
    assert length(expanded.ir.dialogue_blocks) == 1

    assert Enum.map(expanded.ir.elements, & &1.text) ==
             ["INT. FIRST - DAY", "First.", "EXT. ROAD - DAY", "MARA", "Go.", "INT. LAST - NIGHT", "Last."]

    assert {:ok, restored} = Screenplay.apply(expanded, Fount.Edit.delete_scene(inserted.id))
    assert Enum.map(restored.ir.scenes, & &1.id) == [first.id, last.id]
    assert restored.ir.dialogue_blocks == []
    assert length(Fount.parse!(Screenplay.to_fountain(restored)).ir.scenes) == 2
  end

  test "undo and redo restore immutable prior and subsequent models with new revision IDs" do
    original =
      Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Mara waits."}]}])

    action = Enum.find(original.ir.elements, &(&1.type == :action))
    assert {:ok, changed} = Screenplay.apply(original, Fount.Edit.replace_text(action.id, "Mara leaves."))
    assert {:ok, undone} = Screenplay.undo(changed, original)
    assert Screenplay.node(undone, action.id).text == "Mara waits."
    assert undone.revision.id != original.revision.id
    assert undone.revision.parent_id == changed.revision.id
    assert {:ok, redone} = Screenplay.redo(undone, changed)
    assert Screenplay.node(redone, action.id).text == "Mara leaves."
    assert redone.revision.parent_id == undone.revision.id
    assert redone.revision.id != changed.revision.id
  end

  test "generated mixed-case cues and unconventional headings retain their meaning on export" do
    model =
      Screenplay.new(
        scenes: [
          %{
            heading: "THE WHITE ROOM",
            elements: [
              %{type: :character, text: "Dr. Vance"},
              %{type: :dialogue, text: "Listen."}
            ]
          }
        ]
      )

    parsed = model |> Screenplay.to_fountain() |> Fount.parse!()
    assert hd(parsed.ir.scenes).heading_id
    assert Enum.any?(parsed.ir.elements, &(&1.type == :character and &1.text == "Dr. Vance"))
    assert Enum.any?(parsed.ir.elements, &(&1.type == :dialogue and &1.text == "Listen."))
  end

  test "deleting a scene removes authored annotations targeting its deleted nodes" do
    model = Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Wait."}]}])
    scene = hd(model.ir.scenes)
    claim_id = Fount.ID.v4()

    claim = %Fount.Annotation{
      id: claim_id,
      namespace: "writer",
      kind: :beat,
      target: %Fount.Annotation.Target{node_id: scene.id},
      value: "arrival",
      provenance: %Fount.Annotation.Provenance{producer: "writer"}
    }

    model = %{model | annotations: %{claim_id => claim}}

    assert {:ok, changed} = Screenplay.apply(model, Fount.Edit.delete_scene(scene.id))
    assert changed.annotations == %{}
  end

  test "FDX crosses the canonical boundary with explicit adapter losses" do
    xml =
      "<FinalDraft><Content><Paragraph Type=\"Scene Heading\"><Text>INT. ROOM - DAY</Text></Paragraph><Paragraph Type=\"Character\"><Text>McKay</Text></Paragraph><Paragraph Type=\"Dialogue\"><Text>Fish &amp; chips.</Text></Paragraph></Content><TagData/></FinalDraft>"

    assert {:ok, model, losses} = Screenplay.from_fdx(xml)
    assert Enum.any?(losses, &String.contains?(&1, "production tags"))
    assert Enum.any?(model.ir.elements, &(&1.type == :character and &1.text == "McKay"))
    assert {:ok, exported} = Screenplay.to_fdx(model)
    assert exported.data == xml
    assert String.contains?(exported.data, "McKay")
    assert {:ok, reparsed, _} = Screenplay.from_fdx(exported.data)
    assert Enum.any?(reparsed.ir.elements, &(&1.type == :dialogue and &1.text == "Fish & chips."))

    dialogue = Enum.find(model.ir.elements, &(&1.type == :dialogue))
    assert {:ok, revised} = Screenplay.apply(model, Fount.Edit.replace_text(dialogue.id, "Go & wait."))
    assert {:ok, regenerated} = Screenplay.to_fdx(revised)
    assert String.contains?(regenerated.data, "Go &amp; wait.")
    assert Enum.any?(regenerated.losses, &String.contains?(&1, "production tags"))
  end

  test "literal scene numbering survives canonical edit, export, parse and reload" do
    model = Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: []}])
    scene = hd(model.ir.scenes)
    assert {:ok, numbered} = Screenplay.apply(model, Fount.Edit.set_scene_number(scene.id, "12A"))
    assert Screenplay.scene(numbered, scene.id).number == "12A"
    source = Screenplay.to_fountain(numbered)
    assert String.contains?(source, "#12A#")
    assert hd(Fount.parse!(source).ir.scenes).number == "12A"
    assert {:ok, cleared} = Screenplay.apply(numbered, Fount.Edit.set_scene_number(scene.id, nil))
    refute String.contains?(Screenplay.to_fountain(cleared), "#12A#")
  end

  test "JSON projection exposes canonical cast and occurrence evidence" do
    model =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "Go."}
            ]
          }
        ]
      )

    {model, mara} = Screenplay.add_character(model, "Mara")
    cue = Enum.find(model.ir.elements, &(&1.type == :character))
    {:ok, model} = Screenplay.link_cue(model, cue.id, mara.id)

    assert {:ok, projection} = JSON.export(model, projection: true)
    assert {:ok, data} = Jason.decode(projection.data)
    assert hd(data["cast"])["id"] == mara.id
    assert hd(data["mentions"])["character_id"] == mara.id
    assert data["source"] == nil
  end

  test "specialized cue change forces mixed case while preserving cue identity" do
    model =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "Hello."}
            ]
          }
        ]
      )

    cue = Enum.find(model.ir.elements, &(&1.type == :character))
    {model, character} = Screenplay.add_character(model, "Mara")
    {:ok, model} = Screenplay.link_cue(model, cue.id, character.id)
    assert {:ok, renamed} = Screenplay.apply(model, Fount.Edit.set_character_cue(cue.id, "Dr. Vance"))
    assert Screenplay.node(renamed, cue.id).text == "Dr. Vance"
    assert hd(Screenplay.mentions_for(renamed, character.id)).surface == "Dr. Vance"

    assert Enum.any?(
             Fount.parse!(Screenplay.to_fountain(renamed)).ir.elements,
             &(&1.type == :character and &1.text == "Dr. Vance")
           )
  end

  test "semantic diff reports ID-level text change and scene movement" do
    original =
      Screenplay.new(
        scenes: [
          %{heading: "INT. A - DAY", elements: [%{type: :action, text: "One."}]},
          %{heading: "INT. B - DAY", elements: [%{type: :action, text: "Two."}]}
        ]
      )

    [first, second] = original.ir.scenes
    action = Enum.find(original.ir.elements, &(&1.text == "One."))

    {:ok, changed} =
      Screenplay.apply(original, [
        Fount.Edit.replace_text(action.id, "Revised."),
        Fount.Edit.move_scene(first.id, second.id)
      ])

    diff = Screenplay.diff(original, changed)
    assert diff.elements.changed == [action.id]
    assert diff.scenes.moved == [second.id, first.id]
    assert diff.elements.added == []
    assert diff.elements.removed == []
  end

  test "character rename plans confirmed cues and leaves literary references for review" do
    model =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara waits."},
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "Where is Mara?"}
            ]
          }
        ]
      )

    {model, mara} = Screenplay.add_character(model, "Mara")
    cue = Enum.find(model.ir.elements, &(&1.type == :character))
    {:ok, model} = Screenplay.link_cue(model, cue.id, mara.id)

    assert {:ok, plan} = Screenplay.plan_character_rename(model, mara.id, "Dr. Vance")
    assert length(plan.cue_operations) == 1
    assert Enum.map(plan.review, & &1.role) == [:action, :dialogue_reference]
    assert {:ok, renamed} = Screenplay.accept_character_rename(model, plan)
    assert renamed.cast[mara.id].display_name == "Dr. Vance"
    assert Screenplay.node(renamed, cue.id).text == "Dr. Vance"
    assert String.contains?(Screenplay.to_fountain(renamed), "@Dr. Vance")
    assert Enum.any?(renamed.ir.elements, &(&1.type == :action and &1.text == "Mara waits."))
    assert Enum.any?(renamed.ir.elements, &(&1.type == :dialogue and &1.text == "Where is Mara?"))
    assert {:error, {:stale_rename_plan, _}} = Screenplay.accept_character_rename(renamed, plan)
  end
end
