# Phase 2 source delivery

**Phase:** Observe Measurement Substrate Hardening. **Status:** OFFLINE_IMPLEMENTED.
**Date:** 2026-09-26, Pacific/Honolulu.

This overlay adds the Phase 2 measurement contracts, closed typed context, safe
lens/calibration declarations, exact semantic identities, ETS L1 reuse, resource
preflight/accounting, partial-result recovery, recording/import paths, fixture-file
loading, and an inspectable scene-question example. It does not implement Phase 3.

The complete specification and evidence record remain in the separate docset
repository: `handoffs/PHASE_02_OFFLINE_HANDOFF.md`,
`handoffs/PHASE_02_IMPLEMENTATION_MATRIX.md`,
`handoffs/PHASE_02_FILE_INVENTORY.json`, and
`handoffs/PHASE_02_RUNTIME_QC_HANDOFF.md`.

The source-writing environment has no Elixir, Mix or Erlang. ExUnit tests were
written but not executed; no formatting, compile, Credo, Dialyzer, ExDoc, database,
PDF, speech, provider or writer-demonstration success is claimed. Python source,
asset and archive checks do not establish runtime correctness.

The four attachments are raw unsealed Repomix exports. Every modified Fount
preimage is authenticated against a matching post-QC file hash carried in the
supplied Phase 1 inventory. A removed terminal LF is restored only when those
exact bytes match the recorded hash. This is file-level evidence, not proof of an
entire Git checkout or a replacement for future sealed snapshots. The manifest
uses strict original byte hashes; no alternate-LF bypass is requested.

The user applies and commits. Codex verifies the already-applied source and
repairs this phase; it must not reapply the overlay, overwrite unrelated work,
claim inherited Phase 1 green results for changed files, or begin Phase 3.
