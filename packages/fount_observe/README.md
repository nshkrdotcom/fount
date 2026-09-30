<p align="center"><img src="assets/fount_observe.svg" alt="Fount Observe" width="200" height="200"/></p>

# Fount Observe

> **Current workspace status:** Observe remains the neutral measurement/System One boundary in the five-library workspace. The six-phase Run program is complete; System One reintegration Phases 01 and 02 are runtime-certified, while Phase 03 host integration is offline-implemented and awaits runtime QC. The Phoenix host lives only at `apps/fount_web`; Observe has no Phoenix dependency and remains the sole owner of native System One SDK construction.

**Measure what is on the page without letting an answer rewrite the screenplay.**

Observe supplies atomic, source-grounded measurements for Fount's writing and inspection tools. It separates a proposition's probability from a choice's confidence, preserves ordered rubrics and raw distributions, and keeps missing/failed measurements distinct from evidence that a proposition is false.

A reusable `MeasurementResult` contains the effective question/input/provider identity. An `Observation` binds that result to the current screenplay revision, exact evidence and acquisition run. Cache hits therefore do not carry old revision citations into a new report.

## Try a deterministic measurement

From this package, run `mix run examples/sandbox.exs`. It uses an authored fixture, not a model prediction or a validated claim about a reader. See [usage](guides/usage.md) for live providers, source evidence and cache controls.

## Package boundary

Observe depends on canonical `fount` and `system_one_sdk`. Only `Fount.Observe.Providers.SystemOne` touches native SDK types. Closed sensor, projection and lens registries reject arbitrary executable names. Intelligence interprets measurements; Workshop owns screenplay generation, PDF rendering and acceptance.

The first-party FountWeb composition uses `Fount.Observe.provider/1` for configured System One runtime and `Fount.Observe.Sandbox` for deterministic test/demo work. Host code does not construct `SystemOneSDK.Client` directly. Credentials remain inside the opaque provider handle, whose public Inspect representation omits state; callers must not serialize or log provider internals.

The Phase 1 source includes request/error contracts, source projections, a deterministic Sandbox, ordered batch reassembly, analytical budgets, cancellation/timeouts, and a process-owned LRU cache. The measurement substrate is the verified Phase-10 baseline. Phase-11 calibration/corpus interpretation remains owned by Intelligence; Observe only adds a gated live measurement check.

## Build against the supplied SDK

The inspected SDK API is 0.6.0. Availability on Hex was not verified. To test the supplied checkout, set `FOUNT_SYSTEM_ONE_SDK_PATH` to its `packages/system_one_sdk` directory before `mix deps.get`. Runtime QC must reconcile actual dependency resolution and regenerate lockfiles; no resolved lock is fabricated by this overlay.

## Verification status

New Elixir code and tests are **written, not executed** in this delivery. See [verification](guides/verification.md) and the Phase 1 handoff. Python archive/source checks are not Elixir compilation or provider validation.

## License

[MIT](LICENSE) - Copyright (c) 2026 nshkrdotcom.

## Phase 2: an inspectable scene question

Ask a concrete scene question with `Fount.Observe.SceneQuestion.ask/5`, inspect the
exact passages supplied for each answer, and receive an honest unavailable result
when acquisition fails. This path never changes the draft.

The measurement substrate also provides typed context roundtrips, canonical output
contracts, separate raw/calibrated views, a private LRU/TTL ETS cache, resource
preflight, partial-result retention, data-only fixture files, and human/deterministic
recordings. See [Measurement substrate](guides/measurement-substrate.md).

Run `mix run examples/phase_two.exs` after dependency setup. Its fixed fixture
answers are workflow demonstrations, not human validation. Phase 2 runtime
results are recorded in the docset's `PHASE_02_RUNTIME_QC_REPORT.md`.

## Phase-5 diagnosis measurements

The installed `diagnosis.concern_relevance` and `diagnosis.evidence_support` lenses are declarative measurement assets used by the Intelligence shell. The latter declares a closed context contract for the writer concern plus optional neutral facts, beliefs, relationship state and prior base-assessment literals. Observe remains unaware of Intelligence structs or diagnosis semantics beyond those explicit neutral inputs.

## Phase 8: safe project/studio lens declarations

`Fount.Observe.validate_declarative_lens/1`, `preview_declarative_lens/1`, and the explicit install/enable catalog helpers allow project/studio teams to define one generic proposition/choice/score measurement without loading executable code. Declarations are limited to registered projections, closed typed context, standard thresholds/resources and the existing System One measurement path; module/function names, shell/file access, endpoints, credentials, database/HTTP callbacks, tools and custom decoders/adapters are rejected. See [Constrained declarative lenses](guides/declarative-lenses.md). Durable asset persistence remains a later phase.

## Phase 11 live QC

`FOUNT_PHASE11_OBSERVE_LIVE=1 mix run examples/phase_eleven_live.exs` sends only the synthetic hallway scene through the existing provider boundary three times, records provider-neutral findings/resource usage, and prints no credentials. It is an opt-in live contract/drift check, not human calibration or screenplay-quality evidence.
