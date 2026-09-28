<p align="center">
  <img src="assets/fount_workshop.svg" alt="Fount Workshop" width="200" height="200"/>
</p>

<p align="center">
  <a href="https://hex.pm/packages/fount_workshop"><img src="https://img.shields.io/hexpm/v/fount_workshop.svg" alt="Hex.pm"/></a>
  <a href="https://hexdocs.pm/fount_workshop"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="HexDocs"/></a>
  <a href="https://github.com/nshkrdotcom/fount"><img src="https://img.shields.io/badge/GitHub-repo-black?logo=github" alt="GitHub"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"/></a>
</p>

# Fount Workshop

**Write alternate pages, compare them to your draft, and decide what becomes canon.**

Workshop develops a draft from a brief, continues or bridges scenes, creates competing approaches, combines selected material, rebuilds sequences, rewrites a character, coordinates notes, runs creative passes and recovers earlier writing. The resulting pages remain reviewable candidates until an explicit writer decision advances the accepted revision.

Use Intelligence to investigate a concern and inspect consequences. Use Workshop to generate actual screenplay material, save alternatives, review exact differences, hear dialogue and render pages. A probability is not permission to change the script.

Phase 9 now carries that separation through the actual writing loop: provider-free preflight, pre-write writer packets, diagnosis-to-strategy lineage, optional post-candidate Revision Intelligence, protected-strength/collateral review metadata, and actual analysis resource use can travel with a candidate without changing the explicit acceptance model. See [`guides/intelligence-integration.md`](guides/intelligence-integration.md).

Phase 10 adds an opt-in durable analysis layer for session resume and audit: reusable semantic measurements can survive draft revisions while current evidence/provenance is rematerialized for the active revision. Cache eviction remains separate from candidate/history retention, and writer acceptance is unchanged.

Phase 11 adds a deliberately small live-generation QC lane: `FOUNT_PHASE11_WORKSHOP_LIVE=1 mix run examples/phase_eleven_live.exs` generates exactly one candidate for one scene, disables Observe for that run, exports the normal review packet, and never accepts the candidate. Evaluation/metrics remain in Intelligence.

Phase 12 adds writer-first discovery without creating another screenplay representation: provider-free `Session.open/4`, explicit Draft/Explore/Inspect/Revise modes, evolving briefs and fragments, reverse outlines/card proposals, manual writer candidates, and treatment-bound scene alternatives. Canon still moves only through explicit acceptance. See [`guides/discovery-and-scene-exploration.md`](guides/discovery-and-scene-exploration.md) and [`examples/phase_twelve/README.md`](examples/phase_twelve/README.md).

Phase 13 adds cinematic pass lenses for sound/space, playable stillness/rhythm and transitions; writer-selected source voice exemplars and deterministic exact-text protection; explicitly noncanonical rehearsal exercises with traceable adoption; and actual candidate-page comparison that separates changed action/language from generator self-description. See [`guides/cinematic-revision-rehearsal-and-voice.md`](guides/cinematic-revision-rehearsal-and-voice.md) and [`examples/phase_thirteen/README.md`](examples/phase_thirteen/README.md).

Phase 14 adds provenance-safe research dossiers, durable note triage that keeps concern separate from treatment, exact/ambiguous/orphaned anchor tracking across drafts, and consequence review tied to actual candidate page changes. Research and note records stay noncanonical until the writer chooses a normal candidate and explicitly accepts it. See [`guides/research-notes-and-consequences.md`](guides/research-notes-and-consequences.md) and [`examples/phase_fourteen/README.md`](examples/phase_fourteen/README.md).

## A complete writer demonstration

After configuring a disposable PostgreSQL database and applying Fount's migrations:

```bash
mix run examples/phase_one.exs --out examples/_output/phase_one --decision reject
# Also render the candidate PDF after npm ci and installing Poppler:
mix run examples/phase_one.exs --out examples/_output/phase_one_pdf --decision accept --pdf
```

This creates two stored alternatives using Inference's explicit mock, rejects one, accepts the selected fixture draft, makes an exact targeted rewrite, measures a strategy contrast with Observe Sandbox, compares real revisions, and exports original/candidate/accepted Fountain, review JSON and an HTML table read. The final `--decision` accepts or rejects the rewrite. It uses real persistence and export code, not a fake acceptance implementation. Fixture selections are not evidence of a human preference or live model performance.

## Use actual APIs

For the integrated session workflow, preflight first when the caller wants resource visibility before provider work:

```elixir
{:ok, preflight} = FountWorkshop.preflight(model, request)
{:ok, session} = FountWorkshop.Session.start(model, request, services)
# Add services.observe to obtain pre/post Intelligence packets; omit it to preserve the generation-only lane.
```

The lower-level and original workflow APIs remain available:

```elixir
# repo is a running Fount.Repo with migrations applied; key identifies an existing project.
# client is a real Inference.Client chosen by the host.
{:ok, result} = FountWorkshop.TargetedRewrite.run(repo, key, [element_id],
  "Make the accusation indirect without changing the facts.", client)
{:ok, packet} = FountWorkshop.Review.packet(repo, result.candidate.id)

# Present packet["original_fountain"], packet["proposed_fountain"], and both diffs.
# Only after the writer reviews this exact content:
review = %{"candidate_id" => result.candidate.id, "content_hash" => packet["content_hash"],
  "actor" => writer_id, "report_ids" => packet["report_ids"], "overrides" => []}
{:ok, accepted} = FountWorkshop.Review.accept(repo, result.candidate.id,
  packet["base_revision_id"], review)
```

`Review.reject/3` preserves candidate material for history/recovery while leaving canon unchanged. Stale-base or mismatched-content acceptance fails; do not bypass it. These are the implemented functions, not a hypothetical context/propose/preview facade.

For a project starting from a brief, use `Develop.run/5` or the public `FountWorkshop.develop/5`. Existing candidate, session, rebase, audition, pass, notes, sequence, character and recovery APIs remain available; their guides and tests travel with this phase.

## Inspect, rehearse and export

`Services.analysis/1` composes a host-owned Inference completion callback, Observe handle and measured-PDF-layout callback for Intelligence. `mix fount.analyze` runs closed JSON inspection requests; `mix fount.search` retains exact search. No data-selected executable module is accepted.

`TableRead.export(model, path, :html)` and `:json` need no speech provider. `TableRead.render_audio/4` produces real per-turn audio when the configured speech tool is present; it does not infer engagement or actor approval. `Export.PDF.export/3` uses the pinned renderer and reports actual inspection results. Dated submission checks are mechanical aids, not a guarantee of current venue rules or eligibility.

## Setup and checks

Run `npm ci` in this package for the existing renderer; PDF inspection requires Poppler. Database workflows require `FOUNT_DATABASE_URL` and Fount's migrations. For the newly inspected SDK source, set `FOUNT_SYSTEM_ONE_SDK_PATH` before resolving dependencies; details are in Observe's guide.

Run `mix test` for package tests and `MIX_ENV=test mix test integration` for the explicit integration directory after preparing the database/PDF prerequisites. Phase 13 is the applied/runtime-verified baseline in this snapshot. Phase 14 source changes require Codex runtime repair/QC before the phase can be marked complete; this source-writing handoff does not claim Mix/PostgreSQL/provider or human-study execution.

## License

[MIT License](LICENSE) - Copyright (c) 2026 nshkrdotcom.