# Fount source continuation handoff - 2026-09-24

## Delivery status

This is an **implemented source continuation, not a verified release**. Full source files, tests, migrations, CLI commands, real-only example modes, profile assets, and an installer are delivered relative to the supplied `fount(1).xml`. No Mix command, Elixir code, PostgreSQL operation, provider call, PDF rendering, speech synthesis, or application test was run in this pass. Python was used only for reading/writing source artifacts, inventory, hashing, ZIP packaging, and packaging validation; any installer exercises are confined to disposable reconstructed file trees.

The original specification remains authoritative. The supplied XML is the implementation baseline, not the earlier partial overlay manifest. The original specification is retained under [spec_draft_implementation](spec_draft_implementation/README.md). Do not reinstall the old partial overlay.

## What the continuation adds

The new `FountWorkshop.Session`/`Candidate` path turns a validated writer request into inspected context, distinct strategies, actual typed screenplay edits, immutable candidate revisions, and a review packet. It supports development/bridging, alternatives and selective joins, story-change repairs, sequence rebuilding, character workspaces, coordinated notes, six passes, historical scene recovery/adaptation, and investigation remedies. Explicit selection, writer editing, conservative rebase, audition, and acceptance are separate operations. Generating or exporting a candidate does not accept it.

Core now has contract validation, replayable local references, canonical identity-preserving JSON, revised revision-scoped persistence definitions, a second schema-hardening migration, and Core CLI commands. Probe now has fragment-level evidence projections, access-ledger support, real SDK evaluation and typed policies, extraction/retrieval/constraint/knowledge/dependency/continuity/dialogue/voice/action/comparison tools, finite investigation planning, and question-profile identities. Workshop adds the saved session path, actual proposal generation through Hex Inference/Codex, group/range combination with generated joins, review export, measured PDF comparisons and table-read/audio paths.

**There are still implementation gaps, not just unavailable verification.** In particular, fine-grained edit-scope enforcement, several Probe options, foreign-project historical copying, full semantic conflict/repair coverage, and investigation follow-up remain unfinished. Read [KNOWN_GAPS.md](KNOWN_GAPS.md) before accepting generated writing or describing the product as complete.

## Package layout and entry points

| Package | Ownership | New entry points |
| --- | --- | --- |
| `packages/fount` | Source/IR, typed edits, canonical store and interchange | `Fount.Interchange`, `Fount.Writing.Schema`, `Fount.CLI` |
| `packages/fount_probe` | Evidence-backed inspection; no accepted-head writes | `FountProbe.run/5`, `execute/4`, `plan/4`, `explain/5`, `Profile`, `Jev` |
| `packages/fount_workshop` | Writer requests, saved strategies/candidates, review and explicit decisions | `Session`, `Workflows`, `Candidate`, `Strategy`, `Acceptance`, `Review.export/4` |

The previous `Develop`, `TargetedRewrite`, `SequenceRebuild`, `NoteResponse`, `Pass`, `CharacterRewrite`, and `Recover` convenience APIs are preserved, rather than silently deleted. The new CLI writing path uses the new session implementation. Their earlier narrower behavior is not evidence of complete workflow acceptance. Compatibility between old convenience paths and new stricter persistence must be exercised locally.

## Reading order for the receiving agent

1. [CONTINUE_PROMPT.md](CONTINUE_PROMPT.md): instructions to apply, fix, verify and finish.
2. [SETUP.md](SETUP.md): installer, exact repository paths, fresh database and dependency configuration.
3. [KNOWN_GAPS.md](KNOWN_GAPS.md): prioritized source gaps and risks.
4. [FEATURES.md](FEATURES.md): all F01-F09, W01-W09 and T01-T13 mapped to source/tests/live modes.
5. [API_MAP.md](API_MAP.md) and [OPERATIONS.md](OPERATIONS.md): concrete API/state flow and commands.
6. [VERIFICATION.md](VERIFICATION.md): prior evidence versus all newly unrun checks.
7. [CHANGES.md](CHANGES.md), [WISHLIST.md](WISHLIST.md), [SOURCE_RECORD.json](SOURCE_RECORD.json).

## First local actions

Inspect local changes in `~/p/g/n/fount`. Dry-run the supplied installer; review any mismatched preimage or new-file collision rather than forcing a replacement. The manifest includes exact reconstructed XML-body hashes and a separately computed one-terminal-LF alternative. That alternative is accepted only with the explicit `--allow-terminal-newline` option after review. There is no Git HEAD/SHA guard and no reset operation. Run the offline checks in all three packages, fix compilation/format/test defects, then use an explicitly chosen fresh PostgreSQL database for integration and authorized live modes. Keep all prior-run evidence dated and separate.
