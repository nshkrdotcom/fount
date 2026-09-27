# Intelligence integration

Phase 9 connects Workshop's writer-controlled page workflows to the existing Observe and Intelligence architecture without giving analysis authority over canon.

## What changes for a writer

A substantial revision session can now carry three separate layers all the way to review:

1. **Before pages:** a writer-facing Intelligence packet records the concern, source evidence, derived state, competing diagnoses, uncertainty, protected strengths and resource use.
2. **Writing choice:** generated dramatic strategies retain the pre-analysis packet and diagnosis IDs as lineage. Alternatives are still materialized as actual candidate pages, never selected automatically.
3. **After pages:** when an Observe provider is configured, Revision Intelligence compares the immutable base with each candidate and reports intended-effect evidence, protected-strength preservation, collateral risks, causal ripple, reader/diegetic distinctions and resource use.

The review packet exposes the pre-analysis writer packet, revision packet, strategy lineage, consequence proposals and resource metadata next to the exact Fountain source/structural diff. None of those fields can accept, reject or rank a candidate. The existing explicit review gate remains the only path that can advance canon.

## Provider-free preflight

Call preflight before starting an expensive workflow:

```elixir
{:ok, preflight} = FountWorkshop.preflight(model, request,
  max_inference_calls: 12,
  max_measurement_states: 500
)
```

Preflight validates the normal Workshop request and asks Intelligence for its existing provider-free capability-playbook estimate. It performs no provider dispatch and changes no screenplay content. Hosted price and cache reuse remain unknown unless a configured runtime reports them.

The same preflight is persisted in `session["provenance"]["phase9_preflight"]` when a session starts.

## Optional Observe provider, preserved generation

Workshop still requires only its existing store and `Inference.Client`. Add an Observe provider to enable Phase-9 analysis:

```elixir
services = %{
  store: store,
  inference: inference_client,
  observe: observe_provider
}

{:ok, session} = FountWorkshop.Workflows.alternatives(model, request, services)
```

If `:observe` is absent or analysis cannot run, Workshop records `writer_intelligence.status == "not_run"` and continues the existing writing workflow. It does not fabricate a diagnosis or fail otherwise-valid page generation.

## Notes: reaction is not cause is not treatment

The notes workflow now keeps the raw note, reported reaction, suggested cause and suggested treatment in separate fields. A free-text note is preserved as the reaction; a cause or treatment is only populated when the note explicitly supplies one. Intelligence may then test competing explanations against screenplay evidence. A note's proposed fix is never silently promoted to diagnosis or canon.

## Strategies and consequences

Each generated strategy keeps its creative fields plus an `intelligence_lineage` record pointing to the relevant pre-analysis packet and diagnosis IDs. Local validation rejects exact duplicate causal strategy signatures across premise, mechanism, changes and consequences. The model prompt still requires genuinely different causal routes rather than cosmetic rewrites.

For story-change propagation, the strategy's concrete consequence list travels into candidate provenance as `consequence_proposals`, while the post-analysis packet can add an evidence-backed `causal_ripple`. The candidate still has to express actual authorized repairs as typed change groups with dependencies.

## Candidate review packet

`FountWorkshop.Review.packet/2` retains its original fields and adds:

- `writer_packet` — pre-candidate writer-facing analysis;
- `revision_packet` — explicit base/candidate Revision Intelligence;
- `strategy_lineage` — diagnosis-to-strategy lineage;
- `note_triage` — separated note semantics when applicable;
- `consequence_proposals` and `causal_ripple`;
- `resource_usage` — actual pre/post analysis metadata reported by Intelligence.

Revision-derived checks are advisory. Required deterministic/semantic writer constraints continue to be enforced by the existing review gate; Phase 9 does not add an analysis-based auto-rejection or auto-acceptance rule.

## Investigate without writing pages

The existing `investigate` workflow and `mode: "diagnose"` / `mode: "explore"` materialization rules remain intact. The saved session now exposes its `writer_packet`, so a writer can inspect an evidence-backed diagnosis without generating candidate pages. Set `write_fixes: true` only when actual screenplay remedies are wanted.

## Selection, combination, audition and rebase

Writer selection/edit preserves the candidate's Intelligence lineage. Combining candidates records the source candidate lineages rather than pretending they share one diagnosis. Audition output reports the relevant writer/revision packet IDs and resource metadata. Deterministic rebase retains source lineage while generated rebase runs through a new Workshop session and therefore receives fresh Phase-9 preparation.

## Runtime verification

Phase 9 is the verified baseline for this delivery. The new Phase-10 durable-analysis changes were produced without an Elixir/Mix/PostgreSQL runtime, so their migration, ExUnit, integration, architecture, Dialyzer and preservation gates remain for Codex after the overlay is applied. Static source checks are not substitutes for those runtime results.

## Optional durable analysis and resume

Phase 10 can persist the analysis side of the same writer loop without changing the generation or acceptance path. Opt in per session with `durable_analysis: true`; optionally provide `analysis_privacy_namespace:` when the host needs a namespace stricter than the screenplay default. The setting is saved in the existing session limits so resume uses the same policy.

When enabled and the Workshop store exposes its Core Repo, Intelligence records analysis-run identity, current-revision Observations, immutable reusable MeasurementResults, writer packets, dependency rows, and actual resource usage. Rejected or unchosen candidates remain ordinary Workshop history; durable analysis does not resurrect them, select them, or promote them to canon. If durable analysis is disabled, the Phase-9 Store + Inference-only and optional-Observe paths behave as before.

Cache retention is independent of writer history. Hosts may evict reusable L2 measurement rows without deleting writer packets, analysis runs, observations, candidate lineage, or accepted/rejected decisions.
