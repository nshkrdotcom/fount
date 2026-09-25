# Writer operations and real examples

All commands below are **instructions for the local agent**, not recorded successful runs. Use the owning package directory and a fresh configured database. The generated screenplay remains a candidate until an explicit reviewed acceptance.

## Import, inspect and export

```bash
cd ~/p/g/n/fount/packages/fount
mix fount.import priv/fixtures/last_light.fountain --key last-light-review --format fountain
mix fount.inspect --key last-light-review --json
mix fount.history --key last-light-review --json
mix fount.export --key last-light-review --format json --output /tmp/fount-review/canonical.json
mix fount.export --key last-light-review --format fountain --output /tmp/fount-review/source.fountain
mix fount.export --key last-light-review --format fdx --output /tmp/fount-review/interchange.fdx
```

Use the returned real UUIDs; do not substitute display scene numbers as identities. Canonical JSON is the identity-preserving application interchange. FDX and Fountain carry their declared fidelity limitations.

## Construct a pass request from the actual stored revision

This command writes only a request artifact using the stored accepted head. It does not call a provider or accept an edit.

```bash
cd ~/p/g/n/fount/packages/fount_workshop
mix run -e '
  {:ok, repo} = Fount.CLI.Support.connect()
  {:ok, model} = Fount.Persistence.load(repo, "last-light-review")
  request = %{
    "version" => 1, "workflow" => "pass", "mode" => "revise",
    "base_revision_id" => model.revision.id,
    "instruction" => "Make the action more visibly playable. Preserve intentions and specific physical business.",
    "selection" => %{"whole_screenplay" => true}, "constraints" => [],
    "alternatives" => 1, "options" => %{"profile" => "action_visual"}
  }
  File.write!("/tmp/fount-pass-request.json", Jason.encode!(request, pretty: true))
'
mix fount.write --key last-light-review --request /tmp/fount-pass-request.json --output /tmp/fount-review/pass --pdf
```

`--new` on `fount.write` creates an empty stored screenplay before development. Use a development request with a null/unset initial `base_revision_id` accepted by the CLI's new-root preparation, a whole-screenplay selection and an explicit placement such as `{"kind":"start"}`. The library `Session.start` itself always requires an actual base revision.

Workflow names are `develop`, `alternatives`, `propagate`, `sequence`, `character`, `notes`, `pass`, `recover`, `investigate`. Modes and payloads follow the retained original workflow contract plus `FountWorkshop.Request`. Pass names are `dialogue_subtext`, `action_visual`, `brevity`, `dry_comedy`, `tension`, `custom`; custom requires explicit direction. `character` requires a confirmed cast ID and direction. `sequence` requires an actual target scene count. `recover` requires a historical revision, typed source targets, destination and an explicit adaptation choice. Exploration/diagnosis can save strategies without claiming new pages.

## Saved sessions and selective writer control

Set the following shell variables to actual IDs from the generated review packet, not these labels:

```bash
mix fount.session --id "$SESSION_ID" --output /tmp/fount-review/reopened
mix fount.session --id "$SESSION_ID" --resume --output /tmp/fount-review/resumed
mix fount.materialize --session "$SESSION_ID" --strategies "$STRATEGY_A,$STRATEGY_B" --output /tmp/fount-review/materialized
mix fount.select --candidate "$CANDIDATE_ID" --groups "$GROUP_A,$GROUP_B" --output /tmp/fount-review/selected
mix fount.audition --candidate "$CANDIDATE_ID" --output /tmp/fount-review/audition --pdf
```

A combination JSON request contains `candidate_ids` and `selection`. `selection.picks` has entries with a `candidate_id` plus `group_ids`, or `ranges` entries with typed `source` and `target` element references and optional exact byte spans. Overlapping selections return explicit group conflict identities; `selection.choose` names a winner for each conflicting pair. `selection.join` can supply an instruction and editable selection to generate real connective writing while pinning the writer-selected passages. The new `alternatives` live mode writes a concrete `combination-request.json` containing real IDs as an example.

```bash
mix fount.combine --request /tmp/fount-combination.json --output /tmp/fount-review/combined --pdf
mix fount.rebase --candidate "$CANDIDATE_ID" --request /tmp/fount-rebase.json --output /tmp/fount-review/rebased
```

A rebase request names `current_revision_id` and explicit `choices` keyed by conflict group ID (`current` or `candidate`). `generate: true` requires a complete new `request`; this is a new authored writing decision, not silent replay. Generation does not grant permission to ignore current facts or constraints.

## Review and accept explicitly

Open the candidate Fountain pages first, then `review.md`, each candidate's review JSON, exact source diffs, notes, constraints and actual PDF pages. The exported `.decision.json` has a blank actor and no automatic overrides. Fill it only after review. A required semantic uncertainty/failed interpretation needs a reasoned writer override when permitted; structural invalidity and required deterministic failures are not overridden.

```bash
mix fount.accept --candidate "$CANDIDATE_ID" --expected-revision "$BASE_REVISION_ID" \
  --actor writer --review /tmp/fount-reviewed-decision.json
mix fount.reject --candidate "$OTHER_CANDIDATE_ID" --actor writer
mix fount.render --key last-light-review --output /tmp/fount-review/accepted.pdf
mix fount.read --key last-light-review --output /tmp/fount-review/table-read
```

A stale accepted head requires explicit rebase and fresh review. A repeat of the identical stored acceptance is idempotent; a changed review identity is not. Rejected candidates remain historical material.

## Probe commands

```bash
cd ~/p/g/n/fount/packages/fount_probe
mix fount.search --key last-light-review --query 'brass key' --history --output /tmp/fount-review/search
mix fount.probe --key last-light-review --request /tmp/fount-probe-requests.json --output /tmp/fount-review/probe
```

Probe requests are an array of `{id, tool, params}` records. `FountProbe.tools/0` provides closed schemas. Example inventory request: `[{"id":"scene-inventory","tool":"inventory","params":{"selection":{"whole_screenplay":true}}}]`. For exact history/lift comparisons provide real revision IDs. For knowledge provide legal prefix points and explicit subjects, not an inferred scene-attendance list. A partial report is not a clean result.

## Real-only example matrix

Run from the owning package with `MIX_ENV=dev mix run examples/live.exs -- --mode MODE --out DIRECTORY`. Exactly one such entrypoint exists per package. Start with the cheap/file-only cases; new writer modes require actual PostgreSQL/Codex/Jev and requested PDF tools. The new Workshop harness caps its shared work at 40 Inference calls and 1,500 Jev states, with 100,000-byte context limits; these are caps, not promised consumption or cost. Oversized/unfinished work remains partial.

Set `FOUNT_CODEX_MODEL` to a model available through the configured Codex provider. `FOUNT_CODEX_REASONING_EFFORT` optionally selects `none`, `low`, `medium`, `high`, `xhigh`, or `max` for the shared Probe/Workshop launcher; omitting it uses the model default. For the current low-cost local check, `gpt-5.6-luna` with `low` was confirmed by the local SDK and a read-only Codex probe. Keep provider credentials in the local secret wrapper.

Proposal generation sends a compact JSON guide and validates every response against the full local canonical contract. A provider response can require up to two JSON repair calls; a failed branch remains resumable while successful candidates stay saved. Apply all Fount migrations before live sessions, including the session-status migration, then inspect `session.json` and the review packet rather than assuming a returned model response means a valid candidate.

| Package | Retained modes | New modes |
| --- | --- | --- |
| Core | `roundtrip`, `database` | `interchange` |
| Probe | `knowledge` (old preliminary view) | `tools`, `voice`, `knowledge_access`, `consequences` |
| Workshop | `develop`, `rewrite`, `sequence`, `notes`, `pass`, `character`, `recover`, `table` and any existing PDF/speech cases in the entrypoint | `bridge`, `alternatives`, `propagate`, `sequence_routes`, `character_workspace`, `grouped_notes`, `pass_all`, `recover_scene`, `investigate` |

Do not call old preliminary knowledge output a full access ledger. New modes write actual run artifacts and hashes, candidate/session IDs, reports and available outputs. Their real service failure terminates the example rather than silently substituting a mock. Some ordinary tool insufficiency remains a partial report; inspect it rather than equating process success with complete acceptance.

`--accept-demo` is optional for the new Workshop fixture modes and applies only to a project freshly created by that mode. Do not use it on an existing writer project. It does not invent overrides for unresolved required checks. For normal work use the separate review/accept commands.
