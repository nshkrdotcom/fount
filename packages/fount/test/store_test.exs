defmodule Fount.StoreTest do
  use ExUnit.Case, async: false

  setup do
    root = Path.join(System.tmp_dir!(), "fount-store-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "filesystem store keeps Fountain canonical and restores IDs", %{root: root} do
    store = Fount.Store.Filesystem.new(root)
    doc = Fount.parse!("INT. ROOM - DAY\n\nMARA\nHello.\n")
    original_ids = Enum.map(doc.ir.elements, & &1.id)

    assert :ok = Fount.Store.save(store, "drafts/main", doc)
    assert File.read!(Path.join(root, "drafts/main.fountain")) == doc.source.raw
    assert {:ok, loaded} = Fount.Store.load(store, "drafts/main")
    assert Enum.map(loaded.ir.elements, & &1.id) == original_ids
  end

  test "sqlite store saves current document and revision history", %{root: root} do
    store = Fount.Store.SQLite.new(Path.join(root, "fount.sqlite3"))
    doc = Fount.parse!("INT. ROOM - DAY\n\nMARA\nHello.\n")
    :ok = Fount.Store.save(store, "main", doc)

    [dialogue] = Fount.elements(doc, :dialogue)
    {:ok, changed, _} = Fount.apply(doc, Fount.Edit.replace_text(dialogue.id, "Changed."))
    :ok = Fount.Store.save(store, "main", changed)

    assert {:ok, loaded} = Fount.Store.load(store, "main")
    assert Fount.render(loaded) == Fount.render(changed)
    assert {:ok, history} = Fount.Store.SQLite.history(store, "main")
    assert length(history) == 2
  end
end
