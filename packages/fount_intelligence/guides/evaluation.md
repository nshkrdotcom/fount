# Calibration, evaluation, robustness, and corpus policy

Phase 11 adds a provider-neutral evaluation layer around the existing screenplay analysis system. It does **not** turn subjective craft into one quality score, choose a preferred rewrite, or claim human validation that has not occurred.

## What is evaluated separately

Keep these surfaces distinct:

1. **measurement support/validity** — whether an Observe distribution supports the intended current construct;
2. **output-contract integrity** — whether a frozen fixture still matches the exact current `Fount.Observe.OutputContract` digest;
3. **StoryWorld / Reader reasoning** — provider-free reasoning over frozen current-contract MeasurementResults and Observations;
4. **diagnosis/capability regressions** — screenplay-specific benchmark suites, including non-linear presentation/story-time cases;
5. **writer usefulness** — a separate optional human study, never inferred from support metrics.

`Fount.Intelligence.Evaluation` is the public convenience surface. Its components remain inspectable under `Fount.Intelligence.Evaluation.*`.

## Rights and provider-export policy

Every real evaluation item should carry a `CorpusManifest`. The manifest records the rights basis/evidence, intended uses, retention/confidentiality, and six explicit permissions:

- local storage;
- human review;
- hosted Observe;
- hosted Inference;
- local/on-prem model processing;
- redistribution.

`provider_export_allowed` is an aggregate upper bound; hosted Observe and hosted Inference are still independently enabled or denied. Public availability is never treated as permission. Credential-like keys are rejected from manifests.

```elixir
{:ok, manifest} = Fount.Intelligence.validate_evaluation_corpus(manifest_data)
:ok = Fount.Intelligence.authorize_evaluation_corpus(manifest_data, :human_review)
```

The shipped corpus fixture is synthetic and redistributable, but hosted-provider export is deliberately disabled. It is a contract/regression example, not evidence about real readers or scripts.

## Human annotations and disagreement

`Evaluation.Annotation` stores each annotator response independently at a semantic level (`label`, `ordinal`, `value`, text or selections). Human labels must not embed provider/model/logit/token/output-contract encodings. Reader checkpoints require a canonical presentation index and `first_exposure: true`.

Summaries preserve the original annotations and add an empirical label distribution when labels are present. A 50/50 split stays 50/50; it is not adjudicated into a fake gold answer.

## Metrics and abstention

`Evaluation.Metrics.evaluate/3` supports:

- `noul` / `choice`: multiclass Brier score, distributional log loss, calibration buckets/ECE, and coverage-versus-human-support abstention curves;
- `score`: the same distributional metrics plus ordinal MAE/RMSE against the mean human ordinal response.

The input keeps raw probability distributions. Thresholds are explicit inputs rather than universal constants. AUROC/AUPRC are intentionally not synthesized without a benchmark where they are justified.

## Frozen current-contract reasoning fixtures

`Evaluation.Benchmark.freeze/6` binds:

- current question specification;
- exact current output-contract logical ID and digest;
- immutable MeasurementResult;
- current Observation/evidence/provenance;
- explicit expected provider-free reasoning;
- regression tags and evidence level.

`Benchmark.validate/2` compares the saved contract with `Question.output_contract/1`. If the contract shape changes, the fixture fails with `stale_output_contract_fixture`, `regeneration_required: true`, and `compatibility_decode: false`.

There is no old-contract decoder. Regeneration is explicit:

1. rerun the **current** measurement question;
2. materialize a new current-revision Observation;
3. rerun/review the provider-free reasoning benchmark;
4. call `Benchmark.freeze/6` and deliberately replace the old fixture.

`Benchmark.regeneration_plan/2` reports the old/new digest and those steps without mutating a fixture.

## Capability coverage and non-linear time

`Evaluation.Suite.catalog/0` maps all twelve installed screenplay capability families to registered Observe lenses and required benchmark classes. Audience/Reader, Sequence, Setup/Payoff, and Revision Intelligence explicitly require a non-linear presentation/story-time benchmark.

The shipped `nonlinear_story_time.synthetic.json` plus the Phase-11 regression test keeps these invariants executable:

- Reader reduces forward in screenplay presentation order;
- a later-presented flashback does not inherit future diegetic state;
- unknown story-time relations remain unknown without evidence;
- causality is not inferred merely from presentation order.

## Drift and robustness

`Evaluation.Drift.compare/2` aligns cases by stable case ID and reports distribution L1 movement, selection changes, unmatched cases, and provider/model/lens/projection/output-contract identity changes. Its result is explicitly descriptive drift, not a model/provider ranking.

Run robustness suites across the dimensions justified by the construct: provider/model identity, lens wording, output-contract digest, projection/context, whitespace/no-op perturbations, neighboring scene context, batch order/concurrency, timeout/partial/error paths and hard resource caps. Missing provider results remain failures/unavailable data, never negative semantic evidence.

## Longitudinal resource calibration

`Evaluation.Resources` compares preflight estimates with actual resource units. Unknown hosted cost, reuse, token/unit or runtime values remain `nil`; they are never turned into zero. `compare_writer_packet/1` understands the existing WriterPacket resource shape and `summarize_history/1` can consume Phase-10 durable usage rows to preserve raw history plus estimate-versus-actual comparisons.

This measures the estimator; it does not promise future dollar cost when provider rates/throughput are unavailable.

## Executable fixtures and examples

Shipped package assets live under `priv/evaluation/`:

- `corpus_manifest.synthetic.json`;
- `reader_annotations.synthetic.json`;
- `frozen_concealment_fixture.json`;
- `nonlinear_story_time.synthetic.json`;
- `phase_eleven_suite.json`.

Run the provider-free smoke example:

```bash
mix run examples/phase_eleven.exs
```

Run live checks only when explicitly authorized:

```bash
# Synthetic Observe request, three uncached executions for drift inspection.
FOUNT_PHASE11_OBSERVE_LIVE=1 mix run examples/phase_eleven_live.exs

# From fount_workshop: one scene, one generated candidate, no acceptance and no Observe call.
FOUNT_PHASE11_WORKSHOP_LIVE=1 mix run examples/phase_eleven_live.exs
```

The Observe script uses the existing `Fount.Observe.provider/1` and `SceneQuestion.ask/5` path. Workshop uses the existing `Inference.Client.agent_session!` -> `Inference.Adapters.ASM` boundary through `FountWorkshop.Launcher`; Intelligence never calls SystemOneSDK, Inference or ASM directly.

## Evidence claims

The included corpus, annotations, metrics inputs and frozen observations are synthetic regression assets. No Phase-11 human study has been performed by merely shipping them. If a real study is later run, record its corpus rights, protocol, per-reader responses, disagreements, exclusions, and actual findings separately.
