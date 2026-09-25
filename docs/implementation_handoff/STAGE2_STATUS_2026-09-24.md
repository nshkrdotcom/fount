# Stage 2 implementation and verification — 2026-09-24

This is a local continuation after the committed overlay and the separate QA commit `2d330e9`. The original delivery report and source-only handoff remain historical records. This stage implements and tests a substantial subset of `KNOWN_GAPS.md`; it does **not** certify the full F01–F09, W01–W09, or T01–T13 acceptance matrix.

## Implemented and exercised

- Candidate scope checks now validate operations against selected scenes, elements and byte spans before replay, then compare protected elements and scene ownership/order in the result. Character workspaces intersect confirmed appearance scenes with the writer selection. Narrow selections cannot overwrite existing cast or authored records. Tests cover wrong-scene insertion, outside movement, protected spans, repeated span replay, and character restrictions.
- PostgreSQL report saves validate primary/source revisions, evidence membership and exact excerpts. Candidate acceptance checks same-screenplay, base/result/source report lineage and repeated-decision identity. Core integration covers valid and forged reports and idempotency conflicts.
- Canonical JSON import now rejects unknown fields in the encoded revision, screenplay elements/scenes/turns, cast/mentions, annotations, source spans, title entries and source artifact envelope; authored item payloads and element attributes remain extensible.
- Probe implements adjacent-scene extraction, same-scene dependency ordering and prior-material ablation, validated saved extraction-record reuse, intended-reveal/behavior localization, changed-target continuity, profile threshold dispatch, typed constraint targets and sequence scene counts. Prohibited-fact policy evaluates listed facts against before/after material where semantic clients are available; deterministic mode stays unknown rather than certifying absence.
- Audience projection now limits default material to anonymous cues and spoken lines; exact action fragments enter only when explicitly supplied as observable evidence IDs. It remains an incomplete estimate of the viewing experience and does not certify visual or off-screen access.
- Action can measure printed PDF line regions from a verified layout report. Workshop PDF export honors A4 and title-page selection in the settings hash. A real A4 sample was rendered and visually inspected.
- Exact recovery supports a same-screenplay fragment or contiguous range and cross-screenplay copy with new IDs and explicit cast mapping. Sessions can selectively retry cached failed inspections; repeated partial group selection retains the full note dependency set. Notes with overlapping scene/element targets are flagged as potential conflicts.
- Investigation uses structured hypothesis records and one bounded follow-up batch. Its explanation must revise every initial hypothesis. Rebase rejects malformed resolution shapes before replay.

## Actual checks

`bash scripts/verify_handoff.sh --offline` passed all 12 dependency, format, warning-free test compilation and default ExUnit checks. Local status file: `/tmp/fount-handoff-offline-20260924T184522-351998/status.tsv`.

| Package | Default suite |
| --- | ---: |
| Core | 68 passed (67 tests, 1 property) |
| Probe | 43 passed |
| Workshop | 45 passed |

Using the previously created local `fount_verify_20260924_qa` database on PostgreSQL 5433, Core integration passed 8 tests and Workshop integration passed 12 tests. The Workshop suite includes real Afterwriting/Poppler checks. This stage did not create a new fresh database or rerun migrations.

Standalone A4 PDF `/tmp/fount-stage2-a4.pdf` has SHA-256 `f6501b6f747106d1532c4b69831c9229ae5c09577c2a3a4be65204e11d209659`, two pages, no blank pages, A4 dimensions 595.28 × 841.89 points, and embedded CourierPrime. The title and script pages were visually inspected. These files are local temporary evidence, not committed artifacts.

## Still open

The full writer acceptance fixtures have not been run through live generation, review and explicit acceptance. `FOUNT_CODEX_MODEL` was not configured during this stage. In particular W03's ferry/key/reveal repair, W04's two distinct five-to-three routes and measured page savings, W05's chosen outcome/secret/partner repair, W07's six real pass outputs, and W09's end-to-end evidence/strategy/writing run remain unproven.

Additional work remains on full PostgreSQL concurrency and interchange edge matrices; broader audience/access fixtures; chronology, pronouns and relationships; integrated dialogue knowledge/voice and requested voice conformance; broader retrieval/history filters; cross-scene semantic note conflicts; repair-failure artifacts; arbitrary PDF profiles; and mixed speech output. Action line mapping uses text matching against a real PDF and can report unavailable for ambiguous repeated text. Prohibited-fact checks cannot certify the absence of an undeclared invention. Review these as open acceptance work, not passes inferred from the smaller tests above.
