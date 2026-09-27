# Durable analysis, reuse, and recomputation

Phase 10 adds an **opt-in** durable analysis shell without moving canonical screenplay ownership out of `fount`, provider execution out of Observe, or creative generation/acceptance out of Workshop.

## What is durable

A durable writer analysis run records the exact screenplay/revision, playbook identity/hash, concern/intent/scope, output-contract ID/digest, actual resource usage, the writer packet, fresh revision-bound Observations, and reverse dependency rows. Reusable `MeasurementResult` values live separately in an L2 cache. A cache row is not an Observation and never becomes canonical screenplay truth.

`Fount.Intelligence.Persistence.new/2` owns this shell. Observe receives its existing `Fount.Observe.Cache` behaviour through `Persistence.MeasurementCache`; the pure StoryWorld, Reader, capability and Diagnosis modules do not gain Repo access.

## Cross-revision reuse

Reuse is based on the semantic identity Observe already computes: privacy namespace, measurement-spec digest, exact model-visible state/context digest, provider/model fingerprint and semantic execution digest. Revision-only lineage is excluded. Therefore an unchanged scene can reuse a result across screenplay revisions only when the **effective semantic input is exactly unchanged**.

A cache hit is revalidated by Observe and materializes a new current-revision Observation with current target/evidence/dependencies. Old byte spans or prior-revision provenance are never returned as the current Observation.

Durable reuse requires `immutable_exact` or `provider_stable` model identity. A mutable model alias remains valid for weaker run-local/L1 use but is rejected by Observe under `cache_policy: :durable`.

## Privacy and retention

Every L2 lookup includes an explicit privacy namespace. Identical semantic keys in different namespaces occupy distinct rows and cannot cross-reuse accidentally.

`Persistence.evict_cache/2` is an explicit resource policy. It removes old L2 cache rows only. It does **not** delete analysis runs, writer packets, Observations, dependency history, candidate lineage, or canonical revisions. Screenplay edits likewise do not delete cache rows; changed semantics miss naturally.

## Project/studio assets

Validated custom lenses and genre packs, plus data-only calibration/playbook configuration, can be installed by content digest only when the caller passes `allow_project_assets: true`. Installation and enablement remain separate. Runtime-bearing keys such as modules, functions, commands, paths, endpoints, credentials, tools, adapters or providers are rejected for generic data assets. There is no numeric domain-version field or compatibility reader.

## Recomputation

`Fount.Intelligence.recomputation_plan/4` composes the existing pure frontiers:

- StoryWorld: the connected dependency/story-time region, never a chronological suffix;
- Reader: the earliest affected **presentation** checkpoint and the forward suffix;
- persisted writer packets/diagnoses/Observations: only records whose declared dependency keys intersect the change.

The planner does not delete MeasurementResults. Re-execution performs ordinary exact cache lookup; if model-visible context changed, the input digest changes and the L2 lookup misses.

## Workshop

Existing Workshop behavior is unchanged unless `durable_analysis: true` is supplied. When enabled against the normal `FountWorkshop.Store`, prewrite and post-candidate Intelligence runs receive the durable store. Their `analysis_run_id` is written into writer-packet provenance, and that packet remains inside the candidate/session lineage. Rejecting a candidate does not remove its analysis history; resuming a session still follows the existing explicit candidate decisions instead of reviving rejected advice.

## Verification boundary

This source phase does not itself prove PostgreSQL migration/runtime behavior. Run the Phase-10 database, cache, recomputation, session-resume and full workspace QC gates in the runtime handoff before marking Phase 10 complete.
