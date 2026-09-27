defmodule Fount.Observe.PhaseTwoSceneQuestionTest do
  use ExUnit.Case, async: true
  alias Fount.Observe.{Question, Sandbox, SceneQuestion}

  defp model,
    do:
      Fount.parse!(
        "INT. HALL - NIGHT\n\nMara pockets a key. [[Private author note.]]\n\nMARA\nEmpty.\n"
      )
      |> Fount.Screenplay.from_document()

  test "a scene question returns evidence without changing the source or claiming fixture insight" do
    m = model()
    before = Fount.Screenplay.to_fountain(m)
    provider = Sandbox.new!(%{"scene_question" => %{"concealment" => 0.85}})

    assert {:ok, packet} =
             SceneQuestion.ask(provider, m, %{"kind" => "scene", "id" => hd(m.ir.scenes).id},
               concealment: Question.noul("Does Mara conceal something?")
             )

    assert packet["status"] == "available"
    [finding] = packet["findings"]
    assert finding["simulation"]
    assert finding["evidence"] != []
    assert Enum.all?(finding["evidence"], &(&1["revision_id"] == m.revision.id))
    refute Jason.encode!(packet) =~ "Private author note"
    assert Fount.Screenplay.to_fountain(m) == before
    assert packet["source_revision"] == m.revision.id
    assert packet["strategies"] == []
  end

  test "missing provider is an honest unavailable answer, never a negative scene verdict" do
    m = model()

    assert {:ok, packet} =
             SceneQuestion.ask(nil, m, %{"kind" => "scene", "id" => hd(m.ir.scenes).id},
               q: Question.noul("Is the intention clear?")
             )

    assert packet["status"] == "unavailable"
    assert packet["findings"] == []

    assert [%{"class" => "provider_unconfigured"}] =
             Enum.map(packet["errors"], &Map.take(&1, ["class"]))
  end
end
