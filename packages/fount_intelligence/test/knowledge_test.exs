defmodule Fount.Intelligence.KnowledgeTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.Acquisition.{Knowledge, Views}
  alias Fount.Observe.Sandbox
  alias Fount.{Query, Screenplay}

  test "only prior on-screen scenes are measured and empty speaker access stays unknown" do
    model =
      "INT. ROOM - DAY\n\nA sealed box waits.\n\nDAN\nOpen it.\n\nEXT. ROAD - NIGHT\n\nMARA\nI killed him.\n"
      |> Fount.parse!()
      |> Screenplay.from_document(cast_resolution: :literal_cues)

    second = Enum.at(model.ir.scenes, 1)
    dan = Enum.find(Query.characters(model), &(&1.display_name == "DAN"))
    mara = Enum.find(Query.characters(model), &(&1.display_name == "MARA"))
    provider = Sandbox.new!(%{"audience" => %{"q" => 0.35}, dan.id => %{"q" => 0.35}})

    assert {:ok, report} =
             Knowledge.trace(model, "Mara killed him", second.id, [dan.id, mara.id], provider)

    assert report.status == :complete
    assert report.assessments["audience"].probability == 0.35
    assert report.assessments[dan.id].probability == 0.35
    assert report.assessments[mara.id].status == :unknown
    assert report.acquisition["scheduled"] == 2
    assert report.acquisition["received"] == 2
    assert report.acquisition["errors"] == []
    assert {:ok, view} = Views.audience_before(model, second.id)
    refute Jason.encode!(view) =~ "I killed him."
    refute Jason.encode!(report.acquisition["entries"]) =~ "I killed him."

    for entry <- report.acquisition["entries"],
        observation <- entry["observations"],
        evidence <- observation["evidence"] do
      refute get_in(evidence, ["target", "id"]) in second.element_ids
    end
  end
end
