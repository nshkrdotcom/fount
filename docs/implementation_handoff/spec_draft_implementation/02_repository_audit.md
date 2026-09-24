# Source review and baseline corrections

## Inputs read

All nine documents in the source directory were read: `0001_ideas.md`, `0002_ideas.md`, `0003_prompt.md`, `0004_prompt.md`, `0010_claude.md`, `0020_gemini.md`, `0021.md`, `0030_gpt.md`, `0031.md`.

| Source | Incorporated decision / correction |
| --- | --- |
| 0001 | Focused Jev judgments, knowledge logic, writer intent and semantic revision comparison. |
| 0002 | Precise boundaries, audience/character contrast, voice matrix; reject automatic claims that post-turn text is redundant. |
| 0003 | Third package; permission to redesign core and Workshop. Its instruction to skip examples is superseded. |
| 0004 | Queries/slices, typed evidence, history, derived/authored separation, preview integration. Its proposed generic selector/question/reducer planner is replaced by named operators. |
| 0010 | Separate shared execution, feature algorithms and configurable wording. Do not implement the proposed generic lens catalogue. |
| 0020 | Useful candidate craft analyses, but probabilities are not objective voice measures; no runtime atom creation from character IDs. |
| 0021 | Perspective isolation and useful supporting operators; creative workflows now determine their use. Character mention/cue alone does not prove observation. |
| 0030 | Operator-constrained planner, profiles, scene function map. Build the operators required by the creative workflows; defer infrastructure without a present feature use. |
| 0031 | Product-driven design and explicit future capabilities. This docset supplies the implementation decisions that brief requested. |

## Locally inspected repositories

| Repository | Commit reviewed | Actual Mix roots |
| --- | --- | --- |
| `~/p/g/n/fount` | `c8ed5ab86fd01c70add68f284d7c809f6333e5c9` | `packages/fount`, `packages/fount_workshop` |
| `~/p/g/n/system_one_sdk` | `e757598a89e549274b979f0e77c6a4b2b6667752` | Use `packages/system_one_sdk`; its current source also has a sibling contracts dependency. |
| `~/p/g/n/inference` | `a1f91ee33d082fc726b0dfdc3ccf619fca9121b9` | `apps/inference`; repository root is not the package consumed by Fount. |

Read relevant source, package manifests, guides, tests and examples. These paths below are relative to their repository and can be found by their file entries inside the three XMLs. They are evidence, not absolute line-number dependencies.

## Keep, correct, replace

| Current code | Finding | Required action |
| --- | --- | --- |
| `packages/fount/lib/fount/fountain/*`, `ir/*` | Lossless parser/CST and format-independent IR already exist, including notes, boneyards and dual dialogue. | Retain and fix concrete format defects exposed by feature tests. Do not replace with an LLM parser. |
| `screenplay.ex` | Canonical editing supports fewer operations than source-backed `edit.ex`. `from_document/1` does not populate cast automatically. | Complete canonical typed edits; expose explicit cue-to-cast resolution and use it in imports/examples. |
| `query.ex`, `index.ex` | Query API mostly matches `Document`; `Screenplay.node/scene` repeatedly scan lists. | Give both models a common derived index and query surface. |
| `annotation/target.ex` | Target has `node_id` without kind. | Replace with typed `kind/id/span`; update every codec and caller. |
| `screenplay.ex` annotations | Authored/derived distinction relies on producer string; affected-ID logic lacks the full parent closure. | Separate authored values from derived reports; preserve unresolved writer intent and exact revision association. |
| `persistence.ex`, `persistence/codec.ex` | Mutable head projection plus JSON historical snapshots; rows loaded at head omit some representation fields. `at_revision/2` does not take screenplay scope. | Replace persistence with revision-scoped rows and one loader (04). Preserve full element/dual/outline data and explicit artifact references. |
| `persistence.ex` | **Already** supplies `history/2`, `at_revision/2`, locking and `insert_acceptance` inside `persist`. Workshop already has a `Fount.Repo` accept clause. | Strengthen existing behavior rather than implement the obsolete “filesystem acceptance only” diagnosis from 0004. |
| `store/filesystem.ex`, `store/sqlite.ex` | Legacy application stores add another persistence model. | Remove legacy stores, import-legacy path and `exqlite`; keep file import/export and pure Document editing. Remove associated stale docs/tests. |
| `test/persistence_test.exs` | Default suite starts a real PG repo on a hardcoded local port. | Move service checks to explicitly invoked `integration/`; default tests exercise pure validation and a focused persistence boundary double. |
| Workshop `proposal.ex` | Generated proposals accept only text replacement and headings, with `value` always a string. | Add discriminated typed operation contracts and scope validation (09). |
| Workshop `preview` canonical branch | Builds diffs but leaves diagnostics empty. | Run the same structural validation used by canonical saves; attach optional Probe regression. |
| Workshop `export/pdf.ex`, `package.json` | Uses real Afterwriting 1.17.3 and Poppler. Renderer path is derived from compile-time source location; default tests spawn real tools. | Keep renderer, resolve installed package data at runtime or explicit path; isolate process runner in tests; real PDF in live example/integration. |
| Workshop `table_read.ex` | Callback-based speech routing already exists, but no bundled speech implementation. | Preserve function injection; ship an explicit local `espeak-ng` speech implementation and real example clips. |
| Workshop `submission.ex` | Hardcoded competition policies mix formatting with eligibility assertions. | Ship a general spec preset and dated user profiles; query accepted provenance from PostgreSQL. |
| System One `prepared.ex`, guides | Has public fingerprint, strict typed questions, batching, errors and test transport. | Use those APIs directly; do not build transport, retry or supervisor machinery in Fount. |
| Inference `adapters/asm.ex` | Provider runtime is optional; Codex supported through installed ASM, Antigravity currently refused. | Codex is the required live completion provider. Record Antigravity as an upstream dependency issue, without bypassing the adapter. |

The System One root `AGENTS.md` says there is no standalone contracts package, while its current `packages/system_one_sdk/mix.exs` explicitly depends on `../system_one_contracts`. For consuming the checkout, the manifest is the operative dependency graph. Do not edit the dependency repo to reconcile its prose in a Fount overlay. Include the required sibling package when reconstructing XML. Record any actual dependency resolution problem in the handoff.

## Corrections to speculative claims

Revision IDs are UUIDs, not content hashes. Add a separate canonical content hash. A prepared set already has a public fingerprint. Noul answers have no provider confidence field. Batch concurrency is SDK-owned and does not require a caller-created Task Supervisor. A proposed conditional fact is not a writer assertion until adopted. Notes, boneyards, future scenes, character biographies and reveal labels must not leak into perspective state. A question's wording still reveals the proposition being tested; claim limited context isolation, not proof of bias-free inference.

## Product correction incorporated

The user clarified that diagnostic instruments and ordinary screenplay handling are necessary supporting capabilities. The release must also develop material, create and combine creative alternatives, perform character and sequence rewrites, propagate story changes, turn notes into edits and recover writing from history. Documents 01 and 01a supersede the initial five-operator release framing. Causal support, scene omission experiments and historical search now ship because those writing workflows require them. Codex is the sole required generative provider; Antigravity is recorded only in 13.
