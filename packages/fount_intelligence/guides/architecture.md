# Pure interpretation and explicit acquisition

The package graph is `fount <- fount_observe <- fount_intelligence <- fount_workshop`, with direct canonical dependencies where needed. Only Observe depends on SystemOneSDK. Only Workshop depends on Inference and owns provider-specific completion integration. No previous analysis package or delegate remains.

`StoryWorld.Records` validates proposed records against exact selected evidence. `Reader.Reveal` computes threshold crossings/retractions from explicit measured points. `Capabilities.DecisionPolicy` and `Capabilities.Interpretation` derive policy outcomes without acquiring evidence. These pure components receive values and return values; they do not call providers, databases, environment, filesystem, clocks or randomness.

`Acquisition` creates source-backed Observe requests or invokes explicit host proposal services. `Playbooks` compose existing inspections and experiments. `Reporting` binds logical result contracts and source identity. `Persistence.SavedRecords` validates reusable stored analytical material. `Runner` applies shared resources and checks citations against current/explicit historical models. Workshop supplies completion and measured-layout functions without becoming an Intelligence dependency.

## Gate

Run `mix fount.architecture` at the workspace root after dependency setup. It builds the workspace then checks all production source and compiled imports/attributes/debug references. Source traversal resolves ordinary and grouped aliases, nested module scope, imports, structs, remote calls and captures. The gate rejects wrong package ownership, native-provider leakage, pure-core shell/IO dependencies, dynamic dispatch in pure code, forbidden effectful calls, and a leftover removed-package directory.

`mix fount.architecture --source-only` from this package skips compiled inspection and labels its report accordingly. Full QC requires compiled modules for every owned production module, deterministic replay tests, and a `mix xref` dependency review. Macro-generated/runtime-dispatched code is not proven pure by a static scan alone; this gate is enforcement plus evidence, not a mathematical purity guarantee.

The allowed Observe leaf set is explicit. `Observation`, `MeasurementResult`, `Distribution`, exact references/errors and typed neutral context primitives may be read by pure logic; the executor, provider handles, lenses, registry and cache may not. Phase 4 extends the pure core with `Temporal` views and a forward-only `Reader`. Diagnosis remains a later-phase responsibility.
## Pure StoryWorld / Temporal / Reader boundary

The StoryWorld compiler consumes only canonical Fount values, allowed Observe leaf values, and explicit replay records/evidence. It adds no call to Observe execution, SystemOneSDK, Inference, Repo, filesystem, environment, clock, randomness, process state, or persistence. Deterministic IDs derive from screenplay/revision/content identities.

StoryWorld intentionally owns three independent graphs/coordinates: source presentation points, partial story-time constraints, and typed causality. Only unambiguous strict temporal precedence propagates. Causality never manufactures time order, and source order never manufactures diegetic order. Non-base dream/recollection/hypothetical/alternate/contested scopes stay qualified instead of being silently merged into base-story state.

## Phase-4 Reader rule

`Fount.Intelligence.Reader` derives checkpoints from the canonical visible performed stream. Notes, boneyards and omitted material are excluded from that stream. Reader-visible events must cite current-revision evidence at or before their own presentation point; future evidence is rejected. Private events are ignored rather than allowed to mutate first-reader state.

`Fount.Intelligence.Temporal` stays on the other side of the semantic split: it queries event-qualified StoryWorld state and partial story-time connectivity. Reader recomputation is a presentation suffix; temporal recomputation is a dependency-driven story-time connected region. Neither implies the other.
