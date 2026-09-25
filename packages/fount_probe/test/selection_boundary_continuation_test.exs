defmodule FountProbe.SelectionBoundaryContinuationTest do
  use ExUnit.Case, async: true

  test "a scene selection does not widen a separate element span" do
    model =
      Fount.Screenplay.from_document(
        Fount.parse!("INT. ROOM - DAY\n\nAlpha beta gamma.\n\nEXT. STREET - DAY\n\nCars pass.\n")
      )

    [first, second] = model.ir.scenes
    element = Enum.find(model.ir.elements, &(&1.id in first.element_ids and &1.type == :action))

    selection = %{
      "targets" => [
        %{"kind" => "scene", "id" => second.id},
        %{
          "kind" => "element",
          "id" => element.id,
          "span" => %{"byte_start" => 6, "byte_end" => 10}
        }
      ]
    }

    assert {:ok, units} = FountProbe.Projection.select(model, selection)
    assert [%{"excerpt" => "beta"}] = Enum.filter(units, &(&1["target"]["id"] == element.id))
  end

  test "a semantic scene target becomes a legal end-of-scene observation" do
    model =
      Fount.Screenplay.from_document(Fount.parse!("INT. ROOM - DAY\n\nThe lamp goes dark.\n"))

    scene = hd(model.ir.scenes)

    assert {:ok, point} =
             FountProbe.Projection.resolve_point(model, %{"kind" => "scene", "id" => scene.id})

    assert {:ok, _} = FountProbe.Projection.cutoff(model, point)
    assert point["through_element_id"] == List.last(scene.element_ids)
  end
end
