# Fount code delivery and continuation

## Status

This is a **partial implementation handoff**, not the completed
F01–F09 / W01–W09 / T01–T13 release requested in the supplied specification.
Do not infer feature completion from an existing filename or from earlier
conversation claims. Runtime verification has not established completion.

The overlay preserves recoverable prior source changes and adds concrete code
for UTF-8 evidence spans, canonical JSON fingerprints, candidate-local reference
allocation, group dependency ordering/selection, review validation, probabilistic
decision policies, evidence registries, SDK batch-index association, and the
Inference structured/text completion boundary. Focused ExUnit tests accompany
these additions. Six creative profile assets and the original fixture/contracts
are included.

These components are **not yet fully integrated** into the required public
Screenplay/Persistence/Probe/Workshop APIs. In particular, the complete fresh
PostgreSQL persistence replacement, all creative workflows, complete tool
families, safe candidate lifecycle, and all real examples remain release work.
See FEATURES.md and CONTINUE_PROMPT.md. The implementation scope is not reduced:
the entire authoritative specification travels in `spec_draft_implementation/`.

## Reading order

Read VERIFICATION.md, CHANGES.md, FEATURES.md, SETUP.md, and CONTINUE_PROMPT.md.
Then follow the original specification's reading order and build sequence.

## Package layout

- `packages/fount`: retained deterministic parser/core plus new writing helpers.
- `packages/fount_probe`: dependency manifest and concrete probabilistic/evidence
  support code; a complete T01–T13 tool catalog is not claimed.
- `packages/fount_workshop`: retained Workshop plus new change-group/review and
  Inference completion support; complete W01–W09 orchestration is not claimed.

The installer defaults to a dry-run and refuses changed preimages or new-file
collisions. It preserves unrelated local changes and keeps touched originals
under a transaction-specific backup directory. No installer action touches
PostgreSQL or either dependency repository.
