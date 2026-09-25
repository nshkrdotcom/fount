# Apply, verify, and finish the Fount source continuation

You are the local implementing agent with the actual environment. Your repositories are **`~/p/g/n/fount`**, **`~/p/g/n/system_one_sdk`**, and **`~/p/g/n/inference`**. Apply and edit Fount only. You receive `fount-overlay.zip`, its exact external manifest, deletion list, installer, extracted handoff, and the existing original specification under `docs/implementation_handoff/spec_draft_implementation/`.

This overlay contains substantial implemented source, tests, migrations, commands, real example modes and supporting assets. It is **not a verified release**. The source-writing agent could not run Mix, Elixir, PostgreSQL, providers, tests, rendering or speech. Python artifact inspection/packaging is not runtime verification. No independent code-review agent ran. Preserve that provenance and all dated earlier-run evidence. Do not claim unrun checks passed.

## Start with the actual state

Read this handoff's README, FEATURES, KNOWN_GAPS, API_MAP, SETUP, OPERATIONS and VERIFICATION. Read the original complete specification in its README order, especially creative workflows, Probe tools, Workshop, live examples, tests, build sequence, contracts and fixture. Inspect current source before changing it. The specification remains the feature target; the supplied Fount XML was the overlay baseline. The old progress notes/manifest are not an instruction to reconstruct an earlier overlay or remove stores already removed.

Inspect `git status --short` and local diffs before application. Preserve unrelated changes. Dry-run the provided installer against `~/p/g/n/fount`, the ZIP and the external manifest. Review preimage mismatches and new-file collisions manually; there is no force/reset escape hatch. If an inspected mismatch is only the XML body's missing final newline, use the manifest's computed one-LF alternative via `--allow-terminal-newline`, then dry-run again. Apply only after conflicts are reconciled; retain `.fount-overlay-backups/`. Do not require an exact Git HEAD, reset a branch, remove unrelated files or drop a database. Deletions in this delivery are explicitly empty.

## Finish the actual implementation, not its labels

First compile and inspect the new cross-package call paths. All new source is unformatted/uncompiled by Elixir in this pass; fix real errors and run all old and new tests. The old convenience APIs remain and must continue to work or be consciously revised with documentation and corresponding source tests. Keep Hex `inference` and Hex `agent_session_manager`; use the sibling System One dependency exactly as the supplied source specifies. Do not edit either reference repository, introduce direct alternative providers, add Antigravity, copy SDK internals or create a generic workflow runtime.

Prioritize the explicit known gaps:

1. Complete strict edit-scope enforcement for byte spans, insertion positions, moved outside-scope elements and restricted character workspaces. Prove selected candidate groups, local IDs, overlaps, rebases and note dependencies cannot bypass it.
2. Harden actual candidate/report/source/session identity checks and complete the PostgreSQL FK/deferrable-trigger/rollback/concurrency matrix. Keep immutable original bases and explicit writer review. Repeated identical acceptance is idempotent; different repeated decisions conflict.
3. Finish Probe's marked incomplete option semantics, same-scene dependency links, full chronological/access/behavior localization, integrated dialogue knowledge/voice checks, profile threshold dispatch and measured action layout density. Unknown results remain unknown or errors, never zero or clean checks.
4. Finish multi-stage partial note resolution and semantic note conflict handling; complete exact partial/cross-screenplay recovery with new IDs and explicit cast mapping; implement structured hypothesis records and the single allowed investigation follow-up cycle. Retain successes and failures across session retries without silently shifting base or spending again.
5. Complete remaining PDF/profile/CLI edge behavior and actual feature-specific tests. Do not claim universal craft correctness or page savings from word counts or model probabilities.

Use FEATURES for all F01-F09, W01-W09 and T01-T13, not merely this priority list. A tool name, prompt asset, successful model request or saved report is not a complete writer action. Keep actual candidate screenplay pages and writer choice central.

## Verify in stages

For each of `packages/fount`, `packages/fount_probe`, `packages/fount_workshop`, record actual results for dependency resolution, `mix format --check-formatted`, `MIX_ENV=test mix compile --warnings-as-errors`, and `MIX_ENV=test mix test` with `SYSTEM_ONE_API_KEY`, `FOUNT_DATABASE_URL`, `FOUNT_CODEX_MODEL` unset. Use `scripts/verify_handoff.sh --offline` or the exact commands in VERIFICATION. Resolve actual Hex versions locally and retain legitimate lockfiles; never fabricate a resolution. Fix failures and rerun the full suites, not only a targeted test.

Use an explicitly chosen fresh `FOUNT_DATABASE_URL`. Confirm the intended local host/port without disclosing credentials. Apply both migrations using the actual current Ecto API. Never drop/reset a pre-existing database. Execute Core and Workshop integration tests; these use real PostgreSQL and, where required, real PDF tooling, though some provider inputs are intentionally offline fixtures.

Install/confirm Workshop's pinned Afterwriting and Poppler commands before actual PDF integration. Run configured real modes from each owning package with `MIX_ENV=dev mix run examples/live.exs -- --mode MODE --out DIRECTORY`. The `/home/home/scripts/with_bash_secrets` wrapper may be used for authenticated calls if present, without printing its environment or output secrets. No live entrypoint may substitute mock data after failure.

Run all new writer modes: bridge, alternatives, propagate, sequence_routes, character_workspace, grouped_notes, pass_all, recover_scene, investigate. Also retain/regress the original modes and run Core interchange and Probe tools/voice/knowledge_access/consequences. Visually inspect actual PDF pages and compare page counts only with identical settings. Run optional speech only when configured; otherwise record it not run. Ordinary candidate generation and packet export must leave the accepted head unchanged.

Demonstrate the exact fixture outcomes: retained bridge neighbors plus edited/reopened/explicitly accepted candidate; two alternatives and a third attributed combined candidate with real joins; reveal movement from scene 3 to 6 with earlier accusation repaired, independent ferry motive and key setup/use retained, and before/after knowledge; two meaningfully different five-to-three routes with protected text and measured PDFs; character-wide actions/voice/partner responses with chosen secrets/outcomes; grouped local/sequence notes and partial acceptance; six real passes; historical/current/proposed recovery; revised hypotheses, three strategies and at least two written investigation remedies. The earlier sequence run saved zero pages. Do not invent improvement to close that case.

## Return evidence and a truthful handoff

Record commands, passed/failed/partial/not-run statuses, real IDs, generated public-fixture artifacts and hashes. Keep prior results dated and separate from your reruns. Update the handoff and exact source manifest for your final changes. List all remaining implementation gaps explicitly; do not replace missing functionality with another roadmap or claim release completion while a required case remains a prompt/helper. Preserve the user's screenplay, unrelated local work, credentials, immutable history and explicit acceptance choices throughout.
