defmodule Fount.Intelligence.PhaseElevenEvaluationTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Evaluation
  alias Fount.Intelligence.Evaluation.Benchmark
  alias Fount.Observe.Question

  defp fixture(name) do
    :fount_intelligence
    |> Application.app_dir("priv/evaluation/#{name}")
    |> File.read!()
    |> Jason.decode!()
  end

  test "corpus rights are explicit per use and hosted export fails closed" do
    manifest = fixture("corpus_manifest.synthetic.json")

    assert {:ok, validated} = Evaluation.validate_corpus_manifest(manifest)
    assert is_binary(validated["manifest_sha256"])
    assert :ok = Evaluation.authorize_corpus_use(manifest, :local_storage)
    assert :ok = Evaluation.authorize_corpus_use(manifest, :human_review)
    assert :ok = Evaluation.authorize_corpus_use(manifest, :local_model)
    assert :ok = Evaluation.authorize_corpus_use(manifest, :redistribution)
    assert {:error, :corpus_use_not_permitted} =
             Evaluation.authorize_corpus_use(manifest, :observe_hosted)

    leaked = put_in(manifest, ["permissions", "api_key"], true)
    assert {:error, :invalid_corpus_manifest} = Evaluation.validate_corpus_manifest(leaked)
  end

  test "independent reader disagreement is retained rather than adjudicated" do
    annotations = fixture("reader_annotations.synthetic.json")
    assert {:ok, [summary]} = Evaluation.summarize_annotations(annotations)

    assert summary["reader_count"] == 2
    assert summary["agreement"] == 0.5
    assert summary["label_distribution"] == %{"archive" => 0.5, "unknown" => 0.5}
    assert length(summary["annotations"]) == 2
    assert Enum.all?(summary["annotations"], &(get_in(&1, ["checkpoint", "first_exposure"]) == true))

    provider_coupled = put_in(hd(annotations), ["response", "provider_probability"], 0.9)
    assert {:error, :invalid_human_annotation} =
             Fount.Intelligence.Evaluation.Annotation.validate(provider_coupled)
  end

  test "categorical metrics include calibration and abstention without collapsing disagreement" do
    cases = [
      %{
        "case_id" => "a",
        "distribution" => %{"yes" => 0.8, "no" => 0.2},
        "human_labels" => ["yes", "yes", "no"]
      },
      %{
        "case_id" => "b",
        "distribution" => %{"yes" => 0.45, "no" => 0.55},
        "human_labels" => ["yes", "no"]
      }
    ]

    assert {:ok, report} = Evaluation.evaluate_measurements(:choice, cases, bins: 5)
    assert report["case_count"] == 2
    assert is_number(report["brier_score"])
    assert is_number(report["log_loss"])
    assert is_number(report["expected_calibration_error"])
    assert report["human_disagreement_preserved"] == true
    assert Enum.any?(report["abstention"], &(&1["threshold"] == 0.8 and &1["retained"] == 1))
  end

  test "ordinal score evaluation reports ordinal error separately from distributional metrics" do
    cases = [
      %{
        "case_id" => "score-a",
        "distribution" => %{"0" => 0.1, "1" => 0.2, "2" => 0.7},
        "human_ordinals" => [1, 2, 2]
      }
    ]

    assert {:ok, report} = Evaluation.evaluate_measurements(:score, cases)
    assert report["kind"] == "score"
    assert report["ordinal_cases"] == 1
    assert is_number(report["ordinal_mean_absolute_error"])
    assert is_number(report["ordinal_root_mean_square_error"])
  end

  test "drift is descriptive and keeps provider/model identity changes explicit" do
    baseline = [
      %{
        "case_id" => "same-case",
        "distribution" => %{"a" => 0.7, "b" => 0.3},
        "identity" => %{"provider" => "system_one", "model" => "jev-a"}
      }
    ]

    current = [
      %{
        "case_id" => "same-case",
        "distribution" => %{"a" => 0.4, "b" => 0.6},
        "identity" => %{"provider" => "system_one", "model" => "jev-b"}
      }
    ]

    assert {:ok, report} = Evaluation.compare_drift(baseline, current)
    assert report["changed_selection_count"] == 1
    case_result = hd(report["cases"])
    assert get_in(case_result, ["identity_changes", "model"]) ==
             %{"before" => "jev-a", "after" => "jev-b"}
    assert report["interpretation"] == "descriptive_drift_only_not_quality_ranking"
  end

  test "frozen observation fixture pins the current contract and stale contracts require regeneration" do
    fixture = fixture("frozen_concealment_fixture.json")
    question = Question.noul("Does Mara conceal the key from Dan?")

    assert :ok = Evaluation.validate_benchmark(fixture, question)

    changed =
      Question.choice("What is Mara doing?",
        concealing: "Hiding her discovery",
        sharing: "Sharing her discovery"
      )

    assert {:error, stale} = Evaluation.validate_benchmark(fixture, changed)
    assert stale["reason"] == "stale_output_contract_fixture"
    assert stale["regeneration_required"] == true
    assert stale["compatibility_decode"] == false

    assert {:ok, plan} = Benchmark.regeneration_plan(fixture, changed)
    assert plan["status"] == "regeneration_required"
    assert plan["compatibility_decode"] == false
    assert length(plan["steps"]) == 4
  end

  test "all twelve capability families have installed-lens benchmark coverage" do
    assert :ok = Evaluation.validate_benchmark_catalog()
    catalog = Evaluation.benchmark_catalog()
    assert length(catalog) == 12
    assert Enum.map(catalog, & &1["capability_family"]) == Fount.Intelligence.capability_families()

    suite = fixture("phase_eleven_suite.json")
    assert {:ok, validated} = Evaluation.validate_evaluation_suite(suite)
    assert is_binary(validated["suite_sha256"])
    assert validated["support_validity"] == true
    assert validated["writer_usefulness"] == "separate_optional_study"
  end

  test "longitudinal resource calibration keeps unknown dimensions unknown" do
    estimate = %{
      "provider_requests_before_retries_estimate" => 10,
      "reuse_estimate" => 0.5,
      "hosted_cost" => nil
    }

    actual = %{
      "provider_requests" => 12,
      "cache_hits" => 6,
      "scheduled_states" => 12,
      "hosted_cost" => nil
    }

    assert {:ok, report} = Evaluation.compare_resource_estimate(estimate, actual)
    provider = Enum.find(report["dimensions"], &(&1["dimension"] == "provider_requests"))
    reuse = Enum.find(report["dimensions"], &(&1["dimension"] == "reuse"))
    cost = Enum.find(report["dimensions"], &(&1["dimension"] == "hosted_cost"))

    assert provider["absolute_error"] == 2
    assert reuse["absolute_error"] == 0.0
    assert cost["actual"] == nil
    assert cost["absolute_error"] == nil
  end
end
