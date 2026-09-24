# Changes and representation status

The machine-readable overlay manifest is the authoritative file inventory.

New files use `Fount.Writing.*`, `FountProbe.Writing.*`, and
`FountWorkshop.Writing.*` namespaces to preserve recovered work without silently
replacing uninspected implementations. These are integration components, not a
claim that the specification's public APIs have been migrated.

The Workshop dependency declaration is extended where its source manifest
contains the ordinary `deps` function. Inspect it locally and resolve the actual
graph. The new Probe manifest uses the three supplied repository layouts.
Existing lockfile bytes are retained. A newly created Probe lockfile is empty
when no resolved prior lock exists: this explicitly means **unresolved**, not a
fabricated lock. Run `mix deps.get` locally and include the resulting lockfiles
in the completed release.

Original Fountain parsing code is not replaced with a new parser. The original
fixture and reference contracts are copied as assets. Reference SQL under
`priv/writing_contracts/` is not being represented as an executed Ecto migration.

This delivery does not assert the old stores/migration chain were removed or the
new revision-scoped schema was installed. Complete those changes together with
all affected callers, tests, configuration and documentation. Use a fresh,
explicitly selected database and never automatically drop an existing database.

Content-hash semantics require a domain projection excluding revision metadata,
source offsets/blobs, generated provenance and note-resolution audit IDs while
retaining authored wording/status. The new canonical JSON encoder alone does
not supply that projection.

No compatibility shim or direct provider bypass is introduced. Integration
should use the specified APIs rather than keeping duplicate long-term models.
