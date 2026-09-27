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

## A complete writer demonstration

After configuring a disposable PostgreSQL database and applying Fount's migrations:

```bash
mix run examples/phase_one.exs --out examples/_output/phase_one --decision reject
# Also render the candidate PDF after npm ci and installing Poppler:
mix run examples/phase_one.exs --out examples/_output/phase_one_pdf --decision accept --pdf
```

This creates two stored alternatives using Inference's explicit mock, rejects one, accepts the selected fixture draft, makes an exact targeted rewrite, measures a strategy contrast with Observe Sandbox, compares real revisions, and exports original/candidate/accepted Fountain, review JSON and an HTML table read. The final `--decision` accepts or rejects the rewrite. It uses real persistence and export code, not a fake acceptance implementation. Fixture selections are not evidence of a human preference or live model performance.

## Use actual APIs

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

Run `mix test` for package tests and `MIX_ENV=test mix test integration` for the explicit integration directory after preparing the database/PDF prerequisites. New Phase 1 code and tests were not run in the source-writing environment. Codex must execute, repair and record the full handoff checks before declaring completion.

## License

[MIT License](LICENSE) - Copyright (c) 2026 nshkrdotcom.
