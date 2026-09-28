# Intelligence examples

`mix run examples/inspect.exs` runs a provider-free canonical inventory and emits exact source-bound reporting data. It is not a live model demonstration.

Live and database-backed inspection examples now belong to Workshop, which owns completion, environment and PDF setup: run `mix run examples/analysis.exs --mode knowledge` there. Other modes are documented in its example guide. Do not run a completion-dependent example from Intelligence or add Inference as a dependency to make it work.

The historical Phase 1 writing preservation demonstration remains `packages/fount_workshop/examples/phase_one.exs`. The Phase 3 StoryWorld core is preserved. The new Phase 4 Temporal/Reader source, tests, and example are pending runtime QC in this delivery; prior phase status remains as recorded in the docset.
## Phase 3 story-world reference

`mix run examples/phase_three.exs` builds a small non-linear screenplay, supplies one frozen observation plus exact source-backed story records, and demonstrates event-qualified state, explicit story-time constraints, a separate causal edge, and deterministic writer-reference Markdown. It performs no provider or database call.

## Phase 4 temporal and Reader demonstration

`mix run examples/phase_four.exs` demonstrates the same screenplay in two coordinate systems: a flashback that is presented later but constrained earlier in diegetic time, and a first-reader ledger in which a private note is ignored until the visible reveal occurs. It also prints an event-qualified character view. The example has no provider or database call.
## Phase 5 diagnosis and multi-pass writer-playbook demonstration

`mix run examples/phase_five.exs` builds a small interrogation scene, derives its actual evidence IDs, creates matching `Fount.Observe.Sandbox` fixtures, runs the Scene Doctor shell through base Observe measurement, pure evidence-need reduction, closed-context measurement, and pure diagnosis, then renders the writer result packet as Markdown. It uses no database or hosted provider.

## Phase 6 capability demonstration

`mix run examples/phase_six.exs` builds one screenplay scene, creates deterministic `Fount.Observe.Sandbox` answers for the installed Scene Engine measurement contract, and runs the Phase-6 Scene Doctor integration. The packet contains source-grounded capability state and diagnoses only; it does not generate or accept screenplay pages.

## Phase 7 audience/reader demonstration

`mix run examples/phase_seven.exs` builds a two-scene non-linear watch setup, supplies source-backed strict-forward Reader events, creates deterministic `Fount.Observe.Sandbox` answers for the Audience / Reader Experience lens, and runs the `suspense_audit` writer playbook. The later-presented flashback resolves the question only when it is actually presented. Runtime execution of the new Phase-7 source remains for Codex QC in this source delivery.

## Phase 8 capability-completion demonstration

`mix run examples/phase_eight.exs` creates a tiny base screenplay and an explicit candidate revision, supplies deterministic `Fount.Observe.Sandbox` answers, and runs the preserved `revision_regression` writer packet through Phase-8 Revision Intelligence. The packet reports intended-effect/protected-strength evidence and separate source/StoryWorld/Reader comparison slots without accepting either revision or generating new pages. Runtime execution remains for Codex QC in this source delivery.

## Phase 11 evaluation demonstration

`mix run examples/phase_eleven.exs` validates the shipped synthetic rights manifest, preserves two disagreeing first-reader annotations, evaluates a sample probability distribution, compares descriptive drift, validates the frozen current-output-contract fixture and lists all twelve capability benchmark mappings. It performs no provider or database call and makes no human-validation claim.
