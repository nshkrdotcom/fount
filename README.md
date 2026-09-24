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

## License

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom
