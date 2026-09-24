# Implement Fount's creative screenplay workflows

You are implementing Fount, a PostgreSQL-backed screenplay writing and revision environment. Your inputs are this entire `spec_draft_implementation/` docset and three Repomix XML files named **`fount.xml`**, **`system_one_sdk.xml`**, and **`inference.xml`**. Read the complete docset and inspect the source in all three XMLs before implementation. Earlier brainstorming files and this conversation are not required inputs.

## Intended product

Build powerful writing operations that produce actual screenplay pages: develop from a brief, continue/bridge scenes, explore different dramatic approaches, audition and combine alternatives, change a story decision and repair consequences, rebuild sequences, rewrite a character across the draft, turn notes into coordinated edits, run creative passes, recover/adapt earlier writing, and investigate a creative problem before writing remedies.

The screenplay-specific tools—knowledge, continuity, dependencies, dialogue, voice, scene mechanics, search and comparisons—support those writing operations and are also callable by an external agent. Implement both. A collection of analysis reports without usable creative workflows is incomplete. Features determine the schema, architecture and tests.

## Read in this order

1. `README.md`, `01_features_and_research.md`, `01a_creative_workflows.md`.
2. `02_repository_audit.md` and the three XML sources. The XMLs determine your actual starting code; audit hashes are reference information.
3. `03_architecture.md` through `09_workshop.md` and every asset under `contracts/`.
4. `10_live_examples.md`, `11_tests.md`, `12_build_sequence.md`, `13_wishlist_and_upstream.md`, `14_delivery_and_handoff.md` and `fixtures/`.

Follow the build sequence and feature acceptance scenarios. Correct a verified source/API mismatch with the smallest feature-preserving change and record the reason. Do not silently reduce the feature scope, leave placeholder commands, or replace actual writing with a strategy report when pages are requested.

## Implementation authority and boundaries

Fount is greenfield. Change, replace or remove its current APIs, stores, schema and internals as needed, updating all callers/tests/docs together. Preserve useful screenplay handling and source fidelity. PostgreSQL is the sole application store; replace the current partial persistence with the specified revision-scoped schema. No legacy data migration is required; document fresh-database setup and never automatically drop an existing user's database.

Use three Mix packages: `packages/fount`, `packages/fount_probe`, `packages/fount_workshop`. Core has no model dependency. Probe uses System One/Jev for repeated semantic evaluations and Inference for extraction/investigation. Workshop uses Inference for creative reasoning and actual writing, plus Probe checks. All completions go through **Inference with Codex**. `agent_session_manager` is the optional runtime behind Inference's adapter, not a Fount API or a fourth source export you need to receive. Dependency setup is in 08.

Do not implement Antigravity support. Keep its current adapter limitation in the wishlist. Do not modify System One or Inference in the Fount overlay, copy their internals into Fount, add alternate direct provider calls, or simulate an unavailable capability. Document a concrete upstream gap if one genuinely blocks a desired future feature.

Use ordinary modules/functions, PostgreSQL and SDK batching. Avoid generic workflow runtimes, distributed queues, vector/graph databases and infrastructure that does not serve a specified writing feature. Craft observations are questions and evidence, not universal judgments. Jev probabilities are not facts, guaranteed calibration or artistic quality scores. Preserve uncertainty and inspected scope.

## Required behavior

Implement all F01–F09 foundations, all W01–W09 creative workflows and the T01–T13 tool families. Strategies and candidates are durable domain objects. Candidates contain actual typed screenplay edits and complete revision values. Produce source/structural diffs, in-context pages, inventions, group dependencies, requested checks and source provenance. Let writers select/combine/recover passages and resume a session. Generated edits never advance the accepted head until explicit acceptance.

Implement exact IDs, UTF-8 span rules, local reference allocation, pure edits, stable identity for retained material, revision-aware evidence and one loader for current/history/candidate values. Separate writer intent from model interpretations. Protect selected text and story requirements; a model must not repair a failure by quietly changing the requirement.

Support real Fountain import/export, supported FDX/JSON interchange with explicit fidelity reports, real PostgreSQL persistence, proper spec PDF rendering and table-read export with optional real speech. Page-saving claims require measured output under identical renderer settings.

## Tests and live examples

Default `mix test` in all three packages must run offline: no live model/API calls, PostgreSQL, renderer, speech process or authenticated CLI. Use real deterministic code and temporary files, SDK Test clients, Inference Mock and focused doubles at external boundaries. Tests cover actual writing/editing behavior and the minimum supporting infrastructure needed to trust it. Explicit PostgreSQL/PDF integration checks live outside default tests.

Create the **three live entrypoints** specified in 10, one per package, with modes covering functionality. Examples are live only: real files, database, PDF, Jev and/or Inference where applicable. No mock/replay/canned-response mode or fake generated artifact. Use the original supplied fixture and dynamically bind its IDs. Develop mode must generate pages from an empty root. Creative modes must return actual candidate writing. Missing services fail the requested mode explicitly.

Run checks and live examples when your execution environment permits. Record exact commands/results and distinguish not run from passed. If external services are unavailable, still implement complete executable examples and give the follow-on agent exact commands; never fabricate run evidence.

## Required delivery

Produce **`fount-overlay.zip`**, containing the full contents of every new and modified Fount file at paths relative to the Fount root. Include code, tests, migrations, profiles, fixtures, examples, documentation and lockfiles. Include a manifest with original/result hashes, modes and explicit deletions, plus an inspectable overlay application script supporting preflight/dry-run and preserving conflicting local changes. A prose-only response or patch-only archive does not satisfy this request.

Also produce a **follow-on handoff docset** under `docs/implementation_handoff/` inside the overlay and as an extracted delivery. It must include a `CONTINUE_PROMPT.md` telling the next agent that the repositories are located at:

- `~/p/g/n/fount`
- `~/p/g/n/system_one_sdk`
- `~/p/g/n/inference`

The prompt instructs that agent to inspect local changes, apply the full-file overlay and deletions to Fount, preserve unrelated work, set up the fresh PostgreSQL schema without deleting an existing database, run offline tests in all three packages, execute configured real example modes and inspect their outputs. Include feature mapping, setup, operations, actual verification, changed APIs/schema, remaining limitations and upstream wishlist as required in 14.

Your final response links the ZIP, manifest and handoff; summarizes completed features and verification; and names any real external blocker. Complete the implementation before delivering. Do not stop after scaffolding or substitute speculative design for required code.
