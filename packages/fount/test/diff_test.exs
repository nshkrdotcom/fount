defmodule Fount.DiffTest do
  use ExUnit.Case, async: true

  test "semantic diff distinguishes modified stable nodes" do
    doc = Fount.parse!("INT. ROOM - DAY\n\nMARA\nOld.\n")
    [dialogue] = Fount.elements(doc, :dialogue)
    {:ok, changed, _} = Fount.apply(doc, Fount.Edit.replace_text(dialogue.id, "New."))

    diff = Fount.Diff.semantic(doc, changed)
    assert Enum.any?(diff.modified, &(&1.id == dialogue.id))
  end
end
