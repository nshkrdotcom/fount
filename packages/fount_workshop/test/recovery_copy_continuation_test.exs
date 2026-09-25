defmodule FountWorkshop.RecoveryCopyContinuationTest do
  use ExUnit.Case, async: true
  test "a deleted scene can be restored without an inference client or new scene identities" do
    base = Fount.Screenplay.new(scenes: [%{heading: "INT. OFFICE - DAY", elements: [%{type: :action, text: "The key falls."}]}, %{heading: "EXT. ROAD - DAY", elements: [%{type: :action, text: "Mara leaves."}]}])
    [source, _] = base.ir.scenes
    {:ok, current, _} = Fount.Screenplay.apply(base, [%{"kind" => "delete_scene", "target" => %{"kind" => "scene", "id" => source.id}}])
    req = %{"workflow" => "recover", "base_revision_id" => current.revision.id, "selection" => %{"whole_screenplay" => true}, "constraints" => [],
      "options" => %{"adapt" => false, "source_revision_id" => base.revision.id, "source_targets" => [%{"kind" => "scene", "id" => source.id}], "destination" => %{"kind" => "start"}}}
    registry = Map.new(base.ir.elements ++ base.ir.scenes ++ base.ir.dialogue_blocks ++ Map.values(base.cast), &{&1.id, &1})
    context = %{selection: req["selection"], evidence: [], source_models: [base, current], restore_registry: registry,
      data: %{"historical_source" => %{"revision_id" => base.revision.id, "scene_specs" => [%{"id" => source.id, "heading" => "INT. OFFICE - DAY", "number" => nil, "omitted" => false, "elements" => Enum.map(tl(source.element_ids), &%{"keep" => &1})}]}}}
    assert {:ok, candidate} = FountWorkshop.Writing.RecoveryCopy.propose(current, req, %{"id" => "copy", "title" => "Restore"}, context, [])
    assert Fount.Query.scene(candidate["screenplay"], source.id).element_ids == source.element_ids
    assert candidate["provenance"]["recovery"]["source_revision_id"] == base.revision.id
  end
end
