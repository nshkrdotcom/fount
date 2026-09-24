defmodule Fount.StoreTest do
  use ExUnit.Case, async: false

  alias Fount.Store.{Filesystem, Snapshot, SQLite}

  setup do
    root = Path.join(System.tmp_dir!(), "fount-store-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "filesystem store keeps Fountain canonical and restores IDs", %{root: root} do
    store = Filesystem.new(root)
    doc = Fount.parse!("INT. ROOM - DAY\n\nMARA\nHello.\n")
    original_ids = Enum.map(doc.ir.elements, & &1.id)

    assert :ok = Fount.Store.save(store, "drafts/main", doc)
    assert File.read!(Path.join(root, "drafts/main.fountain")) == doc.source.raw
    assert {:ok, loaded} = Fount.Store.load(store, "drafts/main")
    assert Enum.map(loaded.ir.elements, & &1.id) == original_ids
  end

  test "sqlite store saves current document and revision history", %{root: root} do
    store = SQLite.new(Path.join(root, "fount.sqlite3"))
    doc = Fount.parse!("INT. ROOM - DAY\n\nMARA\nHello.\n")
    :ok = Fount.Store.save(store, "main", doc)

    [dialogue] = Fount.elements(doc, :dialogue)
    {:ok, changed, _} = Fount.apply(doc, Fount.Edit.replace_text(dialogue.id, "Changed."))
    :ok = Fount.Store.save(store, "main", changed)

    assert {:ok, loaded} = Fount.Store.load(store, "main")
    assert Fount.render(loaded) == Fount.render(changed)
    assert loaded.revision.id == changed.revision.id
    assert Enum.map(loaded.ir.elements, & &1.id) == Enum.map(changed.ir.elements, & &1.id)
    assert {:ok, history} = SQLite.history(store, "main")
    assert length(history) == 2
    assert {:ok, previous} = SQLite.load_revision(store, "main", doc.revision.id)
    assert Fount.render(previous) == Fount.render(doc)
    assert previous.revision.id == doc.revision.id
  end

  test "sidecar preserves title identity and annotation queries after reopen", %{root: root} do
    store = Filesystem.new(root)
    doc = Fount.parse!("Title: First Draft\n\nINT. ROOM - DAY\n\nMARA\nHi.\n")
    title_id = hd(doc.ir.title_page.entries).id
    {:ok, analyzed} = Fount.analyze(doc, Fount.Analyzers.CharacterEntities)
    assert length(Fount.Annotations.by_kind(analyzed.annotations, :character_entity)) == 1

    assert :ok = Fount.Store.save(store, "main", analyzed)
    assert {:ok, loaded} = Fount.Store.load(store, "main")
    assert hd(loaded.ir.title_page.entries).id == title_id
    assert hd(Enum.filter(loaded.cst.nodes, &(&1.type == :title_page))).id == title_id
    assert length(Fount.Annotations.by_kind(loaded.annotations, :character_entity)) == 1

    assert {:ok, external_edit} = Fount.reparse(loaded, "Title: First Draft\n\nINT. ROOM - DAY\n\nNo dialogue.\n")
    assert hd(external_edit.ir.title_page.entries).id == title_id
    assert Fount.Annotations.by_kind(external_edit.annotations, :character_entity) == []
  end

  test "a unique title-page field retains identity when its value and position change" do
    doc = Fount.parse!("Title: First\nAuthor: Writer\n\nINT. ROOM - DAY\n")
    old_title = hd(doc.ir.title_page.entries)

    assert {:ok, changed} =
             Fount.reparse(doc, "Credit: Written by\nTitle: Second\nAuthor: Writer\n\nINT. ROOM - DAY\n")

    new_title = Enum.find(changed.ir.title_page.entries, &(&1.key == "Title"))
    assert new_title.id == old_title.id
    assert Enum.find(changed.cst.nodes, &(&1.type == :title_page and &1.attrs.key == "Title")).id == old_title.id
  end

  test "filesystem save detects an externally changed source and stale sidecar drops derived analysis", %{root: root} do
    store = Filesystem.new(root)
    doc = Fount.parse!("INT. ROOM - DAY\n\nMARA\nHi.\n")
    {:ok, analyzed} = Fount.analyze(doc, Fount.Analyzers.CharacterEntities)
    assert :ok = Fount.Store.save(store, "main", analyzed, expected_revision: :new)
    path = Path.join(root, "main.fountain")
    File.write!(path, "INT. ROOM - DAY\n\nMARA\nHello.\n")

    assert {:error, {:conflict, _}} = Fount.Store.save(store, "main", analyzed, expected_revision: doc.revision.id)
    assert {:ok, loaded} = Fount.Store.load(store, "main")
    assert Enum.any?(loaded.diagnostics, &(&1.code == :sidecar_source_changed))
    assert Fount.Annotations.by_kind(loaded.annotations, :character_entity) == []
    assert Fount.render(loaded) == File.read!(path)
  end

  test "malformed sidecar is reported instead of silently inventing identity", %{root: root} do
    store = Filesystem.new(root)
    doc = Fount.parse!("INT. ROOM - DAY\n")
    :ok = Fount.Store.save(store, "main", doc)
    File.write!(Path.join(root, "main.fount.json"), "{bad json")
    assert {:error, :malformed_sidecar} = Fount.Store.load(store, "main")

    malformed =
      doc
      |> Snapshot.dump()
      |> Map.put("identity_anchors", ["not an anchor"])
      |> Jason.encode!()

    File.write!(Path.join(root, "main.fount.json"), malformed)
    assert {:error, :malformed_sidecar} = Fount.Store.load(store, "main")
  end

  test "sqlite accepts an initialized caller-owned connection and checks revisions", %{root: root} do
    path = Path.join(root, "owned.sqlite3")
    store = SQLite.new(path)
    assert :ok = SQLite.init(store)
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    try do
      owned = SQLite.new(conn: conn)
      doc = Fount.parse!("INT. ROOM - DAY\n")
      assert :ok = Fount.Store.save(owned, "main", doc, expected_revision: :new)
      assert {:error, {:conflict, _}} = Fount.Store.save(owned, "main", doc, expected_revision: "wrong")
      assert {:ok, loaded} = Fount.Store.load(owned, "main")
      assert Fount.render(loaded) == Fount.render(doc)
    after
      Exqlite.Sqlite3.close(conn)
    end
  end

  test "sqlite can initialize a caller-owned in-memory connection" do
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")

    try do
      store = SQLite.new(conn: conn)
      assert {:error, :schema_not_initialized} = Fount.Store.load(store, "main")
      assert :ok = SQLite.init(store)
      doc = Fount.parse!("INT. MEMORY - DAY\n")
      assert :ok = Fount.Store.save(store, "main", doc, expected_revision: :new)
      assert {:ok, loaded} = Fount.Store.load(store, "main")
      assert Fount.render(loaded) == Fount.render(doc)
    after
      Exqlite.Sqlite3.close(conn)
    end
  end
end
