alias Fount.Intelligence.Evaluation
alias Fount.Observe.Question

load = fn name ->
  :fount_intelligence
  |> Application.app_dir("priv/evaluation/#{name}")
  |> File.read!()
  |> Jason.decode!()
end

manifest = load.("corpus_manifest.synthetic.json")
annotations = load.("reader_annotations.synthetic.json")
fixture = load.("frozen_concealment_fixture.json")
suite = load.("phase_eleven_suite.json")
nonlinear = load.("nonlinear_story_time.synthetic.json")

{:ok, rights} = Evaluation.validate_corpus_manifest(manifest)
{:ok, reader_groups} = Evaluation.summarize_annotations(annotations)
:ok = Evaluation.validate_benchmark(fixture, Question.noul("Does Mara conceal the key from Dan?"))
{:ok, suite} = Evaluation.validate_evaluation_suite(suite)

{:ok, metrics} =
  Evaluation.evaluate_measurements(:choice, [
    %{
      "case_id" => "checkpoint-02",
      "distribution" => %{"archive" => 0.62, "unknown" => 0.38},
      "human_labels" => ["archive", "unknown"]
    }
  ])

{:ok, drift} =
  Evaluation.compare_drift(
    [%{"case_id" => "checkpoint-02", "distribution" => %{"archive" => 0.62, "unknown" => 0.38}}],
    [%{"case_id" => "checkpoint-02", "distribution" => %{"archive" => 0.55, "unknown" => 0.45}}]
  )

{:ok, resource_calibration} =
  Evaluation.compare_resource_estimate(
    %{
      "provider_requests_before_retries_estimate" => 4,
      "reuse_estimate" => nil,
      "hosted_cost" => nil
    },
    %{"provider_requests" => 4, "cache_hits" => 0, "scheduled_states" => 4, "hosted_cost" => nil}
  )

IO.puts(
  Jason.encode!(
    %{
      "corpus" => Fount.Intelligence.Evaluation.CorpusManifest.summary(manifest) |> elem(1),
      "rights_manifest_sha256" => rights["manifest_sha256"],
      "reader_groups" => reader_groups,
      "metrics" => metrics,
      "drift" => drift,
      "resource_calibration" => resource_calibration,
      "suite_sha256" => suite["suite_sha256"],
      "benchmark_catalog" => Evaluation.benchmark_catalog(),
      "nonlinear_fixture" => nonlinear,
      "fixture_status" => "current",
      "human_validation_claim" => false
    },
    pretty: true
  )
)
