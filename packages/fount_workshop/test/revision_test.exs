defmodule FountWorkshop.RevisionTest do
  use ExUnit.Case, async: false

  alias Fount.Store.Filesystem

  setup do
    root = Path.join(System.tmp_dir!(), "fount-workshop-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    %{store: Filesystem.new(root), root: root}
  end

  test "a model proposal previews a source-backed scene edit and acceptance reloads it", %{
    store: store
  } do
    source = "INT. ROOM - DAY\n\nMARA\nOld line.\n\nEXT. ROAD - NIGHT\n\nUntouched.\n"
    doc = Fount.parse!(source)
    assert :ok = Fount.Store.save(store, "main", doc)
    scene = hd(Fount.scenes(doc))
    dialogue = hd(Fount.elements(doc, :dialogue))
    assert {:ok, context} = FountWorkshop.context(doc, scene.id)
    assert context.revision == doc.revision.id
    assert String.contains?(context.source, "Old line.")

    client =
      Inference.client!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        model: "test",
        adapter_opts: [
          response_text:
            Jason.encode!(%{
              "operations" => [
                %{"kind" => "replace_text", "target" => dialogue.id, "value" => "Sharper line."}
              ]
            })
        ]
      )

    assert {:ok, proposal} = FountWorkshop.propose(context, "Sharpen Mara's line", client)
    assert {:ok, preview} = FountWorkshop.preview(doc, proposal)
    assert String.contains?(Fount.render(preview.document), "Sharper line.")
    assert String.contains?(Fount.render(preview.document), "Untouched.")
    assert Fount.node(preview.document, dialogue.id).text == "Sharper line."
    assert preview.source_diff != []
    assert preview.semantic_diff.modified != []
    assert File.read!(Path.join(store.root, "main.fountain")) == source

    assert :ok = FountWorkshop.accept(store, "main", preview, doc.revision.id)
    assert {:ok, loaded} = Fount.Store.load(store, "main")
    assert Fount.render(loaded) == Fount.render(preview.document)
    assert Fount.node(loaded, dialogue.id).text == "Sharper line."
    assert FountWorkshop.Acceptance.any_for?(store, "main")

    {:ok, nicholl} = FountWorkshop.Submission.profile(:nicholl_2026_27)

    checked =
      FountWorkshop.Submission.check_saved(
        store,
        "main",
        loaded,
        %{
          pages: 90,
          blank_pages: [],
          source_revision: loaded.revision.id,
          page_size: :us_letter,
          courier_prime?: true
        },
        nicholl
      )

    assert :known_ai_origin_conflicts_with_target_rule in checked.requires_writer_review
  end

  test "invalid proposal targets and stale acceptance fail without overwriting source", %{
    store: store
  } do
    doc = Fount.parse!("INT. ROOM - DAY\n\nMARA\nOld line.\n")
    :ok = Fount.Store.save(store, "main", doc)
    scene = hd(Fount.scenes(doc))
    {:ok, context} = FountWorkshop.context(doc, scene.id)

    assert {:error, %Jason.DecodeError{}} = FountWorkshop.Proposal.decode("{broken", context)

    assert {:error, :unsupported_operation} =
             FountWorkshop.Proposal.decode(
               %{
                 "operations" => [
                   %{"kind" => "delete_scene", "target" => scene.id, "value" => ""}
                 ]
               },
               context
             )

    assert {:error, {:invalid_target, "missing"}} =
             FountWorkshop.Proposal.decode(
               %{
                 "operations" => [
                   %{"kind" => "replace_text", "target" => "missing", "value" => "x"}
                 ]
               },
               context
             )

    dialogue = hd(Fount.elements(doc, :dialogue))

    {:ok, proposal} =
      FountWorkshop.Proposal.decode(
        %{
          "operations" => [
            %{"kind" => "replace_text", "target" => dialogue.id, "value" => "New."}
          ]
        },
        context
      )

    {:ok, preview} = FountWorkshop.preview(doc, proposal)
    File.write!(Path.join(store.root, "main.fountain"), "INT. ROOM - DAY\n\nExternally edited.\n")

    assert {:error, {:conflict, _actual}} =
             FountWorkshop.accept(store, "main", preview, doc.revision.id)

    assert File.read!(Path.join(store.root, "main.fountain")) ==
             "INT. ROOM - DAY\n\nExternally edited.\n"
  end
end
