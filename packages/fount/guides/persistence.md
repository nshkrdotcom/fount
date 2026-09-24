# Persistence

Fount separates immutable screenplay transformations from effects, while keeping both the domain and its persistence interface in this package. `Fount.Screenplay` can be created, edited, queried, and exported in memory without starting a database. `Fount.Persistence` is the PostgreSQL transaction boundary around accepted canonical revisions. `Fount.Repo`, Ecto row schemas, migrations and composable queries all belong to Fount. The workshop configures and starts the Repo; it does not own the screenplay schema.

## Canonical relational store

The Ecto migrations ship at `Fount.Persistence.migrations_path/0`. Configure `Fount.Repo` for a PostgreSQL database, start it in your supervision tree, and run the migrations during deployment. In an application, for example:

```elixir
config :fount, Fount.Repo,
  database: "fount",
  username: "fount",
  password: System.fetch_env!("FOUNT_DATABASE_PASSWORD"),
  hostname: "localhost"
```

```elixir
children = [Fount.Repo]
{:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
Ecto.Migrator.run(Fount.Repo, Fount.Persistence.migrations_path(), :up, all: true)

model = Fount.Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [%{type: :action, text: "Mara waits."}]}])
:ok = Fount.Persistence.save(Fount.Repo, "feature", model, expected_revision: :new)
{:ok, loaded} = Fount.Persistence.load(Fount.Repo, "feature")
```

The current title, scenes, elements, dialogue turns, cast, aliases and mentions live in typed relational rows. Immutable `revisions.model` snapshots support history and undo; `load/2` rebuilds the live screenplay from current rows. A save validates references and exact mention bytes, compares the expected head, then commits a new revision, current rows, import artifact and optional acceptance provenance in one transaction. Stale saves return `{:error, {:conflict, current_revision}}`. Use `Fount.Persistence.Query` with ordinary Ecto queries for joins and pipeline selection.

The current implementation uses PostgreSQL. Ecto does not make the SQLite and PostgreSQL adapters interchangeable by configuration alone; their migrations and constraints differ. The pure screenplay API needs no running database process, but the relational workflow does.

## Compatibility stores

`Fount.Store.Filesystem` and `Fount.Store.SQLite` retain the earlier Fountain-document workflow. They persist original `.fountain` source with identity/annotation sidecar data or a v1 SQLite source/snapshot store. They do **not** expose the normalized current screenplay rows. Use them for existing documents and compatibility; import a `Fount.Document` with `Fount.Screenplay.from_document/1` to enter the canonical authoring path. An untouched imported Fountain artifact can be exported byte-for-byte with `Fount.Screenplay.to_fountain/1`; after canonical edits the exporter emits new Fountain.

For a v1 SQLite database, `Fount.Persistence.import_legacy(Fount.Repo, legacy_store, source_key, target_key)` copies its revision history and current draft to PostgreSQL as one transaction. It retains the original bytes for every imported revision and leaves the SQLite file untouched. The target key must be new. `Fount.Store.SQLite.load_revision/3` exposes a historical source document for inspection.

Filesystem writes use temporary files and renames, but the source and sidecar are not one atomic file. `expected_revision:` rejects a detected stale source before save; it is not a cross-process lock. SQLite v1 uses optional `:exqlite`; consumers of that compatibility store should add Exqlite to their own dependency list. A caller-owned Exqlite connection may be supplied with `Fount.Store.SQLite.new(conn: conn)` and must be closed by its owner.

The compatibility stores and the canonical relational store have different authorities. Do not treat a v1 sidecar snapshot as a queryable substitute for canonical rows or silently synchronize both as independent heads.
