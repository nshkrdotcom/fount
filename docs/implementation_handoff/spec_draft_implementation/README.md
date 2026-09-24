# Fount: professional spec draft implementation

Status: implementation specification, 2026-09-24. This directory is the complete handoff; earlier brainstorming files are not required by its recipient.

Build a creative screenplay writing and revision environment backed by PostgreSQL across `packages/fount`, `packages/fount_probe`, and `packages/fount_workshop`. The deliverable from the implementation agent is a **Fount zip overlay containing every new and modified file**, plus an explicit deletion manifest and a follow-on handoff docset. This directory specifies that work; it does not claim the implementation exists.

Give the implementation agent this entire directory, [IMPLEMENTATION_PROMPT.md](IMPLEMENTATION_PROMPT.md), and three Repomix files named **`fount.xml`, `system_one_sdk.xml`, and `inference.xml`**. The prompt also specifies the eventual local workspace: **`~/p/g/n/fount`, `~/p/g/n/system_one_sdk`, and `~/p/g/n/inference`**.

## Reading order

| Document | Decision or contract |
| --- | --- |
| [01 — Features and research](01_features_and_research.md) | Writer needs, research, required release scope, acceptance criteria |
| [01a — Creative workflows](01a_creative_workflows.md) | Development, alternatives, story changes, sequence rebuilding, character passes, notes and recovery |
| [02 — Repository audit](02_repository_audit.md) | What actually exists and what must change |
| [03 — Architecture](03_architecture.md) | Package ownership and limited implementation choices |
| [04 — PostgreSQL model](04_postgresql_model.md) | Tables, revisions, transactions, candidates, evidence |
| [05 — Core APIs](05_core_apis.md) | Import/export, edits, cast, typed references, slices, history |
| [06 — Perspective and evidence](06_perspective_and_evidence.md) | Audience, character, blind voice and incomplete evidence rules |
| [07 — Probe features](07_probe_features.md) | Exact algorithms, questions, reducers, outputs and uncertainty |
| [08 — SDK integration](08_sdk_integration.md) | Verified System One and Inference interfaces and dependency paths |
| [09 — Workshop](09_workshop.md) | Writer commands, proposals, acceptance, PDF, rehearsal |
| [10 — Live examples](10_live_examples.md) | Three executable examples using real I/O and services |
| [11 — Tests](11_tests.md) | Default offline tests, feature matrix, explicit integration checks |
| [12 — Build sequence](12_build_sequence.md) | Vertical implementation order, file map, completion gates |
| [13 — Wishlist and upstream](13_wishlist_and_upstream.md) | Deferred features and concrete dependency gaps |
| [14 — Delivery and handoff](14_delivery_and_handoff.md) | Zip format, deleted files, verification and follow-on prompt |
| [Validation record](VALIDATION.md) | Source audit and checks performed on this docset |
| [Contracts](contracts/README.md) | Reference SQL, JSON schemas, profiles and planner examples |
| [Demonstration screenplay](fixtures/last_light.fountain) | Original small screenplay for real feature demonstrations |

## Binding choices

1. Features determine the model and APIs. Ship the required features in 01, including usable CLI commands and all three live examples. A framework skeleton is incomplete.
2. Fount is greenfield. Replace deficient interfaces and persistence, remove redundant stores, and update callers and documentation together. Preserve valuable screenplay functionality; compatibility with the current internal API is not a release requirement.
3. PostgreSQL is the only application store. Pure parsing and editing remain usable without a database or a model client.
4. Default tests in **all three Fount Mix packages** use no live API, PostgreSQL, external renderer, speech process, or authenticated CLI. Pure code and temporary local files are real; external boundaries use doubles. Explicit integration checks and `examples/` are live only.
5. The minimum example count is **three entrypoints**, one per package. Core demonstrates real files/database; Probe demonstrates Jev and Inference; Workshop demonstrates creative writing workflows, review, PDF/database output and an optional real speech mode. No mock, replay or canned-response mode exists under `examples/`.
6. All generated edits require a writer acceptance action. Analyses and draft candidates can be saved without changing the accepted screenplay head.
7. All nine creative workflows in 01a ship, supported by the screenplay tools in 07. Strategies, actual candidate pages, cross-scene repairs, auditioning and selective combination are required deliverables.
8. No generic workflow runtime, vector database, distributed queue, graph database, indefinite unattended rewrite loop, or universal screenplay quality score. The code serves one screenplay and ordinary revision work well.

## Precedence

The user's current request controls scope. The creative-workflow correction supplied by the user is incorporated in 01 and 01a. This docset supersedes the nine source notes, including their earlier permission to skip examples and their infrastructure-first phasing. Within this directory, the feature requirements and explicit domain rules control; schemas formalize their wire shapes, and the SQL formalizes the database. A recipient who finds an actual source/API mismatch records it and implements the smallest feature-preserving correction. Do not silently omit a feature or imitate a missing dependency capability.

Reference repository commits are recorded in 02. The supplied XML contents are authoritative for the receiving agent's starting code. Do not assume their hashes equal the locally reviewed commits.
