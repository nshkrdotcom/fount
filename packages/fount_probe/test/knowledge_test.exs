defmodule FountProbe.KnowledgeTest do
  use ExUnit.Case, async: true
  alias Fount.{Query, Screenplay}
  alias FountProbe.Knowledge
  alias SystemOneSDK.Test

  test "Jev sees only prior on-screen scenes and empty speaker access stays unknown" do
    model =
      "INT. ROOM - DAY\n\nA sealed box waits.\n\nDAN\nOpen it.\n\nEXT. ROAD - NIGHT\n\nMARA\nI killed him.\n"
      |> Fount.parse!()
      |> Screenplay.from_document(cast_resolution: :literal_cues)

    second = Enum.at(model.ir.scenes, 1)
    dan = Enum.find(Query.characters(model), &(&1.display_name == "DAN"))
    mara = Enum.find(Query.characters(model), &(&1.display_name == "MARA"))

    client =
      Test.client()
      |> Test.stub_callback(fn request ->
        state = Jason.decode!(request.body)["state"]
        text = Jason.encode!(state)
        refute text =~ "I killed him."
        {:answers, [q: {:noul, 0.35}]}
      end)

    on_exit(fn -> Test.close(client) end)

    assert {:ok, report} =
             Knowledge.trace(model, "Mara killed him", second.id, [dan.id, mara.id], client)

    assert report.status == :complete
    assert report.assessments["audience"].probability == 0.35
    assert report.assessments[dan.id].probability == 0.35
    assert report.assessments[mara.id].status == :unknown
    assert length(Test.requests(client)) == 2
    assert Test.verify!(client) == :ok
  end
end
