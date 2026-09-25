defmodule Fount.InterchangeContinuationTest do
  use ExUnit.Case, async: true

  test "canonical JSON roundtrips IDs, booleans, content and source bytes" do
    bytes = "Title: The Key\r\n\r\nINT. OFFICE - DAY\r\n\r\nMara takes the key.\r\n"
    {:ok, model, []} = Fount.Interchange.read(bytes, "fountain")
    {:ok, json} = Fount.Interchange.write(model, "json", include_source: true)
    {:ok, reopened, []} = Fount.Interchange.read(json.data, "json")
    assert Fount.Screenplay.Model.content(model) == Fount.Screenplay.Model.content(reopened)
    assert Fount.Screenplay.to_fountain(reopened) == bytes
    assert model.revision.content_hash == reopened.revision.content_hash
    bad = Jason.decode!(json.data) |> put_in(["model", "revision", "content_hash"], "forged") |> Jason.encode!()
    assert {:error, :content_hash_mismatch} = Fount.Adapter.JSON.decode_model(bad)

    nested = Jason.decode!(json.data) |> put_in(["model", "revision", "unreviewed"], true) |> Jason.encode!()
    assert {:error, :unknown_nested_canonical_field} = Fount.Adapter.JSON.decode_model(nested)

    element =
      Jason.decode!(json.data) |> put_in(["model", "elements", Access.at(0), "unreviewed"], true) |> Jason.encode!()

    assert {:error, :unknown_nested_canonical_field} = Fount.Adapter.JSON.decode_model(element)

    artifact = Jason.decode!(json.data) |> put_in(["import_artifact", "unreviewed"], true) |> Jason.encode!()
    assert {:error, :unknown_artifact_field} = Fount.Adapter.JSON.decode_model(artifact)
  end

  test "a canonical scene split and merge retain body identities" do
    model =
      Fount.parse!("INT. OFFICE - DAY\n\nShe takes the key.\n\nHe shuts the door.\n")
      |> Fount.Screenplay.from_document()

    [scene] = model.ir.scenes
    [a, _b] = Enum.filter(model.ir.elements, &(&1.type == :action))
    assert {:ok, split, _} = Fount.Writing.Structure.split(model, scene.id, a.id, "EXT. DOCK - DAY")
    assert length(split.ir.scenes) == 2

    assert {:ok, merged, _} =
             Fount.Writing.Structure.merge(split, Enum.map(split.ir.scenes, & &1.id), "INT. OFFICE - DAY")

    assert Enum.map(Enum.filter(merged.ir.elements, &(&1.type == :action)), & &1.id) ==
             Enum.map(Enum.filter(model.ir.elements, &(&1.type == :action)), & &1.id)
  end
end
