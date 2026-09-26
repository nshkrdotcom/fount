# Source map and continuation decisions

## Canonical flow

`FountWorkshop.Session.start(model, request, services, opts)` validates the original base revision and a closed request. `Store.save_session` persists that immutable base/request with optimistic session versions. `Writing.Context` separates editable pages from adjacent read-only context and exact evidence. `Writing.Preparation` executes actual workflow-specific Probe inspections; its context, source revision IDs and results are cached for resume. `Strategy.generate` creates explicit dramatic routes. `Writing.Generation` obtains a full canonical proposal through `FountProbe.Completion`, validates JSON/contracts and compiles actual edits. `Candidate.check` performs deterministic and semantic constraints and optional real PDF comparison. Reports and candidate revisions are stored without moving the accepted head.

`Session.resume` reads the saved base and context. It does not silently retarget to the current accepted head, rerun all successful branches or regenerate strategy IDs. `Strategy.materialize` selects saved approaches to materialize. Partial inspections and exhausted call/state budgets remain visible.

`Candidate.select(id, group_ids, services, opts)` replays selected groups from the original base with their local-reference map and dependency selection. `Candidate.edit` appends explicit writer operations. `Candidate.combine(ids, selection, services, opts)` chooses groups or exact source/target element ranges, exposes overlap choices, namespaces local references and can write actual connective material around pinned selected passages. The intermediate combination source is persisted for evidence identity before generation of joins. `Candidate.rebase` produces an explicit new-base candidate/session or conflicts. None of these accepts writing.

`Review.export(session_id, directory, services, opts)` writes base/candidate Fountain pages, strategies, structural and source diffs, check reports, lineage, JSON/HTML table reads and blank decision forms. With `pdf: true`, renderer failure is a failed request with retained packet rather than a fake PDF. `Acceptance.accept(candidate_id, expected_revision, review, services)` delegates to the PostgreSQL transaction. The transaction validates actual stored data and writer review, serializes head advancement and preserves immutable candidate/history material.

## Services

```elixir
services = %{
  store: FountWorkshop.Store.new(Fount.Repo),
  inference: codex_inference_client,
  jev: system_one_client,
  renderer: FountWorkshop.Export.PDF
}
```

Clients are supplied by the application; environment access is confined to launchers. The optional `voices` service map is for audition/table reads. The application store is PostgreSQL. The test store under `support/` is an explicitly injected test seam, not a production fallback.

Provider boundaries use the supplied source APIs: `Inference.Client.agent_session!`, `Inference.capabilities`, `Inference.Request`/response formats and `Inference.generate`; public System One Noul/Choice/Score constructors and prepared stream execution. The existing `FountProbe.Writing.Executor` owns association with SDK results. No dependency internals are copied into Fount and no dependency repository is modified.

## Data and result conventions

Public request/proposal documents use string JSON keys. Screenplay values use the existing structs. Persisted row maps use database string keys; older convenience modules sometimes return atom-key maps. Normalize only at explicit boundaries through `Fount.Screenplay.Model.plain`, `Store` and codec helpers. Verify these shapes with actual runtime tests before simplifying APIs.

Evidence records carry screenplay/revision/typed target, exact excerpt and half-open UTF-8 byte spans. A projection may expose multiple visible fragments from an element containing hidden notes. Report persistence validates evidence and cited registry IDs against actual immutable source models. Missing answers are errors/unknown/partial, never zero probabilities or clean checks. Noul, categorical confidence/margin and Score distributions remain separate concepts.

`Candidate.provenance` retains the full proposal, one allocated-ID map, compiled operations, source evidence, constraints, reports and check results. Candidate identity includes its actual result revision/payload. Authored note resolution modifies candidate authored state only, not the accepted draft before acceptance.

## Important source-level corrections versus prior notes

* Existing legacy file/SQLite stores were already removed. Do not redo that removal because of an early stale FEATURES summary.
* Ecto schema/query definitions still lagged the new relational model; this continuation updates them rather than trusting the progress prose.
* Boolean decoding must preserve `false`, not replace it through truthy fallback.
* Stable revision IDs and replayed local references must not be regenerated during group selection.
* Core acceptance must validate stored structural/check data, not a caller's empty `structural_errors` array.
* Speaker-scene membership is not proof of access. New knowledge paths use exact-prefix access evidence; the older preliminary `Knowledge.trace` remains as a narrower legacy example, not the full acceptance implementation.
* Same actor/review/content acceptance is idempotent; a changed repeated decision conflicts.
* Profile SHA, effective question SHA and SDK Prepared fingerprint are distinct values.

## Definition locations

Core contracts remain `packages/fount/priv/writing_contracts/`; original target contracts remain under the archived original spec. New Core CLI helpers are `lib/fount/cli*`; migrations are `priv/repo/migrations/`.

Probe public dispatch is `lib/fount_probe.ex`, closed schemas are `catalog.ex`, tool modules are beside it, and actual question assets are `priv/profiles/*.json`. Shared provider behavior is `completion.ex`, `jev.ex`, `profile.ex`, `budget.ex` and the retained `writing/` helpers.

Workshop domain modules are `lib/fount_workshop/`. Generation/preparation/context/layout/footprints/recovery helpers are in its `writing/`. Mix tasks are under each owning package's `lib/mix/tasks/`. Read tests alongside every changed module, then KNOWN_GAPS before broadening a claim.


## Verification status

This continuation is source-only and has not been compiled or tested. The repository handoff at `docs/implementation_handoff/` maps all acceptance cases and explicit remaining gaps. Do not interpret these source APIs as a verified release.
