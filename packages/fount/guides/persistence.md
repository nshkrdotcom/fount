# Persistence

`Fount.Screenplay` parses, edits, queries and exports a draft in memory.
`Fount.Persistence` stores accepted revisions, historical values, writing
sessions, candidates and reports in PostgreSQL. The Repo is started only by an
application or an explicit integration command; importing a screenplay does
not open a database connection.

## Fresh database

The current schema is defined by the ordered migrations under `priv/repo/migrations/`.
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
{:ok, edited, changes} = Fount.Screenplay.apply(accepted, operations, [])

# Post-genesis edits are saved as candidates; save/save_edit do not move canon.
{:ok, candidate} = Fount.Persistence.save_edit_candidate(Fount.Repo, "draft", edited,
  expected_revision: accepted.revision.id,
  operations: changes.operations)

{:ok, principal} = Fount.Writing.Principal.new(:human, authenticated_writer_id)
{:ok, authority} = Fount.Writing.Authority.new(principal, root.id, [:approve])

# The trusted caller creates and durably retains this UUID and exact payload
# before the first acceptance attempt, then reuses both after a lost response.
{:ok, approval} = Fount.Writing.Approval.direct(candidate, principal, stable_approval_id)
{:ok, _} = Fount.Persistence.accept_candidate(Fount.Repo, candidate.id,
  approval: approval, authority: authority)
```

`save/4` and `save_edit/4` are retained migration surfaces, but a changed
post-genesis screenplay now returns `{:error, :approval_required}` instead of
advancing the accepted head. `save_edit_candidate/4` is the Core manual-edit
path. Generated work continues to save a writing session and candidate.
Acceptance always goes through `accept_candidate/3` with a typed
`Fount.Writing.Approval` and a separately constructed trusted
`Fount.Writing.Authority`.

Reviews bind the exact candidate/base/content hash, report IDs and stored
required-check fingerprint. Required deterministic checks cannot be overridden.
Only a human may override an explicitly allowlisted semantic requirement, with
a nonblank reason; agent/service approvals cannot carry overrides. This direct
Phase-01 API currently requires reviewer and approver to be the same principal.
Acceptance compares the current head and candidate base in one transaction; a
stale base returns an error without changing canon. The old actor-string review
shape is not a writable compatibility path.

`load_revision/3` reconstructs a historical or candidate value using the same
loader. `history/3` lists revisions. An imported, untouched Fountain artifact
can be exported byte for byte; after edits Fount generates a new Fountain
rendering. Relational rows are revision-scoped, and the revision also stores a
canonical model snapshot used by the shared loader.

## Durable derived analysis

Phase 10 adds `Fount.Persistence.Analysis` as a **data-only** persistence boundary for derived screenplay intelligence. It stores exact analysis-run identity, reusable immutable measurement results, freshly materialized revision-bound observations, dependency history, actual resource usage, and content-addressed project analysis assets. It does not interpret measurements, call providers, decide recomputation policy, or change the accepted screenplay revision.

Reusable measurement rows are privacy-namespaced and keyed by Observe's existing semantic cache identity. A screenplay edit never deletes those rows; changed semantic input, output contract, model fingerprint, calibration/lens content, or context naturally produces a different key. Explicit cache eviction is a resource policy and does not delete analysis runs, observations, candidate lineage, or canonical history.

Analysis observations are stored only when their target/evidence provenance matches the exact run screenplay/revision. Cross-revision reuse therefore reuses the immutable `MeasurementResult` while Observe creates a fresh current-revision `Observation`.