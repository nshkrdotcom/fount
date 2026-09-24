defmodule Fount.LosslessFountainTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "untouched parse/render is byte-identical for generated UTF-8 Fountain-like text" do
    line =
      StreamData.string(:printable, max_length: 60)
      |> StreamData.map(&String.replace(&1, ["\r", "\n"], ""))

    eol = StreamData.member_of(["\n", "\r\n", "\r", ""])

    check all pairs <- StreamData.list_of(StreamData.tuple({line, eol}), max_length: 80) do
      source = Enum.map_join(pairs, fn {content, terminator} -> content <> terminator end)
      {:ok, doc} = Fount.parse(source)
      assert Fount.render(doc) == source
    end
  end

  test "fixture round-trips exactly and exposes structured elements" do
    source = File.read!(Path.join(__DIR__, "fixtures/full.fountain"))
    {:ok, doc} = Fount.parse(source, document_id: "00000000-0000-5000-8000-000000000001")

    assert Fount.render(doc) == source
    assert length(doc.ir.scenes) == 3
    assert Enum.any?(doc.ir.elements, &(&1.type == :section and &1.text == "ACT ONE"))
    assert Enum.any?(doc.ir.elements, &(&1.type == :synopsis))
    assert Enum.any?(doc.ir.elements, &(&1.type == :page_break))
    assert Enum.any?(doc.ir.elements, &(&1.type == :boneyard))
    assert Enum.any?(doc.ir.dialogue_blocks, &(&1.side == :right))
    assert Fount.validate(doc) == doc.diagnostics
  end
end
