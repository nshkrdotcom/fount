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
end
