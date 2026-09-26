# Persistence

`Fount.Screenplay` parses, edits, queries and exports a draft in memory.
`Fount.Persistence` stores accepted revisions, historical values, writing
sessions, candidates and reports in PostgreSQL. The Repo is started only by an
application or an explicit integration command; importing a screenplay does
not open a database connection.

## Fresh database

The current schema is the single migration under `priv/repo/migrations/`.
Select a new database explicitly with `FOUNT_DATABASE_URL`, then migrate it:

```sh
cd packages/fount
FOUNT_DATABASE_URL=postgres://user@localhost/fount_dev mix ecto.migrate
```

Do not run this migration over an old Fount schema. This greenfield version has
no SQLite import adapter. Fountain and FDX files remain real import/export
formats; `Fount.Screenplay.from_document/1` converts a parsed Fountain document
into the canonical model.

The application starts `Fount.Repo` with its configured URL before calling
persistence. A minimal application flow is:

```elixir
root = Fount.Screenplay.new()
{:ok, _} = Fount.Persistence.create(Fount.Repo, "draft", root)
{:ok, accepted} = Fount.Persistence.load(Fount.Repo, "draft")
{:ok, candidate, changes} = Fount.Screenplay.apply(accepted, operations, [])
{:ok, _} = Fount.Persistence.save_edit(Fount.Repo, "draft", candidate,
  expected_revision: accepted.revision.id)
```

Use `save_edit` for a direct writer edit. Generative work should save a writing
session and candidate, then use `FountWorkshop.Review.accept/4` after an
explicit review. Acceptance checks the current head and candidate base in one
transaction. A stale base returns an error without changing the accepted head.

`load_revision/3` reconstructs a historical or candidate value using the same
loader. `history/3` lists revisions. An imported, untouched Fountain artifact
can be exported byte for byte; after edits Fount generates a new Fountain
rendering. Relational rows are revision-scoped, and the revision also stores a
canonical model snapshot used by the shared loader.
