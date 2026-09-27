# Phase 1 source overlay

This overlay implements the direct four-package split and preserves writing workflows. It is OFFLINE_IMPLEMENTED, not runtime verified. Apply and commit source/docset yourself; Codex then repairs and completes this same phase. No Phase 2 work is authorized.

## Input identity limitation

All four attachments were identified from packed contents. They are raw/unsealed Repomix exports; the strings mentioning the sealing helper inside their source are not embedded seals. Attachment SHA-256 and decoded file bodies are known. Exact original checkout bytes and Git commit identities are not authenticated. Historical preparation commits are not substituted for those missing identities.

Manifest preimages are exact decoded snapshot-body hashes, with a separately computed body-plus-one-LF alternative where appropriate. Real-checkout applicability is unverified. The strict applier must refuse every other mismatch. The terminal-newline alternative requires deliberate review and `--allow-terminal-newline`; it does not authorize CRLF normalization or overwriting local edits. If a mismatch is more than that exact alternative, stop, inspect the actual file and rebuild/reseal affected preimages rather than forcing application.

The overlay deletes all 86 supplied files under the retired package. Unseen excluded assets/build products cannot be safely enumerated from these inputs; Codex must inspect any remaining physical directory. The original applier does not remove directories. After applying files, use:

```bash
python3 handoff/prune_deleted_directories.py --root . --archive /absolute/path/fount_phase_01_overlay.zip
```

This only removes empty ancestors of manifest-deleted files. It reports any remaining ancestors and never deletes an unseen file. `packages/fount_probe` must ultimately be absent for phase completion.

## Runtime responsibilities

The supplied SDK exposes 0.6.0 APIs. Set `FOUNT_SYSTEM_ONE_SDK_PATH` to the actual SDK package checkout when needed; its publication on Hex is not assumed. Codex resolves/records dependencies and lockfiles, runs formatting/compilation/tests/architecture/Credo/Dialyzer/docs/package gates, prepares PostgreSQL, exercises the writer demonstration and existing integrations, and performs authorized small live checks. No Elixir, database, PDF, speech or model check was executed here.

The complete docset has the detailed preservation audit, current progress and Codex handoff. Archive validation against a reconstructed snapshot is not verification against your real checkout.
