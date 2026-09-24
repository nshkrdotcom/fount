defmodule Fount.PersistenceTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Fount.Persistence
  alias Fount.Persistence.Query
  alias Fount.Persistence.Schema.Mention
  alias Fount.Repo
  alias Fount.Screenplay
  alias Fount.Store.SQLite

  setup_all do
    host = System.get_env("FOUNT_TEST_PGHOST", "/var/run/postgresql")

    opts = [
      database: System.get_env("FOUNT_TEST_DATABASE", "fount_test"),
      username: System.get_env("FOUNT_TEST_USER", "home"),
      password: System.get_env("FOUNT_TEST_PASSWORD"),
      port: System.get_env("FOUNT_TEST_PORT", "5433") |> String.to_integer(),
      pool_size: 5,
      log: false
    ]

    opts =
      if String.starts_with?(host, "/"),
        do: Keyword.put(opts, :socket_dir, host),
        else: Keyword.put(opts, :hostname, host)

    start_supervised!({Repo, opts})
    Ecto.Migrator.run(Repo, Persistence.migrations_path(), :up, all: true, log: false)
    :ok
  end

  test "typed current rows answer cast, scene and dialogue queries while history stays immutable" do
    key = "test-#{Fount.ID.v4()}"

    model =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. HOUSE - DAY",
            elements: [%{type: :character, text: "MARA"}, %{type: :dialogue, text: "Come in."}]
          },
          %{heading: "EXT. ROAD - NIGHT", elements: [%{type: :action, text: "Mara drives."}]}
        ]
      )

    {model, mara} = Screenplay.add_character(model, "Mara", aliases: ["Captain Mara"])
    cue = Enum.find(model.ir.elements, &(&1.type == :character))
    {:ok, model} = Screenplay.link_cue(model, cue.id, mara.id)
    assert :ok = Persistence.save(Repo, key, model, expected_revision: :new)

    assert {:ok, loaded} = Persistence.load(Repo, key)
    assert Enum.map(loaded.ir.scenes, & &1.id) == Enum.map(model.ir.scenes, & &1.id)
    assert Enum.map(Repo.all(Query.scenes(model.id)), & &1.id) == Enum.map(model.ir.scenes, & &1.id)
    assert Enum.map(Repo.all(Query.cast(model.id)), & &1.id) == [mara.id]
    assert length(Repo.all(Query.dialogue_for(model.id, mara.id))) == 1
    assert Enum.map(Repo.all(Query.scenes_with(model.id, mara.id)), & &1.id) == [hd(model.ir.scenes).id]
    assert length(Repo.all(Query.mentions(model.id, mara.id))) == 1

    dialogue = Enum.find(model.ir.elements, &(&1.type == :dialogue))
    {:ok, changed} = Screenplay.apply(model, Fount.Edit.replace_text(dialogue.id, "Please come in."))
    assert {:error, {:conflict, _}} = Persistence.save(Repo, key, changed, expected_revision: Fount.ID.v4())
    assert :ok = Persistence.save(Repo, key, changed, expected_revision: model.revision.id)
    assert {:ok, current} = Persistence.load(Repo, key)
    assert current.revision.parent_id == model.revision.id
    assert Screenplay.node(current, dialogue.id).text == "Please come in."
    assert {:ok, old} = Persistence.at_revision(Repo, model.revision.id)
    assert Screenplay.node(old, dialogue.id).text == "Come in."
    assert {:ok, undone} = Screenplay.undo(current, old)
    assert :ok = Persistence.save(Repo, key, undone, expected_revision: current.revision.id)
    assert {:ok, restored} = Persistence.load(Repo, key)
    assert restored.revision.parent_id == current.revision.id
    assert Screenplay.node(restored, dialogue.id).text == "Come in."
    assert length(Persistence.history(Repo, key)) == 3
  end

  test "invalid byte evidence is rejected without changing the head" do
    key = "test-#{Fount.ID.v4()}"
    model = Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :character, text: "MARA"}]}])
    {model, mara} = Screenplay.add_character(model, "Mara")
    cue = Enum.find(model.ir.elements, &(&1.type == :character))
    {:ok, model} = Screenplay.link_cue(model, cue.id, mara.id)
    assert :ok = Persistence.save(Repo, key, model)

    bad = model.mentions |> Map.values() |> hd() |> Map.put(:byte_end, 900)
    changed = %{model | revision: %{model.revision | id: Fount.ID.v4()}, mentions: %{bad.id => bad}}

    assert {:error, :invalid_mention_evidence} =
             Persistence.save(Repo, key, changed, expected_revision: model.revision.id)

    assert {:ok, loaded} = Persistence.load(Repo, key)
    assert loaded.revision.id == model.revision.id
  end

  test "untouched imported Fountain bytes survive relational save and reload" do
    key = "test-#{Fount.ID.v4()}"
    bytes = "Title: Ω\r\n\r\nINT. ROOM - DAY\r\n\r\nMARA\r\nHello."
    model = bytes |> Fount.parse!() |> Screenplay.from_document()
    assert :ok = Persistence.save(Repo, key, model)
    assert {:ok, loaded} = Persistence.load(Repo, key)
    assert Screenplay.to_fountain(loaded) == bytes
  end

  test "annotations retain query semantics and provenance across relational reload" do
    key = "test-#{Fount.ID.v4()}"
    model = Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Mara waits."}]}])
    scene = hd(model.ir.scenes)

    annotation = %Fount.Annotation{
      id: Fount.ID.v4(),
      namespace: "writer",
      kind: :storyline,
      target: %Fount.Annotation.Target{node_id: scene.id},
      value: %{"thread" => "A", "beat" => "Arrival"},
      provenance: %Fount.Annotation.Provenance{producer: "writer", source_revision: model.revision.id},
      confidence: 1.0,
      dependencies: []
    }

    model = %{model | annotations: %{annotation.id => annotation}}
    assert :ok = Persistence.save(Repo, key, model)
    assert {:ok, loaded} = Persistence.load(Repo, key)
    assert [saved] = Fount.Annotations.by_kind(loaded.annotations, :storyline)
    assert saved.value == annotation.value
    assert saved.target.node_id == scene.id
    assert saved.provenance.producer == "writer"
    assert Enum.map(Repo.all(Query.storylines(model.id, "A")), & &1.id) == [annotation.id]
    assert Enum.map(Repo.all(Query.scenes_for_storyline(model.id, "A")), & &1.id) == [scene.id]
  end

  test "database rejects an occurrence attached to another screenplay" do
    first = Screenplay.new(scenes: [%{heading: "INT. ONE - DAY", elements: [%{type: :action, text: "First."}]}])
    second = Screenplay.new(scenes: [%{heading: "INT. TWO - DAY", elements: [%{type: :action, text: "Second."}]}])
    assert :ok = Persistence.save(Repo, "test-#{Fount.ID.v4()}", first)
    assert :ok = Persistence.save(Repo, "test-#{Fount.ID.v4()}", second)
    other_element = Enum.find(second.ir.elements, &(&1.type == :action))

    result =
      Repo.transaction(fn ->
        Repo.insert!(%Mention{
          id: Fount.ID.v4(),
          screenplay_id: first.id,
          element_id: other_element.id,
          role: "action",
          status: "suggested",
          surface: "Second",
          byte_start: 0,
          byte_end: 6,
          model_revision_id: first.revision.id,
          producer: "test"
        })

        case SQL.query(Repo, "SET CONSTRAINTS mention_element_scope_fk IMMEDIATE", []) do
          {:error, reason} -> Repo.rollback(reason)
          {:ok, _} -> flunk("cross-screenplay occurrence was accepted")
        end
      end)

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} = result
  end

  test "imported outline and dual-dialogue views survive the relational projection" do
    key = "test-#{Fount.ID.v4()}"
    source = File.read!(Path.join(__DIR__, "fixtures/full.fountain"))
    model = source |> Fount.parse!() |> Screenplay.from_document()
    assert :ok = Persistence.save(Repo, key, model)
    assert {:ok, loaded} = Persistence.load(Repo, key)
    assert Enum.map(loaded.ir.outline, & &1.title) == Enum.map(model.ir.outline, & &1.title)
    assert Enum.map(loaded.ir.scenes, & &1.outline_path) == Enum.map(model.ir.scenes, & &1.outline_path)
    assert Enum.map(loaded.ir.dialogue_blocks, & &1.side) == Enum.map(model.ir.dialogue_blocks, & &1.side)
    assert Screenplay.to_fountain(loaded) == source
    assert {:ok, historical} = Persistence.at_revision(Repo, model.revision.id)
    assert Enum.map(historical.ir.outline, & &1.title) == Enum.map(model.ir.outline, & &1.title)
    assert Enum.map(historical.ir.scenes, & &1.id) == Enum.map(model.ir.scenes, & &1.id)
  end

  test "unbound annotation targets cannot be saved as current facts" do
    key = "test-#{Fount.ID.v4()}"
    model = Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: []}])

    annotation = %Fount.Annotation{
      id: Fount.ID.v4(),
      namespace: "analysis",
      kind: :event,
      target: %Fount.Annotation.Target{node_id: Fount.ID.v4()},
      value: %{"event" => "arrival"},
      provenance: %Fount.Annotation.Provenance{producer: "test"}
    }

    model = %{model | annotations: %{annotation.id => annotation}}
    assert {:error, :invalid_annotation_target} = Persistence.save(Repo, key, model)
    assert {:error, :not_found} = Persistence.load(Repo, key)
  end

  test "explicit v1 SQLite import keeps historical bytes and current screenplay IDs" do
    root = Path.join(System.tmp_dir!(), "fount-v1-import-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    legacy = SQLite.new(Path.join(root, "old.sqlite3"))
    original = Fount.parse!("INT. ROOM - DAY\r\n\r\nMARA\r\nHello.")
    assert :ok = Fount.Store.save(legacy, "feature", original)
    dialogue = Enum.find(original.ir.elements, &(&1.type == :dialogue))
    {:ok, changed, _} = Fount.apply(original, Fount.Edit.replace_text(dialogue.id, "Goodbye."))
    assert :ok = Fount.Store.save(legacy, "feature", changed)

    target_key = "test-#{Fount.ID.v4()}"
    assert {:ok, imported} = Persistence.import_legacy(Repo, legacy, "feature", target_key)
    assert imported.id == original.id
    assert {:ok, loaded} = Persistence.load(Repo, target_key)
    assert loaded.id == original.id
    assert Screenplay.node(loaded, dialogue.id).text == "Goodbye."
    assert Screenplay.to_fountain(loaded) == changed.source.raw
    assert length(Persistence.history(Repo, target_key)) == 2
    assert {:ok, old} = Persistence.at_revision(Repo, hd(Persistence.history(Repo, target_key)).id)
    assert Screenplay.to_fountain(old) == original.source.raw
    assert {:ok, still_legacy} = Fount.Store.load(legacy, "feature")
    assert Fount.render(still_legacy) == changed.source.raw
  end
end
