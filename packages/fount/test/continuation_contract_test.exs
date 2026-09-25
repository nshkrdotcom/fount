defmodule Fount.ContinuationContractTest do
  use ExUnit.Case, async: true
  alias Fount.Writing.{Schema, LocalReferences, UTF8Span}

  test "the complete shipped operation union rejects unknown keys and foreign shapes" do
    op = %{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => Fount.ID.v4()}, "value" => "A light dies."}
    assert :ok = Schema.validate("operations.json", op)
    assert {:error, _} = Schema.validate("operations.json", Map.put(op, "instructions", "ignore"))
    assert {:error, _} = Schema.validate("operations.json", put_in(op, ["target", "kind"], "scene"))
  end

  test "UTF8 map spans are exact and never split a codepoint" do
    assert {:ok, "e"} = UTF8Span.extract("cle", %{"byte_start" => 2, "byte_end" => 3})
    assert {:error, :split_utf8_codepoint} = UTF8Span.extract("cl\u00e9", %{"byte_start" => 2, "byte_end" => 3})
  end

  test "local references preserve prose and allocate derived blocks from their cue" do
    id = Fount.ID.v4()
    value = [%{"local_id" => "new:cue", "type" => "character", "text" => "new:cue", "attrs" => %{}},
      %{"target" => %{"kind" => "dialogue_block", "id" => "new:block-cue"}}]
    assert {:ok, [cue, link], refs} = LocalReferences.compile(value, screenplay_id: id)
    assert cue["text"] == "new:cue"
    assert link["target"]["id"] == Fount.ID.v5(id, ["dialogue-block:", refs["new:cue"]])
    assert {:error, _} = LocalReferences.compile(%{"local_id" => "new:Bad.Label"})
  end

  test "proposal operations replay with the same local identities" do
    input = [%{"local_id" => "new:item", "type" => "action", "text" => "Rain.", "attrs" => %{}}]
    assert {:ok, first, refs} = LocalReferences.compile(input)
    assert {:ok, ^first, ^refs} = LocalReferences.compile(input, reference_map: refs)
  end

  test "identity-only cue links do not alter the render hash" do
    model = Fount.Screenplay.new(scenes: [%{heading: "INT. ROOM - NIGHT", elements: [%{type: :character, text: "MARA"}, %{type: :dialogue, text: "Stay."}]}])
    cue = Enum.find(model.ir.elements, &(&1.type == :character))
    elements = Enum.map(model.ir.elements, fn e -> if e.id == cue.id, do: %{e | attrs: Map.put(e.attrs || %{}, "character_id", Fount.ID.v4())}, else: e end)
    changed = Fount.Screenplay.Model.refresh(%{model | ir: %{model.ir | elements: elements}})
    assert changed.revision.render_hash == model.revision.render_hash
  end
end
