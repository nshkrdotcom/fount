# Feature and implementation map

This file describes the supplied source overlay. The local implementation has
advanced beyond it; the table below records the current verified additions.
**Implemented in part** does not mean the full feature acceptance case passes.

| Area | Current source and evidence | Status |
| --- | --- | --- |
| Canonical screenplay edits and revision values | `Fount.Screenplay.Editor`, `Fount.Screenplay.Model`, `Fount.Slice`, `Fount.Target`, `Fount.ChangeImpact`; 56 offline core tests pass | Implemented in part; full operation contract and interchange matrix remain |
| PostgreSQL writing model | Fresh migration and `Fount.Persistence`; four real DB integration tests pass | Implemented in part; legacy stores still need removal and more acceptance cases remain |
| Develop and continuation | `FountWorkshop.Develop` uses Hex Inference and writes real candidates; two real Codex drafts and PDFs verified | Implemented in part; full W01 editing/acceptance case remains |
| Candidate review | `FountWorkshop.Review` and atomic acceptance; repeated acceptance now rejects | Implemented in part; full selection/rebase and report validation remain |
| Perspective evaluation | `FountProbe.State` and `FountProbe.Knowledge`; real Jev example and offline tests pass | Implemented in part; complete character access ledger and T01–T13 remain |
| Scene inventory | `FountProbe.Inventory` reports visible scene IDs, cue cast and dialogue/action word counts with exact inspected scope | Deterministic portion of T01 only; model extraction remains |
| Exact passage retrieval | `FountProbe.Search` returns revision-labeled literal phrase hits, inspected counts and exact element IDs; private note and omitted content are excluded by default | Deterministic portion of T02 only; semantic relevance and historical scope remain |
| Exact-target rewrite | `FountWorkshop.TargetedRewrite` uses Inference to replace selected action/dialogue elements by ID, saves/reopens a candidate and leaves accepted head unchanged; offline, DB and live Codex checks pass | A useful part of W07; complete six-pass workflow remains |
| Sequence rebuilding | `FountWorkshop.SequenceRebuild` replaces selected consecutive scenes with generated scenes, validates required exact passages and target count, retains matching existing scene/element IDs, and saves a candidate; offline, PostgreSQL and live five-to-three checks pass | Part of W04; multi-route comparison and genuine page reduction remain |
| Live examples | Exactly one entrypoint exists in each package | Partial mode coverage; see `VERIFICATION.md` |

## Concrete additions

| Responsibility | Source | Offline test source |
|---|---|---|
| UTF-8 byte spans, exact excerpt checks, unique pin relocation | `packages/fount/lib/fount/writing/utf8_span.ex` | `packages/fount/test/writing_contracts_test.exs` |
| Sorted-key canonical JSON and SHA-256 | `packages/fount/lib/fount/writing/canonical_json.ex` | same |
| Candidate-local declarations, single UUID allocation, unknown-reference errors | `packages/fount/lib/fount/writing/local_references.ex` | same |
| Stable group ordering, missing-dependency selection, cycle rejection | `packages/fount_workshop/lib/fount_workshop/writing/change_groups.ex` | `packages/fount_workshop/test/writing_decisions_test.exs` |
| Review content/base/report matching, hard failures versus explicit semantic acknowledgment | `packages/fount_workshop/lib/fount_workshop/writing/review_gate.ex` | same |
| Noul/Choice/Score interpretation, negative intent, nonmonotonic crossings | `packages/fount_probe/lib/fount_probe/writing/decision_policy.ex` | `packages/fount_probe/test/writing_policies_test.exs` |
| Exact revision-aware evidence/citation registry | `packages/fount_probe/lib/fount_probe/writing/evidence.ex` | same |
| Public SDK batching and response/error batch-index joining | `packages/fount_probe/lib/fount_probe/writing/executor.ex` | same (deterministic joining only) |
| Inference structured/text completion with mandatory local validator and decode repair | `packages/fount_workshop/lib/fount_workshop/writing/completion.ex` | additional Inference Mock coverage remains |
| Six creative direction assets | `packages/fount_workshop/priv/writing_profiles/` | workflow integration remains |

The canonical JSON helper is an encoder, **not** a complete domain content-hash
projection. The caller must supply the correct authored-content projection.
The review gate is a pure check, **not** the atomic PostgreSQL acceptance
transaction. The evidence resolver is caller-owned; this is not a new store.
The SDK executor returns in-memory typed results; conversion into the complete
persistent JSON report envelope remains.

## Foundations

| ID | Release status and remaining work |
|---|---|
| F01 | Existing Fountain/interchange retained. Verify fidelity and complete spec projection, title handling and runtime PDF path behavior. |
| F02 | New span/reference helpers supplied. Full typed operation compiler, stable-ID sequence editing, index, target migration and all callers remain to complete/verify. |
| F03 | Complete immutable revision-scoped PostgreSQL replacement and candidate/session transactions remain. Existing baseline persistence must not be represented as the new schema. |
| F04 | Full authored brief/intent/note/constraint values and adoption/resolution integration remain. |
| F05 | Revision-aware evidence helper supplied; complete structural/semantic/historical retrieval and collections remain. |
| F06 | Typed decision and batch helpers supplied; the complete T01–T13 implementations remain. |
| F07 | Group selection/review gates supplied; full candidates, diffs, provenance, stale acceptance/rebase transactions remain. |
| F08 | Retained baseline output is not newly verified. Runtime PDF configuration and real optional speech integration remain. |
| F09 | New offline tests supplied, not run. Audit retained tests for service use, complete offline suites, and implement exactly three real example entrypoints. |

## Creative workflows

All nine workflows remain integration/implementation work; profile files or
support helpers do not count as complete writing workflows.

| ID | Public workflow | Required acceptance case still to establish |
|---|---|---|
| W01 | develop | Empty-root generation, two actual candidate scenes, bridge preserving neighbors, reopen/edit/accept. |
| W02 | alternatives | Actual variants, source/range overlap choices, pinned combination with a generated join. |
| W03 | propagate | Relocate fixture reveal from scene 3 to 6, repair the accusation and ferry motivation, retain the key setup. |
| W04 | sequence | Two genuine five-to-three scene routes; preserved IDs/pins/setup; real identical-settings PDF comparison. |
| W05 | character | Dan changes across at least three scenes, including partner-responsive choices rather than vocabulary substitutions. |
| W06 | notes | Exact note provenance and grouped responses; accepting the local solution leaves the structural and unrelated notes open. |
| W07 | pass | Dialogue, visual/action and dry-comedy mechanisms produce actual typed writing; six profiles callable. |
| W08 | recover | Real historical retrieval, exact source/current/proposed comparison and correctly mapped restored/adapted identity. |
| W09 | investigate | Known tool requests, exact evidence, competing hypotheses, three strategies, and two written remedies. |

## Probe tools

T01 inventory/extraction; T02 search; T03 constraints; T04 knowledge trace;
T05 boundary localization; T06 dependencies; T07 continuity; T08 scene mechanics;
T09 dialogue; T10 voice; T11 action; T12 compare/lift/ablate; T13 strategy contrast.

The supplied support components serve these tools but **are not their complete
implementations**. Follow `spec_draft_implementation/07_probe_features.md`,
including parameter validators, perspective isolation, uncertainty, report
provenance and SDK Test-client coverage. Do not publish a catalog entry without
its executable implementation.
