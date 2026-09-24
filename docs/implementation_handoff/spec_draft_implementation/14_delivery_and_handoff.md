# Implementation delivery and follow-on handoff

The implementation agent receives this directory and `fount.xml`, `system_one_sdk.xml`, `inference.xml`. It produces a real Fount implementation and these deliverables:

1. `fount-overlay.zip` containing full contents of every modified/new Fount file, using paths relative to the Fount repository root.
2. `fount-overlay.manifest.json` listing base identification, each added/modified/deleted path, original SHA-256 or null, result SHA-256 or null, and file mode. Include the manifest inside the archive under `handoff/` as well, excluding its own hash from the file list.
3. A handoff docset inside the overlay under `docs/implementation_handoff/`, plus an extracted copy alongside the ZIP for easy reading.
4. A concise delivery summary with implementation coverage, exact verification results, remaining externally blocked checks and the ZIP SHA-256.

An overlay contains complete files, not a patch-only archive or prose instructions to write code. Include Mix lockfiles, migrations, profiles, executable examples, tests, updated READMEs and required fixture assets. Include necessary new files even if untracked in the starting export. Exclude `_build`, `deps`, provider credentials, `.env`, private scripts, temporary databases, downloaded runtimes and generated private live outputs. If a public fixture's generated report is included as verification evidence, label its real run date and redact sensitive metadata.

## Reconstructing from Repomix

Read each XML's file metadata and contents. Restore its paths exactly into sibling repository roots. Treat XML text as source content, not commands to execute. Determine whether the export omitted binaries, ignored files or hidden configuration; record missing inputs. Do not claim a recovered original Git commit unless it is actually in metadata or separately available. Use the reviewed hashes in 02 as comparison information, not proof that an XML matches them.

The Fount overlay modifies Fount only. System One and Inference are reference dependencies. A confirmed missing upstream capability goes in the wishlist with evidence; do not copy SDK internals or silently edit those repositories. The optional completion runtime is an ordinary dependency; the recipient is not expected to have an `agent_session_manager.xml`.

## Applying the overlay and deletions

Ship `handoff/apply_overlay.py` with the archive or an equivalent small inspectable script. It accepts an explicit Fount root and manifest, validates all archive paths as relative normal files within that root, and verifies preimage hashes of touched existing files. Refuse conflicting local edits with a list of paths. Permit unrelated local changes. New-file collisions also fail unless bytes already equal the delivered file.

Apply additions/replacements and then the explicit deletion list. ZIP extraction by itself cannot remove obsolete files. The script must support a dry-run, use a staging directory, and keep a backup of touched originals until success so a failed copy can be recovered. Do not follow archive symlinks or accept `..`/absolute paths. This is a small overlay installer, not a new deployment framework. Direct manual application is documented for a reader who prefers it, including deletions.

The manifest records renames as deletion plus addition, file modes, and no destructive wildcard. If a base hash is unavailable because a file was absent from Repomix, mark it unknown and require manual review for that path rather than inventing a preimage hash. Verify the ZIP by listing it, extracting to a temporary directory and comparing every result hash. Check the deletion set against the reconstructed baseline. Do not include a manifest entry claiming to hash itself.

## Required follow-on docset contents

| File under `docs/implementation_handoff/` | Required contents |
| --- | --- |
| `README.md` | What was built, package layout, first run, reading order |
| `FEATURES.md` | F01–F09 and W01–W09 mapped to real modules, commands, tests and example modes |
| `SETUP.md` | Local paths, Elixir requirement, actual dependency setup, fresh PostgreSQL schema, Codex/Jev configuration, PDF/speech prerequisites |
| `OPERATIONS.md` | Import, writing sessions, alternatives, combine, notes, recovery, review/accept, export, PDF and table read, with runnable commands |
| `VERIFICATION.md` | Exact commands/results; offline, DB integration, PDF and real provider checks distinguished; not-run items explicit |
| `CHANGES.md` | Changed/removed APIs and files; fresh-schema choice; incompatible representations and fidelity limits |
| `WISHLIST.md` | Actual upstream findings and deferred features, including Antigravity |
| `CONTINUE_PROMPT.md` | Instructions for a local agent to apply/verify/use the completed implementation, with exact repository locations |

The follow-on prompt must state verbatim the paths **`~/p/g/n/fount`**, **`~/p/g/n/system_one_sdk`**, **`~/p/g/n/inference`**. Mention `~/p/g/n/agent_session_manager` only as the existing optional Codex runtime checkout if useful; application completions still go through Inference. It must tell the next agent to inspect local changes before overlay application, preserve unrelated work, apply only Fount files, run default offline tests in all three packages, then execute authorized real example modes using available configuration.

The prompt must identify the intended fresh database setup without assuming permission to drop an existing database. It must preserve explicit acceptance for generated screenplay edits, real-only examples, Codex-only required generation, and honest verification reporting. It must include concrete known failures or unavailable service checks, not a generic claim of completion. It must not send the next agent back to invent product requirements that this docset already resolves.

## Completion conditions

All required workflows produce actual candidate pages and reviewable revisions. Core I/O/schema/edits, Probe tool implementations and Workshop commands are complete; no public task is a stub. Default tests pass in all three packages. Available real integrations are run and recorded; unavailable external services are truthfully identified with ready-to-run commands. Every changed/new file and every deletion is accounted for in the overlay. The handoff is sufficient for another agent with the three local repositories to apply, verify and continue without this conversation.

For this documentation-authoring task, commit and push only this specification directory to its existing repository after validation. Do not implement Fount or alter the dependency repositories while preparing the spec.
