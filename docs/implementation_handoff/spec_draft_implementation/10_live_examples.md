# Three live example entrypoints

Create exactly one documented executable entrypoint per package under its `examples/` directory. Each accepts modes/flags so functionality does not require dozens of near-duplicate scripts. All use public package APIs. Shared sample material may live in `examples/support/` or core fixture assets, but shared helpers cannot return fake service results.

```text
packages/fount/examples/live.exs
packages/fount_probe/examples/live.exs
packages/fount_workshop/examples/live.exs
```

Run from the owning package with `MIX_ENV=dev mix run examples/live.exs -- ...`. The output directory defaults to a timestamped directory under the caller's `tmp/fount-live/`. Each run writes `run.json` with start/end times, actual modes, input hashes, repository versions, produced file hashes, provider/model names, real service statuses, failures and artifact paths. Redact keys, connection passwords and provider credentials. Do not commit generated private screenplay outputs.

## Prerequisites

Elixir 1.19+, resolved Mix dependencies, an explicitly configured development PostgreSQL database, and schemas created with the shipped migrations. Core's example needs only PostgreSQL and files. Probe needs System One credentials and authenticated Inference/Codex runtime; Workshop additionally needs the configured afterwriting renderer and PDF utilities. Speech mode needs `espeak-ng`. Library modules do not read environment variables; example/CLI launchers do.

Use `FOUNT_DATABASE_URL` for the explicit example database. Refuse a missing URL; never silently select a production-named default. Give each run a unique project key such as `fount-demo-<uuid>`. Repeated runs create new projects. Do not truncate databases, reset unrelated projects or automatically delete evidence. An optional cleanup command can delete only the recorded demonstration project after explicit request.

The integration runtime uses Inference as specified in 08. A missing credential, unavailable dependency, failed model call or failed renderer exits nonzero with the failing stage. No `--mock`, replay, canned provider response, fake PDF or fake database is allowed. A user-selected mode may omit a service it genuinely does not use; its run report lists only executed functionality. `--all` cannot claim success for skipped modes.

## Core: `live.exs --mode all`

1. Import the real fixture from disk to Document and Screenplay. Resolve fixture bindings dynamically.
2. Verify unchanged Fountain export bytes, then write canonical JSON and supported FDX to real files and reimport them. Report intentional format fidelity differences. Exercise notes/boneyards, title fields, cast, query views, and a separate small dual-dialogue specimen.
3. Create a PostgreSQL project; close/reload through Persistence. Apply a writer edit with a Unicode line, rename a confirmed character and perform a scene split/merge through public operations. Save and inspect history. Demonstrate that a prose mention is changed only when explicitly selected.
4. Save a candidate revision and prove that load still returns the accepted base. Accept with the expected base, reload current and historical revisions using the same loader, and show the unchanged history. Exercise stale acceptance as an expected rejected operation.
5. Export actual accepted Fountain/FDX/JSON and a machine-readable structural comparison. Compare typed content, cast, source handling and authored items after DB reload.

Output: original/edited `.fountain`, `.fdx`, `.json`, fixture bindings, revision/acceptance IDs, diff, import fidelity report and run manifest. This example needs no AI call: it demonstrates the real substrate used by the other two examples.

## Probe: `live.exs --mode all`

Read/import the fixture, create/load its own PostgreSQL project, then call both real services:

- Inference extracts candidate events/facts, character access and scene intentions with exact source references. Validate excerpts before evaluating them.
- Jev evaluates knowledge at the records room/ferry queue, setup support for the key payoff, and a character/dialogue question with Choice plus an action or tactic rubric with Score. Exercise actual Noul/Choice/Score answer decoding.
- Run scene mechanics, dialogue, action and voice tools; report sample insufficiency honestly. The example has enough substantial Dan/Mara turns for the default split, but an imported user file may not.
- Search current and historical content; inspect relevant retrieved source. Compare a pure candidate that removes the key transfer against baseline, including dependency/continuity coverage. Run a legal-prefix boundary trace and one selected clue ablation without claiming causality from threshold movement.
- Save reports with exact source revision relations. Reopen one, resolve its evidence and verify exact quoted bytes.

Modes `knowledge`, `voice`, `consequences`, and `all` are sufficient. `all` runs each tool family T01–T13 where applicable; strategy contrast can compare two small real Inference-generated strategy cards without editing the screenplay. Individual modes are smaller genuine demonstrations. Record request count and actual provider usage when available. Assertions concern valid results, evidence joins, stream accounting and real calls, never a preordained probability or expected model opinion.

## Workshop: `live.exs --mode WORKFLOW`

Modes: `develop`, `alternatives`, `propagate`, `sequence`, `character`, `notes`, `pass`, `recover`, `investigate`, `all`, and optional `speech`. Use the exact request ideas in [fixtures/README.md](fixtures/README.md), resolved to actual IDs. Each mode creates its own project/session so accepting one does not corrupt another demonstration's base. The full demo launcher explicitly allows up to 40 Inference calls and 1,500 Jev states per creative mode, recording those settings before work; users can reduce them or run a single mode. These limits are workload allowances, not promised usage. Individual application requests keep the defaults in 09. All creative modes use real Inference and the applicable real Jev checks. `all` covers W01–W09 and ends with an output index; it does not require speech unless requested.

Every mode saves a session and candidates to PostgreSQL, reopens them, exports a review packet, and writes actual candidate Fountain plus at least one rendered PDF. Sequence renders baseline and both alternatives under the same settings. Develop starts from a genuinely empty root; its pages must come from Inference. Alternatives demonstrates selection, overlapping passage handling and a requested generated join. Propagate produces the multi-scene repairs. Character covers at least three scenes. Notes shows partial note resolution. Recover includes a real previous revision and current adaptation.

With `--accept-demo`, the example explicitly accepts one selected candidate in its newly created demonstration project, checks the accepted-head change and exports it. Without that flag, show candidates while proving the head stayed unchanged. `all --accept-demo` exercises accepted/rejected alternatives, atomic note resolution and history recovery. There is no default writer-draft mutation concealed behind `preview`.

The `pass` mode runs dialogue/subtext, visual/action and dry-comedy directions, producing separate pages. Brevity, tension and custom profiles must also be runnable via `--profile`; shared workflow mechanics do not require three more entrypoints. For W09, materialize two different strategies after investigation. If calls fail or distinct approaches are not produced, record the limitation and return partial/nonzero rather than replacing them with fixture answers.

Speech mode takes a real loaded candidate/draft, creates table-read JSON/HTML and WAV audio through the configured real speech adapter. Verify a nonempty playable audio file and actual turn mapping; no silent track is a successful speech demonstration.

## Example verification and practical scale

The fixture is small to make real feature behavior reviewable. Add `--input PATH` to run on a writer's full draft, and optional resource-limit flags from 09. Never upload unrelated local files. Use exact context from the selected screenplay/history. The request itself authorizes provider calls needed by its live mode; document that services may charge for them without adding repeated confirmation prompts.

Live outputs are evidence of executed behavior, not golden snapshots for default tests. List each command actually run, date, provider/model, success/partial/failure and location of review artifacts. If services cannot be accessed in the implementation environment, still deliver working entrypoints and record them as **not run** in the handoff. Never equate implemented examples with verified live behavior.
