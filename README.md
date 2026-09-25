<p align="center">
  <img src="assets/fount.svg" alt="Fount" width="200" height="200"/>
</p>

<p align="center">
  <a href="https://hex.pm/packages/fount"><img src="https://img.shields.io/hexpm/v/fount.svg" alt="Hex.pm"/></a>
  <a href="https://hexdocs.pm/fount"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="HexDocs"/></a>
  <a href="https://github.com/nshkrdotcom/fount"><img src="https://img.shields.io/badge/GitHub-repo-black?logo=github" alt="GitHub"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"/></a>
</p>

# Fount

**A headless screenplay framework with a format-independent canonical model, relational persistence, lossless Fountain imports, and format adapters.**

The core Mix project is at [`packages/fount`](packages/fount). [`packages/fount_workshop`](packages/fount_workshop) is a separate app for writer-reviewed model revisions and screenplay PDF handoff. Fount owns pure screenplay transformations and an Ecto/PostgreSQL persistence boundary. Older filesystem/SQLite stores remain for source-backed Fountain documents.

---

## The Four Kinds of Truth

Fount strictly decouples screenplay reality into four distinct architectural layers:

```text
┌──────────────────────────────────────────────────────────────┐
│  1. SOURCE TRUTH                                             │
│  Exact imported Fountain bytes + CST + source spans          │
└──────────────────────────┬───────────────────────────────────┘
                           │ import / project
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  2. SCREENPLAY TRUTH                                         │
│  Typed canonical model, authored cast, durable identities    │
└──────────────────────────┬───────────────────────────────────┘
                           │ analyses / resolution
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  3. INTERPRETIVE TRUTH                                       │
│  Entities, beats, events, relationships, NLP, AI annotations │
└──────────────────────────┬───────────────────────────────────┘
                           │ projections
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  4. PRESENTATION / OPERATIONAL TRUTH                         │
│  Reports, format export, workshop PDF export                 │
└──────────────────────────────────────────────────────────────┘

       PURE CANONICAL EDITS + TRANSACTIONAL ACCEPTANCE
```

1. **Source truth (`CST`)**: Exact byte reproduction, including formatting delimiters, line endings, boneyards, and source spans. Untouched Fountain round-trips through `Fount.render/1` without changing bytes.
2. **Screenplay truth (`IR`)**: Typed elements, scenes, dialogue blocks, title pages, and outline views. Identity reconciliation keeps IDs where continuity can be established; it is best-effort after arbitrary external rewrites.
3. **Interpretive truth (`Annotations`)**: Derived analysis anchored to IDs and source revisions with provenance. The built-in analyzers cover characters, dialogue, and locations; richer narrative interpretation can be added by applications.
4. **Presentation and operational truth (`Projections`)**: Reports plus JSON and FDX adapters. The separate workshop app exports a spec-draft PDF and performs dated submission checks. Exact page eighths and production breakdowns remain future work.

---

## Architectural Principles

- **Lossless Fountain Round-Trip**: The Concrete Syntax Tree preserves whitespace, comments, forced syntax, and indentation.
- **Stable identity**: Reconciliation retains object IDs across many source edits and reports when it cannot safely do so.
- **Source-backed edits**: `Fount.Edit` offers text replacement, cue rename, heading changes, insertion, scene movement/deletion, and undo/redo through `ChangeSet` values.
- **Format adapters**: FDX and JSON stay outside the canonical model. FDX returns fidelity losses for unsupported metadata or styling.
- **Persistence boundary**: The canonical screenplay is authoritative for structured edits. Fount's Ecto/PostgreSQL store holds typed current rows and immutable revisions. Fountain and FDX are I/O adapters; the older source-backed stores remain compatible.

---

## Repository Structure

This repository is structured as a Poncho project:

```text
.
├── LICENSE
├── CHANGELOG.md
├── README.md
├── assets/
│   └── fount.svg
└── packages/
    ├── fount/          # Core Fount engine and Mix project
    └── fount_workshop/ # Model revision and PDF app Mix project
```

---

## Development and Tests

The root Mix project uses Blitz to run the two package projects concurrently.
It is tooling only; each package keeps its own dependencies, build output, and
lockfile. Every test run executes both complete suites, including PostgreSQL,
SQLite, and PDF export coverage. Inference and speech tests use mocks or local
callbacks, so provider credentials are not required.

Install Elixir 1.18+ with a compatible OTP, Node.js/npm, PostgreSQL, and Poppler
(`pdfinfo`, `pdffonts`, and `pdftotext`; `poppler-utils` on Debian/Ubuntu). Then,
from this directory:

```bash
mix setup
```

This fetches the Mix dependencies and runs `npm ci` for the workshop's pinned
Afterwriting renderer. PostgreSQL must already be running. The test connection
defaults are `/var/run/postgresql`, port `5433`, user `home`, and no password.
Override them with `FOUNT_TEST_PGHOST`, `FOUNT_TEST_PORT`, `FOUNT_TEST_USER`, and
`FOUNT_TEST_PASSWORD` as needed. A hostname such as `localhost` selects TCP;
a path selects a Unix socket.

Create the test databases once, using your configured connection:

```bash
createdb -h "${FOUNT_TEST_PGHOST:-/var/run/postgresql}" \
  -p "${FOUNT_TEST_PORT:-5433}" -U "${FOUNT_TEST_USER:-home}" \
  "${FOUNT_TEST_DATABASE:-fount_test}"
createdb -h "${FOUNT_TEST_PGHOST:-/var/run/postgresql}" \
  -p "${FOUNT_TEST_PORT:-5433}" -U "${FOUNT_TEST_USER:-home}" \
  "${FOUNT_WORKSHOP_TEST_DATABASE:-fount_workshop_test}"
```

For password authentication, supply the password through your usual PostgreSQL
client configuration or `PGPASSWORD`; `createdb` does not read
`FOUNT_TEST_PASSWORD`. Skip creation for databases that already exist. Tests run
their own migrations and require a role that can create tables.

The root runner uses separate databases for the two packages so migrations and
tests can run concurrently. `FOUNT_TEST_DATABASE` overrides the core database;
`FOUNT_WORKSHOP_TEST_DATABASE` overrides the workshop database. Keep these names
distinct for parallel runs.

```bash
mix test                                      # Both complete test suites
mix test --seed 0                              # Forward ExUnit options to both
mix test -j 1                                 # Serialize package runs
mix ci                                        # Setup and all quality checks
mix blitz.workspace format                    # Format both packages
mix blitz.workspace compile                   # Compile with warnings as errors
mix blitz.workspace credo --strict
mix blitz.workspace dialyzer
mix blitz.workspace docs                      # Docs with warnings as errors
```

Pass ExUnit options directly, as in `mix test --seed 0`. Blitz 0.4.1 currently
reverses arguments after a standalone `--`, so omit that separator.

`mix ci` checks root/package formatting and unused locks, then runs compilation,
tests, strict Credo, Dialyzer, and docs. It stops on failure. Blitz uses automatic
CPU/memory scaling with task weights of 4 for compilation/tests and 2 for
Dialyzer/docs, without a global concurrency cap. Both packages run in parallel
on a sufficiently capable machine. Use `-j N` on `mix test` or a
`mix blitz.workspace <task>` invocation to set an explicit limit.

For a single package or test, use its ordinary Mix command:

```bash
(cd packages/fount && mix test)
(cd packages/fount && mix test test/persistence_test.exs)
(cd packages/fount_workshop && FOUNT_TEST_DATABASE="${FOUNT_WORKSHOP_TEST_DATABASE:-fount_workshop_test}" mix test)
(cd packages/fount_workshop && mix test test/pdf_export_test.exs:6)
```

Direct package commands read `FOUNT_TEST_DATABASE`; the workshop-specific
variable is mapped by the root Blitz runner. File paths and line numbers belong
to direct package commands rather than the all-packages command.

### Local cross-repository dependencies

The root Blitz dependency and workshop's Inference dependency support the
standard Mix Workspace Ops bootstrap hook (`MIX_WORKSPACE_OPS_BOOTSTRAP` and
`workspace_dep/1`). MWO can select local checkouts such as `../blitz` when invoked
with the appropriate external registry/source configuration. Without MWO, these
remain ordinary locked Hex dependencies. MWO is not a project dependency; its
registry, source preferences, and generated state stay outside this repository.
The workshop's `../fount` dependency remains an ordinary in-repository path.

---

## License

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom

## Source continuation (2026-09-24)

The continuation adds canonical interchange, revision-aware inspection and writer-session/candidate APIs with CLI and real-only example modes. This pass is **uncompiled and untested**; it is not a release-completion claim. Read the [implementation handoff](docs/implementation_handoff/README.md) for actual source coverage, explicit missing functionality, safe application and local verification.
