defmodule Fount.Intelligence.Evaluation do
  @moduledoc """
  Phase-11 evaluation surface: rights-cleared corpus policy, independent human labels,
  calibration/abstention metrics, drift, frozen current-contract benchmarks and
  longitudinal resource calibration.
  """

  alias Fount.Intelligence.Evaluation.{
    Annotation,
    Benchmark,
    CorpusManifest,
    Drift,
    Metrics,
    Resources,
    Suite
  }

  def validate_corpus_manifest(manifest), do: CorpusManifest.validate(manifest)
  def authorize_corpus_use(manifest, use_kind), do: CorpusManifest.authorize(manifest, use_kind)
  def summarize_annotations(annotations), do: Annotation.summarize_groups(annotations)
  def evaluate_measurements(kind, cases, opts \\ []), do: Metrics.evaluate(kind, cases, opts)
  def compare_drift(baseline, current), do: Drift.compare(baseline, current)

  def validate_benchmark(fixture, current_question),
    do: Benchmark.validate(fixture, current_question)

  def benchmark_regeneration_plan(fixture, current_question),
    do: Benchmark.regeneration_plan(fixture, current_question)

  def compare_resource_estimate(estimate, actual), do: Resources.compare(estimate, actual)
  def summarize_resource_history(history), do: Resources.summarize_history(history)
  def benchmark_catalog, do: Suite.catalog()
  def validate_benchmark_catalog, do: Suite.validate_catalog()
  def validate_evaluation_suite(suite), do: Suite.validate_suite(suite)
end
