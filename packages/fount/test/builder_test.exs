defmodule Fount.BuilderTest do
  use ExUnit.Case, async: true

  alias Fount.{Builder, Fragment}

  test "structured fragments become ordinary source-backed screenplay nodes" do
    builder =
      Builder.new(newline: "\r\n")
      |> Builder.title("Title", "Generated")
      |> Builder.section("Act One")
      |> Builder.synopsis("The setup")
      |> Builder.scene("FLASHBACK - ROOM", [
        Fragment.action("A light flickers."),
        Fragment.dialogue("McKay", ["First line.", "", "Second line."], parenthetical: "whispering"),
        Fragment.transition("DISSOLVE TO:"),
        Fragment.note("Production thought")
      ])
      |> Builder.page_break()

    assert {:ok, doc} = Builder.to_document(builder)
    assert Fount.render(doc) == Builder.to_fountain(builder)
    assert doc.source.newline_style == :crlf
    assert hd(doc.ir.title_page.entries).values == ["Generated"]
    assert hd(Fount.elements(doc, :scene_heading)).text == "FLASHBACK - ROOM"
    assert hd(Fount.elements(doc, :character)).text == "McKay"
    assert length(Fount.elements(doc, :dialogue)) == 3
    assert length(Fount.elements(doc, :parenthetical)) == 1
    assert length(Fount.elements(doc, :transition)) == 1
    assert length(Fount.elements(doc, :note)) == 1
    assert length(Fount.elements(doc, :page_break)) == 1
  end
end
