defmodule Fount.ParserSemanticsTest do
  use ExUnit.Case, async: true

  test "parses title page, forced elements, dual dialogue, sections, and scene numbers" do
    source = File.read!(Path.join(__DIR__, "fixtures/full.fountain"))
    doc = Fount.parse!(source)

    assert Enum.map(doc.ir.title_page.entries, & &1.key) == ["Title", "Credit", "Author", "Draft date", "Contact"]

    [first, second, third] = doc.ir.scenes
    assert first.number == "1"
    assert Fount.node(doc, first.heading_id).text == "INT. KITCHEN - NIGHT"
    assert Fount.node(doc, second.heading_id).attrs.forced?
    assert third.number == "2"

    right = Enum.find(doc.ir.dialogue_blocks, &(&1.side == :right))
    left = Enum.find(doc.ir.dialogue_blocks, &(&1.id == right.dual_with))
    assert left.side == :left

    lyric = Fount.elements(doc, :lyric) |> hd()
    assert lyric.text == "A lyric line"
  end

  test "two-space dialogue line remains inside a dialogue block" do
    source = "CHARACTER\nOne.\n  \nTwo.\n"
    doc = Fount.parse!(source)
    [block] = doc.ir.dialogue_blocks
    body = Enum.map(block.body_ids, &Fount.node(doc, &1))

    assert Enum.count(body, &(&1.type == :dialogue)) == 3
    assert Enum.at(body, 1).attrs.intentional_blank?
  end

  test "first source line is classified without wrapping to the last line" do
    scene = Fount.parse!("INT. ROOM - DAY\n\nAction.\n")
    assert length(scene.ir.scenes) == 1
    assert hd(Fount.elements(scene, :scene_heading)).text == "INT. ROOM - DAY"

    dialogue = Fount.parse!("CHARACTER\nHello.\n")
    assert length(dialogue.ir.dialogue_blocks) == 1
    assert hd(Fount.elements(dialogue, :character)).text == "CHARACTER"
  end

  test "an unclosed standalone note stops at a true blank line" do
    source = "[[unfinished note\nstill note\n\nINT. ROOM - DAY\n\nAction.\n"
    doc = Fount.parse!(source)

    [note] = Fount.elements(doc, :note)
    assert note.text == "unfinished note\nstill note\n"
    assert Enum.any?(doc.diagnostics, &(&1.code == :unclosed_note))
    assert Enum.any?(doc.ir.scenes, fn scene -> Fount.node(doc, scene.heading_id).text == "INT. ROOM - DAY" end)
    assert Fount.render(doc) == source
  end
end
