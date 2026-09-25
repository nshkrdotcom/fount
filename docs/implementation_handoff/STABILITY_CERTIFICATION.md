# Stability certification gate — 2026-09-24

## Decision and claim boundary

Feature development is frozen. Certify only the **implemented and explicitly supported behavior** after it passes the gates below. The original [F01–F09, W01–W09 and T01–T13](FEATURES.md) specification remains the feature target, but unimplemented extensions are tracked in [FUTURE_DEVELOPMENT.md](FUTURE_DEVELOPMENT.md). Passing a stability gate cannot be called full original-spec feature acceptance. A failed supported behavior must be fixed or explicitly excluded from the certified surface with a reproducible reason; it must not be silently renamed as a future feature.

No release certification is claimed yet. The separate [Stage 2 record](STAGE2_STATUS_2026-09-24.md) has dated evidence and precise limitations. The source-only [VERIFICATION](VERIFICATION.md) and [KNOWN_GAPS](KNOWN_GAPS.md) records are historical, not current pass/fail summaries.

## Gates and current evidence

| Gate | Required result | Current evidence / status |
| --- | --- | --- |
| S01 · clean reproducible build | Dependency resolution, formatting, warning-free `MIX_ENV=test` compilation and default tests in Core, Probe and Workshop with external credentials unset | Passed after final source changes in `/tmp/fount-handoff-offline-20260924T195206-398419/status.tsv`: Core 69, Probe 45, Workshop 48. |
| S02 · transactional persistence | Fresh disposable PostgreSQL database, all migrations, Core and Workshop integration, rollback, report references, same-head race and immutable reload | New `fount_verify_20260924_fresh_cert` database migrated through all three migrations; Core 10 and Workshop 12 integration tests passed. Full adversarial race/rollback matrix remains unproven. |
| S03 · supported interchange and edit safety | Malformed canonical input rejected; supported Fountain/JSON/FDX and typed edits roundtrip; out-of-scope changes, stale bases, forged reports and bypassed acceptance rejected | Selected offline/integration tests passed. Comprehensive adversarial matrix remains open. |
| S04 · provider and Probe integrity | Real configured completion and Jev call; exact evidence joins, partial/error accounting, access-boundary fixtures and source IDs; no model opinion promoted to fact | Provider connectivity and partial bridge/alternatives/recovery paths exercised. Full tool/fixture matrix remains open. |
| S05 · writer workflow smoke and review | All nine existing modes produce reviewable real candidates or explicit partial failures; inspect story fixture assertions; candidate generation/export does not advance accepted head | Bridge, alternatives and recovery have partial live evidence. `propagate` and `sequence_routes` stopped with explicit `:context_limit` before candidates. Prompt compaction fixes the oversized input in a local regression; a resumed sequence run reached the provider but ended on a `provider_error/runtime` response. Other modes and explicit acceptance paths are open. |
| S06 · rendering and speech | Real PDF and visual settings check; optional per-turn speech only if configured; report unavailable rather than invent output | A4 PDF inspected, Workshop PDF integration passed. Per-turn speech is unrun. Mixed master audio is deferred feature D17. |
| S07 · release hygiene | No secrets in logs/artifacts; documented known limits; final diff review, repeat S01 and relevant integration, commit/push evidence | Open. |

## Certification outcome rule

Report each gate as passed, failed, partial, or not run with command, date, and artifact path. If S01, S02, S03 or S07 is incomplete, do not call even the bounded implementation stable. If S04–S06 are incomplete, identify the exact unverified surface and certify only a narrower surface if it is useful and truthful. Real model generation can demonstrate operation but cannot guarantee screenplay quality or a universal semantic judgment. A candidate and review packet are not an accepted revision.

The current pass may repair regressions in supported behavior, improve tests that expose those defects, and update evidence. It may not implement the deferred capabilities in FUTURE_DEVELOPMENT merely to turn this table green. The original full-feature acceptance remains a separate future effort.
