# Changelog

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
