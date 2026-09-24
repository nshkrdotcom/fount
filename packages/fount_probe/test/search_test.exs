defmodule FountProbe.SearchTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountProbe.Search

  test "search reports exact revision and excludes private notes and future scopes" do
    raw =
      "INT. ROOM - DAY\n\nMara takes the brass key. [[key means guilt]]\n\nEXT. GATE - NIGHT\n\nThe brass key opens the gate.\n"

    model = raw |> Fount.parse!() |> Screenplay.from_document()
    [first, second] = model.ir.scenes

    assert {:ok, one} = Search.find(model, "brass key", scene_ids: [first.id])
    assert one.revision_id == model.revision.id
    assert length(one.hits) == 1
    assert hd(one.hits).scene_id == first.id
    assert {:ok, two} = Search.find(model, "brass key")
    assert Enum.map(two.hits, & &1.scene_id) == [first.id, second.id]
    assert {:ok, none} = Search.find(model, "key means guilt")
    assert none.hits == []
    assert {:error, :unknown_scene} = Search.find(model, "key", scene_ids: [Fount.ID.v4()])
  end
end
