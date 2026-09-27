# Intelligence examples

`mix run examples/inspect.exs` runs a provider-free canonical inventory and emits exact source-bound reporting data. It is not a live model demonstration.

Live and database-backed inspection examples now belong to Workshop, which owns completion, environment and PDF setup: run `mix run examples/analysis.exs --mode knowledge` there. Other modes are documented in its example guide. Do not run a completion-dependent example from Intelligence or add Inference as a dependency to make it work.

The historical Phase 1 writing preservation demonstration remains `packages/fount_workshop/examples/phase_one.exs`. The Phase 3 StoryWorld core is preserved. The new Phase 4 Temporal/Reader source, tests, and example are pending runtime QC in this delivery; prior phase status remains as recorded in the docset.
## Phase 3 story-world reference

`mix run examples/phase_three.exs` builds a small non-linear screenplay, supplies one frozen observation plus exact source-backed story records, and demonstrates event-qualified state, explicit story-time constraints, a separate causal edge, and deterministic writer-reference Markdown. It performs no provider or database call.

## Phase 4 temporal and Reader demonstration

`mix run examples/phase_four.exs` demonstrates the same screenplay in two coordinate systems: a flashback that is presented later but constrained earlier in diegetic time, and a first-reader ledger in which a private note is ignored until the visible reveal occurs. It also prints an event-qualified character view. The example has no provider or database call.
