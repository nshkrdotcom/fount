# Continue the Fount implementation from the attached full-file source overlay

You have a **partial code implementation handoff**, not a completed release.
Continue the actual implementation; do not replace it with another speculative
design, repeat the previous environment excuses, or claim all features exist
because some support files have been written.

## Repositories and inputs

The repositories are located at:

- `~/p/g/n/fount`
- `~/p/g/n/system_one_sdk`
- `~/p/g/n/inference`

Inputs are `fount-overlay.zip`, `fount-overlay.manifest.json`, the inspectable
`apply_overlay.py`, and this docset. The entire authoritative implementation
specification is included under `docs/implementation_handoff/spec_draft_implementation/`.
The original `fount.xml`, `system_one_sdk.xml` and `inference.xml` describe the
baseline when available; the actual local checkouts and local changes must be
inspected before application.

Read this handoff's VERIFICATION.md, CHANGES.md and FEATURES.md first. Then follow
the specification's complete reading order, including all contracts and the
original fixture. Do not ask the user to invent product requirements already
specified there.

## Apply safely

1. Inspect `git status`, local diffs and untracked work in all three repositories.
2. Read the installer and manifest. Run its dry-run against Fount.
3. Preserve unrelated changes. A changed touched file requires an explicit
   three-way/manual content review, not a force reset. New-file collisions must
   also be reviewed. Apply complete files and the explicit deletion list; plain
   ZIP extraction cannot implement deletions.
4. Apply only to Fount. Do not copy code into or edit System One or Inference.
   Keep the installer's backup until verification is finished.

Do not rely on prior conversation statements that core persistence or all Probe
tools were completed. Determine the actual source state.

## Concrete source already supplied

Integrate or move the supplied components into their specified owning APIs,
rather than retaining duplicate long-term models:

- `Fount.Writing.UTF8Span`: byte-span validation and exact pin relocation.
- `Fount.Writing.CanonicalJSON`: deterministic JSON encoding and hashing; add the
  proper domain projection before using it as content_hash.
- `Fount.Writing.LocalReferences`: explicit local declarations and UUID mapping.
- `FountWorkshop.Writing.ChangeGroups`: stable dependency ordering and explicit
  missing-dependency handling.
- `FountWorkshop.Writing.ReviewGate`: pure review checks, not a head transaction.
- `FountProbe.Writing.DecisionPolicy`: typed probability/allowed-mass/crossing
  interpretation.
- `FountProbe.Writing.Evidence`: exact revision-aware registry validation.
- `FountProbe.Writing.Executor`: public SDK preparation/batching and index joins;
  complete SDK Test-client coverage and report serialization.
- `FountWorkshop.Writing.Completion`: Inference structured/text output, mandatory
  local validator and limited malformed-output repair.
- Their new ExUnit tests, six writing profile assets, reference contracts and
  the original screenplay fixture.

The helpers are not an implementation of all required workflows. Inspect and
correct their source/API details against the actual dependency checkouts.
Preserve the original useful Fountain parser/CST/IR and source fidelity.

## Finish the implementation

Follow `12_build_sequence.md` from the first genuinely unfinished task. Complete
all F01–F09, W01–W09 and T01–T13. In particular:

- Implement the full typed canonical edit union, exact IDs and current UTF-8
  spans, local references, stable retained sequence identities, dual integrity,
  cast decisions, authored items, indexes/slices and change-impact closure.
- Replace partial persistence and old filesystem/SQLite stores with the complete
  immutable revision-scoped PostgreSQL schema. Use one loader for accepted,
  historical and candidate values. Implement create/save/load/history,
  optimistic session updates, candidate saves, reports and atomic accept/reject.
- Complete actual writing from an empty brief, continuing/bridging, alternatives,
  selection/combination with pinned passages and generated joins, story changes
  with consequence repair, sequence rebuilding, character rewriting, note
  workflows, six passes, real history recovery, and investigation that writes.
- Complete exact evidence retrieval, perspective isolation and every specified
  Probe tool. Missing results are errors/unknown, never zero or a clean check.
  Jev is probabilistic and has no artistic quality score.
- Complete safe stale-base/review checking, explicit acceptance, source and
  structural diffs, inventions, source provenance, review packets, durable resume
  and real candidate values.
- Complete all CLI commands, proper runtime Afterwriting PDF integration,
  table-read exports and optional real espeak speech. Page-saving claims require
  measured baseline/candidate output under identical settings.

Core must have no model dependency. Probe consumes System One and Inference.
Workshop consumes Inference and Probe. All generative completions use
**Inference with Codex**. `agent_session_manager` is only Inference's optional
runtime. No Antigravity, no direct alternate provider or CLI wrapper, no copied
SDK internals, no general workflow runtime, no graph/vector database.

## Fresh database and dependency setup

Resolve dependencies in all three Fount packages and write genuine lockfiles.
The new Probe lock may be empty; do not call it resolved. Preserve compatible
actual versions and inspect transitive sibling dependencies.

Implement/review the fresh migration from the supplied reference SQL before
migrating. Choose an explicit **unused development database**. Never drop,
truncate or reset an existing database. `FOUNT_DATABASE_URL` must be explicit
for real examples; keep passwords out of reports.

## Verify locally

First ensure default application/test startup cannot start PostgreSQL, a
renderer, speech or authenticated provider. Move real checks outside `test/`.
Use SDK Test clients and Inference Mock at the real external boundaries; keep
pure screenplay behavior and temporary file I/O real.

For each of `packages/fount`, `packages/fount_probe`, and
`packages/fount_workshop`, run:

```bash
mix deps.get
mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
env -u SYSTEM_ONE_API_KEY -u FOUNT_DATABASE_URL -u FOUNT_CODEX_MODEL \
  MIX_ENV=test mix test
```

Then run explicit PostgreSQL and PDF integration checks against the new
development database. Create exactly these executable real-only entrypoints:

```text
packages/fount/examples/live.exs
packages/fount_probe/examples/live.exs
packages/fount_workshop/examples/live.exs
```

Execute configured real modes from each owning package with:

```bash
MIX_ENV=dev mix run examples/live.exs -- --mode MODE
```

Use dynamic fixture bindings, not hardcoded UUIDs. Develop must generate actual
pages from a genuinely empty root. Each creative mode saves/reopens candidates,
exports actual Fountain/review output and renders real PDFs. Exercise
`--accept-demo` only in newly created demonstration projects, and prove that
without it the accepted head does not move. Inspect the actual pages and use
PDF tools plus visual inspection; do not equate a nonempty PDF with correct
screenplay layout. Run speech only when configured and verify real playable
audio. Missing required services produce a failed/partial requested mode, not
mock output or a passing skipped mode.

## Deliver the completed result

Keep exact command results and distinguish passed, failed and not run.
Record concrete known failures, not only generic limitations. Update the
feature map with actual source/tests/commands/mode evidence. Provide the full
new/modified-file overlay, explicit deletions, hashes/modes, safe installer,
resolved lockfiles and updated handoff. Do not claim the release is complete
while any required workflow is merely a prompt, catalog name or support helper.
