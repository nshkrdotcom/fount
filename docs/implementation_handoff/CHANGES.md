# Changes and representation status

The supplied full-file overlay was a partial source starting point. This local
checkout has since acquired additional source and tests. The old overlay
manifest describes only its original payload; it does **not** describe the
current working tree or later commits.

## Implemented in the local checkout

- Core now has a typed screenplay editor, exact target and slice APIs, content
  projection, change impact, and a fresh PostgreSQL writing migration.
- `Fount.Persistence` creates/loads accepted and historical revisions, saves
  sessions/candidates/reports, and makes candidate acceptance transactional.
  The fresh schema was migrated into a new isolated development database.
- Probe now has scene inventory, literal search, exact view construction and
  a Jev evaluation path for audience and confirmed-speaker scene views.
- Workshop now generates candidate pages from an empty brief, rewrites exact
  elements, rebuilds sequences, responds to a local note, runs six writing
  profiles, rewrites character dialogue with partner replies, and restores
  historical beats. All generated pages remain candidates until review.
- The three Fount packages have resolved Mix lockfiles. Inference and Agent
  Session Manager resolve from Hex; System One SDK is consumed from its local
  checkout. Neither external repository was modified.
- Default tests run without a database or authenticated provider. Separate
  real examples and PostgreSQL/PDF integration checks are recorded in
  `VERIFICATION.md`.

The original Fountain parser and source fidelity code remain in use. The new
writer features build on those values rather than replacing the parser.

## Remaining integration

The legacy filesystem/SQLite store modules and their compatibility callers
remain. They must be removed or migrated before claiming the PostgreSQL model
is the only application store. Most T01–T13 tools and full W01–W09 acceptance
cases also remain. Complete CLI coverage, selective candidate combination,
semantic checking, story-change propagation, investigation that writes,
optional speech verification, and a rebuilt final overlay are outstanding.

Use the actual checked-out source and `FEATURES.md` as the progress record.
Do not treat the original overlay's source inventory or verification status as
the current implementation result.
