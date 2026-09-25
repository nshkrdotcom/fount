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
| Local note response | `FountWorkshop.NoteResponse` converts one writer note into an exact target rewrite, removes only that note in the candidate, and preserves other notes and the accepted draft; offline, PostgreSQL and live checks pass | Part of W06; sequence notes and selective group acceptance remain |
| Six writing profiles | `FountWorkshop.Pass` loads all six profile assets and dispatches dialogue/action passes to exact element rewrites and scene-level passes to sequence rebuilding; offline and PostgreSQL checks pass, with a live dialogue pass | Part of W07; complete checks, selective group review and all live profile modes remain |
| Table read output | `FountWorkshop.TableRead.export/3` writes ordered dialogue turns as actual JSON or escaped HTML; offline file I/O and live output checks pass | Optional `Espeak` WAV path exists but was not run because the executable is unavailable |
| Character progression rewrite | `FountWorkshop.CharacterRewrite` selects confirmed character dialogue and immediate partner replies across chosen scenes, generates exact element edits and saves a candidate; offline and live three-scene checks pass | Part of W05; wider character workspace and semantic outcome checks remain |
| Historical beat recovery | `FountWorkshop.Recover` compares source/current/proposed text, restores cut elements at their historical position with their original IDs and saves a candidate; offline, PostgreSQL and live checks pass | Part of W08; deleted-scene recovery, adaptation and branch merging remain |
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

`Fount.Screenplay.Model` now supplies an authored-content projection for the
canonical JSON encoder. `ReviewGate` remains a pure check; the separate
PostgreSQL acceptance transaction is implemented in `Fount.Persistence`.
The evidence resolver is caller-owned. SDK report serialization remains.

## Foundations

| ID | Release status and remaining work |
|---|---|
| F01 | Original Fountain parser retained; real import/export and PDF paths were exercised. Full interchange matrix, title and spec projection remain. |
| F02 | Typed edits, local references, stable scene/element IDs and slices implemented in part; complete operation contract and all callers remain. |
| F03 | Fresh revision-scoped PostgreSQL migration and accepted/candidate/session transactions run in a new database. Legacy filesystem/SQLite stores, dependency and callers were removed. Full schema and concurrency cases remain. |
| F04 | Authored item operations and note candidate responses exist; complete intent/constraint adoption and resolution remain. |
| F05 | Exact slices, literal search and historical element recovery exist; full semantic/historical retrieval and collections remain. |
| F06 | Typed decision and batch helpers plus partial inventory/knowledge paths exist; most T01–T13 work remains. |
| F07 | Candidate persistence, review packets and atomic explicit acceptance exist; selective combination and three-way rebase remain. |
| F08 | Real PDF layout and table-read JSON/HTML were checked. Optional eSpeak WAV path exists but was not run. |
| F09 | Default offline suites pass in all three packages; exactly three real example entrypoints exist, but their complete mode coverage remains. |

## Creative workflows

Several workflows now produce saved screenplay candidates. The acceptance
cases below remain the release target; a partial workflow does not satisfy
its whole case.

| ID | Public workflow | Required acceptance case still to establish |
|---|---|---|
| W01 | develop | Empty-root generation, two distinct candidate drafts, reopen, real PDF and explicit acceptance were verified. Full bridge and subsequent candidate edit path remain. |
| W02 | alternatives | Actual variants, source/range overlap choices, pinned combination with a generated join. |
| W03 | propagate | Relocate fixture reveal from scene 3 to 6, repair the accusation and ferry motivation, retain the key setup. |
| W04 | sequence | One real five-to-three route, exact key passage preservation and same-settings PDF comparison passed; it saved zero pages. A second contrasting route and stronger pin/dependency checks remain. |
| W05 | character | Live Dan/Mara dialogue progression across three scenes passed; broader character workspace and checks remain. |
| W06 | notes | A real local note response removed only its addressed note in a candidate. Sequence notes, grouped acceptance and accepted note resolution remain. |
| W07 | pass | Six profiles are callable and dispatch to typed edits; live dialogue pass passed. Other live profiles and stronger craft checks remain. |
| W08 | recover | Exact historical beat restore with original ID and source/current/proposed text passed offline, DB and live. Adaptation, deleted-scene recovery and merge remain. |
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
