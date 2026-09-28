# Changelog

## Unreleased - Phase 11 offline implementation

- Add an explicitly gated `phase_eleven_qc` live mode limited to one scene and one generated candidate, with Observe disabled and writer acceptance forced off.
- Preserve all existing generation, review, resume and acceptance behavior; Phase-11 evaluation does not rank or promote candidates.

## Unreleased - Phase 10 offline implementation

- Allow writer sessions to opt into durable Intelligence analysis with an explicit privacy namespace while preserving the existing Store + Inference-only lane.
- Persist the durable-analysis option through session resume so reopening a writing session can recover analysis lineage without promoting rejected advice or unchosen candidates.
- Canonical acceptance/rejection semantics are unchanged. Runtime verification is pending in this source-writing environment.

- Adds a PostgreSQL resume/history regression proving rejected advice stays rejected, an unchosen candidate remains available, durable analysis history survives resume, and canon remains unchanged.
## Unreleased - Phase 9 offline implementation

- Integrate Workshop sessions with existing Intelligence capability playbooks before substantial revision work when an Observe provider is configured.
- Add provider-free workflow/resource preflight while preserving the store + Inference-only writing lane.
- Carry writer packets, diagnosis/strategy lineage, note reaction/cause/treatment separation, consequence proposals and resource metadata into candidate/review surfaces.
- Run optional explicit base/candidate Revision Intelligence after candidate compilation and expose protected-strength/collateral checks as advisory review information only.
- Preserve explicit writer acceptance, recovery, selection, combination, audition and rebase behavior; no analysis result can promote canon.
- Runtime verification is pending in the source-writing environment; Codex must execute the Phase-9 handoff checks before the phase is engineering-complete.

## Unreleased - Phase 1 offline implementation

- Split atomic measurements and screenplay interpretation into Observe and Intelligence; update Workshop to the new services without changing explicit acceptance.
- Preserve existing writing/analysis behavior and add source-evidence, batch/cache/boundary tests and a writer demonstration.
- Runtime verification is pending; prior success records do not certify this change.

## 0.1.0 - 2026-09-23

Initial implementation of the Fount Workshop screenplay revision and handoff layer:

- writer-controlled agentic scene revision loop (`context -> propose -> preview -> accept`)
- structured proposal decoding with schema operations
- side-effect-free semantic and source diff previews
- atomic revision acceptance with model and provenance tracking
- PDF handoff export via Afterwriting with inspection reports
- dated submission profiles for Black List and Academy Nicholl requirements
- character-voiced dialogue table read synthesis adapter