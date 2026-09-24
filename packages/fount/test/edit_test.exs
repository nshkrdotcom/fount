defmodule Fount.EditTest do
  use ExUnit.Case, async: true

  test "replace dialogue patches only the target bytes and preserves target identity" do
    source = "INT. ROOM - DAY\n\nMARA\nOld line.\n\nDAN\nUntouched.\n"
    doc = Fount.parse!(source)
    [first, second] = Fount.elements(doc, :dialogue)

    {:ok, changed, change_set} = Fount.apply(doc, Fount.Edit.replace_text(first.id, "New line."))

    assert Fount.render(changed) == "INT. ROOM - DAY\n\nMARA\nNew line.\n\nDAN\nUntouched.\n"
    assert Fount.node(changed, first.id).text == "New line."
    assert Fount.node(changed, second.id).text == "Untouched."
    assert change_set.before_revision != change_set.after_revision
  end

  test "rename character updates all cue occurrences but not action mentions" do
    source = "INT. ROOM - DAY\n\nMARA enters.\n\nMARA\nHi.\n\nMARA\nAgain.\n"
    doc = Fount.parse!(source)

    {:ok, changed, _} = Fount.apply(doc, Fount.Edit.rename_character("MARA", "MARI"))

    assert length(Fount.character_cues(changed, "MARI")) == 2
    assert String.contains?(Fount.render(changed), "MARA enters.")
  end

  test "move scene preserves moved element identities" do
    source = "INT. ONE - DAY\n\nA.\n\nINT. TWO - DAY\n\nB.\n\nINT. THREE - DAY\n\nC.\n"
    doc = Fount.parse!(source)
    [one, two, three] = doc.ir.scenes
    moved_ids = MapSet.new(two.element_ids)

    {:ok, changed, _} = Fount.apply(doc, Fount.Edit.move_scene(two.id, three.id))
    [_new_one, new_three, new_two] = changed.ir.scenes

    assert Fount.node(changed, new_three.heading_id).text == "INT. THREE - DAY"
    assert Fount.node(changed, new_two.heading_id).text == "INT. TWO - DAY"
    assert MapSet.new(new_two.element_ids) == moved_ids
    assert one.id == hd(changed.ir.scenes).id
  end

  test "specialized edits preserve Fountain meaning, punctuation, and undo identities" do
    source = "INT. ROOM - DAY #4#\n\nMARA (V.O.)\nHello.\n\nEXT. ROAD - NIGHT\n\nCars pass.\n"
    doc = Fount.parse!(source)
    [first, second] = doc.ir.scenes
    [cue] = Fount.elements(doc, :character)

    {:ok, renamed, rename_change} = Fount.apply(doc, Fount.Edit.rename_character("MARA", "McKay"))
    assert String.contains?(Fount.render(renamed), "@McKay (V.O.)")
    assert Fount.node(renamed, cue.id).text == "McKay"
    assert hd(renamed.ir.scenes).id == first.id

    {:ok, headed, heading_change} = Fount.apply(renamed, Fount.Edit.set_scene_heading(first.id, "FLASHBACK - ROOM"))
    assert String.starts_with?(Fount.render(headed), ".FLASHBACK - ROOM #4#")
    assert Fount.node(headed, first.heading_id).text == "FLASHBACK - ROOM"
    assert Enum.at(headed.ir.scenes, 1).id == second.id

    assert {:ok, restored_heading} = Fount.undo(headed, heading_change)
    assert Fount.render(restored_heading) == Fount.render(renamed)
    assert Fount.node(restored_heading, first.heading_id).text == "INT. ROOM - DAY"
    assert {:ok, restored_cue} = Fount.undo(restored_heading, rename_change)
    assert Fount.render(restored_cue) == source
    assert Fount.node(restored_cue, cue.id).text == "MARA"
    assert {:ok, redone} = Fount.redo(restored_cue, rename_change)
    assert Fount.render(redone) == Fount.render(renamed)
  end

  test "scene deletion leaves adjacent outline metadata" do
    source = "# Act One\n\nINT. FIRST - DAY\n\nAction.\n\n= Next scene\n\nINT. SECOND - NIGHT\n\nMore.\n"
    doc = Fount.parse!(source)
    [first, second] = doc.ir.scenes

    {:ok, changed, _} = Fount.apply(doc, Fount.Edit.delete_scene(first.id))
    assert String.contains?(Fount.render(changed), "# Act One")
    assert String.contains?(Fount.render(changed), "= Next scene")
    assert length(changed.ir.scenes) == 1
    assert hd(changed.ir.scenes).id == second.id
  end

  test "external text replacement reports identity that cannot be reconciled" do
    doc = Fount.parse!("INT. ROOM - DAY\n\nThe old action.\n")
    old_action = hd(Fount.elements(doc, :action))

    assert {:ok, changed} = Fount.reparse(doc, "INT. ROOM - DAY\n\nA new action.\n")
    assert hd(changed.ir.scenes).id == hd(doc.ir.scenes).id
    assert hd(Fount.elements(changed, :action)).id != old_action.id
    assert Enum.any?(changed.diagnostics, &(&1.code == :identity_not_retained and &1.node_id == old_action.id))
  end

  test "structured scene and dialogue insertion reparses with stable neighboring IDs" do
    doc = Fount.parse!("INT. FIRST - DAY\n\nAn action.\n")
    original_scene = hd(doc.ir.scenes)
    action = hd(Fount.elements(doc, :action))

    {:ok, with_dialogue, _} = Fount.apply(doc, Fount.Edit.insert_dialogue_after(action.id, "McKay", "Hello."))
    assert hd(with_dialogue.ir.scenes).id == original_scene.id
    assert hd(Fount.elements(with_dialogue, :character)).text == "McKay"
    assert hd(Fount.elements(with_dialogue, :dialogue)).text == "Hello."
    assert String.contains?(Fount.render(with_dialogue), "@McKay\nHello.")

    {:ok, with_scene, _} =
      Fount.apply(
        with_dialogue,
        Fount.Edit.insert_scene_after(original_scene.id, "LATER - ROAD", [Fount.Fragment.action("A car passes.")])
      )

    assert length(with_scene.ir.scenes) == 2
    assert hd(with_scene.ir.scenes).id == original_scene.id
    assert hd(Fount.elements(with_scene, :scene_heading)).text == "INT. FIRST - DAY"
    assert Enum.at(Fount.elements(with_scene, :scene_heading), 1).text == "LATER - ROAD"
    assert Fount.validate(with_scene) == with_scene.diagnostics
  end
end
