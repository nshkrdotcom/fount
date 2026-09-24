defmodule Fount.CanonicalEditTest do
  use ExUnit.Case, async: true
  alias Fount.{Screenplay, Query}

  defp fixture do
    {:ok, doc} =
      Fount.parse(
        "Title: Tide\r\n\r\nINT. ROOM - NIGHT\r\n\r\nMARA\r\nGive me the clé.\r\n\r\nEXT. GATE - NIGHT\r\n\r\nA gate opens.\r\n"
      )

    Screenplay.from_document(doc, cast_resolution: :literal_cues)
  end

  test "typed edits keep identities, map byte spans and leave their base untouched" do
    base = fixture()
    line = Enum.find(base.ir.elements, &(&1.type == :dialogue))

    op = %{
      "kind" => "replace_text",
      "target" => %{"kind" => "element", "id" => line.id, "span" => %{"byte_start" => 12, "byte_end" => 16}},
      "value" => "key"
    }

    assert {:ok, next, changes} = Screenplay.apply(base, [op], [])
    assert Query.node(next, line.id).text == "Give me the key."
    assert Query.node(base, line.id).text == "Give me the clé."
    assert next.revision.parent_id == base.revision.id
    assert changes.base_revision == base.revision.id
    assert Fount.Validate.screenplay(next) == []
  end

  test "sequence replacement retains surviving element and block IDs" do
    base = fixture()
    [first, last] = base.ir.scenes
    cue = Enum.find(base.ir.elements, &(&1.type == :character))
    speech = Enum.find(base.ir.elements, &(&1.type == :dialogue))
    block = hd(base.ir.dialogue_blocks)

    op = %{
      "kind" => "replace_sequence",
      "value" => %{
        "scene_ids" => [first.id],
        "scenes" => [
          %{"id" => first.id, "heading" => "INT. ROOM - NIGHT", "elements" => []},
          %{
            "local_id" => "new:landing",
            "heading" => "EXT. LANDING - NIGHT",
            "elements" => [%{"keep" => cue.id}, %{"keep" => speech.id}]
          }
        ]
      }
    }

    assert {:ok, next, _} = Screenplay.apply(base, [op], [])
    assert length(next.ir.scenes) == 3
    assert List.last(next.ir.scenes).id == last.id
    assert hd(next.ir.dialogue_blocks).id == block.id
    assert Query.scene_for(next, speech.id).id != first.id
    assert Fount.Validate.screenplay(next) == []
  end

  test "a dangling dialogue edit rejects the complete batch" do
    base = fixture()
    cue = Enum.find(base.ir.elements, &(&1.type == :character))
    assert {:error, _} = Screenplay.apply(base, [%{"kind" => "delete_elements", "value" => %{"ids" => [cue.id]}}], [])
    assert Query.node(base, cue.id)
  end

  test "metadata-only edits keep exact imported bytes and unchanged render hash" do
    base = fixture()

    op = %{
      "kind" => "put_authored_item",
      "value" => %{
        "local_id" => "new:brief",
        "namespace" => "fount.writer",
        "kind" => "brief",
        "target" => %{"kind" => "screenplay", "id" => base.id},
        "value" => %{"premise" => "A debt comes due."},
        "dependencies" => [],
        "status" => "active",
        "provenance" => %{}
      }
    }

    assert {:ok, next, _} = Screenplay.apply(base, [op], [])
    assert Screenplay.to_fountain(next) == base.import.bytes
    assert next.revision.render_hash == base.revision.render_hash
    refute next.revision.content_hash == base.revision.content_hash
  end

  test "no-op batches retain the revision; foreign and duplicate retained IDs fail" do
    base = fixture()
    assert {:ok, ^base, _} = Screenplay.apply(base, [], [])

    assert {:error, _} =
             Screenplay.apply(
               base,
               [%{"kind" => "delete_scene", "target" => %{"kind" => "scene", "id" => Fount.ID.v4()}}],
               []
             )

    [scene | _] = base.ir.scenes
    line = Enum.find(base.ir.elements, &(&1.type == :dialogue))

    assert {:error, _} =
             Screenplay.apply(
               base,
               [
                 %{
                   "kind" => "replace_scene_body",
                   "target" => %{"kind" => "scene", "id" => scene.id},
                   "value" => %{"elements" => [%{"keep" => line.id}, %{"keep" => line.id}]}
                 }
               ],
               []
             )
  end

  test "literal cues populate cast without declaring attendance" do
    base = fixture()
    assert [%{display_name: "MARA"} = mara] = Query.characters(base)
    assert length(Query.character_dialogue(base, mara.id)) == 1
    assert Query.scenes_with_character(base, mara.id, role: :declared_present) == []
    assert {:ok, slice} = Fount.Slice.scene(base, hd(base.ir.scenes).id, [])
    assert slice.revision_id == base.revision.id
  end
end
