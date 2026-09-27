# Changelog

## Unreleased - Phase 1 offline implementation

- Split atomic measurements and screenplay interpretation into Observe and Intelligence; update Workshop to the new services without changing explicit acceptance.
- Preserve existing writing/analysis behavior and add source-evidence, batch/cache/boundary tests and a writer demonstration.
- Runtime verification is pending; prior success records do not certify this change.

## 0.1.0 - 2026-09-23

Initial implementation of the Fount headless screenplay substrate:

- byte-preserving Fountain source scanner and CST
- semantic screenplay IR with stable identities and source spans
- exact untouched-source round-trip path
- source-patch edit algebra and change sets
- identity reconciliation across edits
- query/index APIs
- annotation/analyzer APIs and built-in character, location, and dialogue analysis
- semantic and source diff support
- filesystem and SQLite stores behind a common behavior
- JSON projection and FDX import/export adapters
- validation and diagnostics
