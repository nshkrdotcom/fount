defmodule Fount.InterchangeContinuationTest do
  alias Fount.Adapter.JSON
  alias Fount.Screenplay.Model
  alias Fount.Writing.Structure
  use ExUnit.Case, async: true

  test "canonical JSON roundtrips IDs, booleans, content and source bytes" do
    bytes = "Title: The Key\r\n\r\nINT. OFFICE - DAY\r\n\r\nMara takes the key.\r\n"
    {:ok, model, []} = Fount.Interchange.read(bytes, "fountain")
    {:ok, json} = Fount.Interchange.write(model, "json", include_source: true)
    {:ok, reopened, []} = Fount.Interchange.read(json.data, "json")
    assert Model.content(model) == Model.content(reopened)
    assert Fount.Screenplay.to_fountain(reopened) == bytes
    assert model.revision.content_hash == reopened.revision.content_hash
    bad = Jason.decode!(json.data) |> put_in(["model", "revision", "content_hash"], "forged") |> Jason.encode!()
    assert {:error, :content_hash_mismatch} = JSON.decode_model(bad)

    nested = Jason.decode!(json.data) |> put_in(["model", "revision", "unreviewed"], true) |> Jason.encode!()
    assert {:error, :unknown_nested_canonical_field} = JSON.decode_model(nested)

    element =
      Jason.decode!(json.data) |> put_in(["model", "elements", Access.at(0), "unreviewed"], true) |> Jason.encode!()

    assert {:error, :unknown_nested_canonical_field} = JSON.decode_model(element)

    artifact = Jason.decode!(json.data) |> put_in(["import_artifact", "unreviewed"], true) |> Jason.encode!()
    assert {:error, :unknown_artifact_field} = JSON.decode_model(artifact)
  end

  test "a canonical scene split and merge retain body identities" do
    model =
      Fount.parse!("INT. OFFICE - DAY\n\nShe takes the key.\n\nHe shuts the door.\n")
      |> Fount.Screenplay.from_document()

    [scene] = model.ir.scenes
    [a, _b] = Enum.filter(model.ir.elements, &(&1.type == :action))
    assert {:ok, split, _} = Structure.split(model, scene.id, a.id, "EXT. DOCK - DAY")
    assert length(split.ir.scenes) == 2

    assert {:ok, merged, _} =
             Structure.merge(split, Enum.map(split.ir.scenes, & &1.id), "INT. OFFICE - DAY")

    assert Enum.map(Enum.filter(merged.ir.elements, &(&1.type == :action)), & &1.id) ==
             Enum.map(Enum.filter(model.ir.elements, &(&1.type == :action)), & &1.id)
  end

  test "scene split rejects a cut inside dual dialogue and merge retains the joint turn" do
    model =
      Fount.parse!("INT. OFFICE - DAY\n\nMARA\nTake the key.\n\nDAN ^\nI have it.\n\nThe door closes.\n")
      |> Fount.Screenplay.from_document(cast_resolution: :literal_cues)

    [scene] = model.ir.scenes
    [first, second] = Enum.filter(model.ir.elements, &(&1.type == :dialogue))
    action = Enum.find(model.ir.elements, &(&1.type == :action))

    assert {:error, :split_simultaneous_group} =
             Structure.split(model, scene.id, first.id, "EXT. ROAD - DAY")

    assert {:ok, split, _} =
             Structure.split(model, scene.id, second.id, "EXT. ROAD - DAY")

    assert Enum.map(split.ir.dialogue_blocks, & &1.id) ==
             Enum.map(model.ir.dialogue_blocks, & &1.id)

    assert Fount.Query.scene_for(split, action.id).id != scene.id

    assert {:ok, merged, _} =
             Structure.merge(split, Enum.map(split.ir.scenes, & &1.id), nil)

    assert Enum.map(merged.ir.dialogue_blocks, & &1.id) ==
             Enum.map(model.ir.dialogue_blocks, & &1.id)

    assert Fount.Query.scene_for(merged, action.id).id == scene.id
  end
end
