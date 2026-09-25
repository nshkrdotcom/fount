defmodule FountProbe.AdjacentExtractionTest do
  use ExUnit.Case, async: true

  test "adjacent scenes provide read-only context without becoming extraction targets" do
    model =
      Fount.Screenplay.new(
        scenes: [
          %{heading: "INT. ONE - DAY", elements: [%{type: :action, text: "Mara takes the key."}]},
          %{heading: "INT. TWO - DAY", elements: [%{type: :action, text: "Mara hides it."}]},
          %{heading: "INT. THREE - DAY", elements: [%{type: :action, text: "Dan asks for it."}]}
        ]
      )

    [before, selected, after_scene] = model.ir.scenes

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        adapter_opts: [
          response_text: Jason.encode!(%{"summary" => "Mara hides the key.", "records" => []})
        ]
      )

    assert {:ok, report} =
             FountProbe.run(
               model,
               "extract_story",
               %{
                 "selection" => %{"targets" => [%{"kind" => "scene", "id" => selected.id}]},
                 "kinds" => ["events"],
                 "adjacent_scenes" => 1
               },
               %{inference: client}
             )

    assert report.status == "complete"
    assert report.coverage["inspected_scene_ids"] == [selected.id]
    assert report.coverage["context_scene_ids"] == [before.id, after_scene.id]
    assert Enum.all?(report.evidence, &(&1["target"]["id"] in selected.element_ids))
    refute Map.has_key?(report.coverage, "unimplemented_options")
  end
end
