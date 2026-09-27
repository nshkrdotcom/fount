<p align="center"><img src="assets/fount_observe.svg" alt="Fount Observe" width="200" height="200"/></p>

# Fount Observe

**Measure what is on the page without letting an answer rewrite the screenplay.**

Observe supplies atomic, source-grounded measurements for Fount's writing and inspection tools. It separates a proposition's probability from a choice's confidence, preserves ordered rubrics and raw distributions, and keeps missing/failed measurements distinct from evidence that a proposition is false.

A reusable `MeasurementResult` contains the effective question/input/provider identity. An `Observation` binds that result to the current screenplay revision, exact evidence and acquisition run. Cache hits therefore do not carry old revision citations into a new report.

## Try a deterministic measurement

From this package, run `mix run examples/sandbox.exs`. It uses an authored fixture, not a model prediction or a validated claim about a reader. See [usage](guides/usage.md) for live providers, source evidence and cache controls.

## Package boundary

Observe depends on canonical `fount` and `system_one_sdk`. Only `Fount.Observe.Providers.SystemOne` touches native SDK types. Closed sensor, projection and lens registries reject arbitrary executable names. Intelligence interprets measurements; Workshop owns screenplay generation, PDF rendering and acceptance.

The Phase 1 source includes request/error contracts, source projections, a deterministic Sandbox, ordered batch reassembly, analytical budgets, cancellation/timeouts, and a process-owned LRU cache. It does not claim the later calibration/corpus or full measurement-substrate hardening phases are complete.

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
answers are workflow demonstrations, not live or human validation. Phase 2 runtime
verification is pending; the current handoff lists the checks Codex must run.
