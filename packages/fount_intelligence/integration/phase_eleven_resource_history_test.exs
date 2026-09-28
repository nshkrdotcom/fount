defmodule Fount.Intelligence.PhaseElevenResourceHistoryIntegrationTest do
  use ExUnit.Case, async: false

  alias Fount.Intelligence.Evaluation
  alias Fount.Intelligence.Persistence, as: AnalysisStore
  alias Fount.Persistence.Analysis
  alias Fount.{ID, Repo, Screenplay}

  setup_all do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    start_supervised!({Repo, url: url, pool_size: 2})
    :ok
  end

  test "durable analysis history can calibrate preflight estimates against actual resource units" do
    screenplay = Screenplay.new()
    key = "phase11-resource-history-#{ID.v4()}"
    assert {:ok, _} = Fount.Persistence.create(Repo, key, screenplay)

    store = AnalysisStore.new(Repo, privacy_namespace: "phase11-resources:" <> ID.v4())
    assert {:ok, run} = AnalysisStore.begin(store, screenplay, "scene_doctor")

    resource_usage = %{
      "preflight" => %{
        "estimate" => %{
          "provider_requests_before_retries_estimate" => 4,
          "reuse_estimate" => 0.25,
          "hosted_cost" => nil
        }
      },
      "actual" => %{
        "base" => %{
          "actual" => %{
            "provider_requests" => 3,
            "cache_hits" => 1,
            "scheduled_states" => 4,
            "successful_states" => 4
          }
        },
        "contextual" => %{
          "actual" => %{
            "provider_requests" => 1,
            "cache_hits" => 0,
            "scheduled_states" => 0,
            "successful_states" => 0
          }
        },
        "analysis_budget" => %{"limit" => 10, "spent" => 4},
        "hosted_cost" => nil
      }
    }

    assert {:ok, _finished} =
             Analysis.finish_run(Repo, run.id, %{
               status: "complete",
               resource_usage: resource_usage,
               metadata: %{"changes_canon" => false}
             })

    history = AnalysisStore.usage_history(store, screenplay.id, "scene_doctor")
    assert [_ | _] = history
    assert {:ok, report} = Evaluation.summarize_resource_history(history)
    assert report["runs_with_estimate_actual_comparison"] >= 1

    [comparison | _] = report["estimate_actual_comparisons"]
    requests = Enum.find(comparison["dimensions"], &(&1["dimension"] == "provider_requests"))
    reuse = Enum.find(comparison["dimensions"], &(&1["dimension"] == "reuse"))

    assert requests["absolute_error"] == 0
    assert reuse["absolute_error"] == 0.0
    assert report["hosted_cost"] == nil
  end
end
