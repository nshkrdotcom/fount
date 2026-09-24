# Feature and implementation map

Status terms: **source added** means an implementation file exists in this
delivery, not that its Elixir tests passed. **Integration remaining** means
release behavior must still be implemented or connected and verified.

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
