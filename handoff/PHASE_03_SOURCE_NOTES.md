# Phase 3 source notes — Story-World Pure Core

Date: 2026-09-26 (Pacific/Honolulu)

This note travels with the Fount overlay. It records what the source-writing pass actually inspected and changed; it is not a runtime-QC report.

## Content-identified inputs

The four supplied XMLs were identified by repository contents rather than attachment names:

- Fount: four-package workspace containing `packages/fount`, `fount_observe`, `fount_intelligence`, and `fount_workshop`; SHA-256 `89c7e363389ccf6414c94664a6224e6134b0be90064971f0461e659372faf430`.
- System One SDK: monorepo containing `packages/system_one_sdk` with public version `0.6.0`; SHA-256 `acf283c1d254293cf1fe634f037c0f861bab298f3d524b4db9c5d37bd639fd2d`.
- Inference: repository containing `apps/inference` with package version `0.5.0`; SHA-256 `a7e30d9b4dccc106923367725d4d9dd4ad01a57105b4684e1becd03e6cc84ee9`.
- Current implementation docset: numbered architecture/product documents `00`–`36`, `PROGRESS.md`, and Phase-1/2 handoffs; SHA-256 `8c1586b780c818012b6a965630b0f44028ea60f9d88b231202947473290c446c`.

The raw attachments contain no current `snapshot_index`; source commit identity must therefore be verified by Codex in the user's applied checkout rather than invented here.

## Phase selection

`PROGRESS.md` records Phase 1 and Phase 2 COMPLETE and Phase 3 NOT_STARTED. The current phase is therefore **Phase 3 — Story-World Pure Core**. This overlay does not begin Phase 4.

## Real APIs inspected

Fount source inspected before implementation includes `%Fount.Screenplay{}`, `Fount.Screenplay.Model.plain/1`, `Fount.Query`, `Fount.Target`, `Fount.SourceEvidence`, `Fount.ID.v5/2`, `Fount.ID.hash/1`, and `Fount.Writing.CanonicalJSON`. Observe leaf contracts inspected include `%Fount.Observe.Observation{}`, `%MeasurementResult{}`, `%Distribution{}`, `%EvidenceRef{}`, and `%TargetRef{}`. The existing Intelligence architecture gate was read and the new pure namespace stays within its Observe-leaf allowlist.

SystemOneSDK `0.6.0` public source was inspected, including `SystemOneSDK.version/0`, `new_client/1`, `noul/2`, `choice/3`, `score/3`, `prepare/1`, and evaluation/runtime contracts. Inference `0.5.0` public source was inspected, including `Inference.client/1`, `client!/1`, `complete/3`, `stream/3`, `capabilities/1`, and response-format contracts. **Phase 3 adds no SystemOneSDK or Inference call.** System One remains behind Observe acquisition; Inference remains outside the pure Intelligence core.

## Implemented Phase-3 behavior

The overlay adds a provider/repository-free `Fount.Intelligence.StoryWorld` model with:

- canonical entities/mentions and scene-event scaffolding;
- evidence-backed events, interactions, assertions/facts, goals, commitments, beats and motifs;
- base/recollection/dream/hypothetical/alternate/contested reality scopes;
- event-qualified state transitions suitable for possession/access/resources, injury/death, knowledge/plan and relationship state;
- partial story-time nodes/constraints with known, ambiguous, contradiction and unknown results without a scene-order fallback;
- typed causal relations independent from presentation and story time;
- local practical consistency checks and evidence-bearing temporal conflicts;
- epistemic-owner assertions and event-qualified knowledge queries;
- reverse dependency indexing and counterfactual support-impact primitives;
- deterministic writer-reference packets and Markdown/JSON renderers that keep evidence/derived state/uncertainty separate and emit no diagnosis or strategy in this phase;
- compatibility ingestion for the Phase-2 extraction record kinds already present in `StoryWorld.Records`.

The writer-useful focus is non-linear continuity and source-grounded reference: what is established at a given story event, what remains unknown/ambiguous, what evidence supports it, and which support/causal records depend on a proposed change.

## Explicit stop line

Forward Reader reduction, audience-state claims, diagnosis, multi-pass playbook reasoning, capability-family expansion, persistence/L2 reuse, and Workshop integration remain later phases. They are not implemented here.

## Execution status

Elixir, Erlang and Mix are absent from this source-writing environment. No formatter, compiler, ExUnit, Credo, Dialyzer, ExDoc, Hex, DB, provider, or human domain-review result is claimed. Python-only lexical/diff/archive checks are recorded in the updated docset. Codex must run and repair the new source from the user's applied commit, then complete the required Phase-3 Level-A structural/factual human review or record an explicit user-authorized validation-debt override before marking Phase 3 COMPLETE.
