defmodule FountRun.Phase02DurableAnalysisContractTest do
  use ExUnit.Case, async: true

  alias FountRun.AnalysisLineage

  test "D04 projects stable analysis identifiers without semantic payload copies" do
    writer = %{
      "id" => "writer-packet-a",
      "status" => "partial",
      "playbook" => "scene_engine",
      "source_revision" => "revision-a",
      "finding" => "private semantic payload",
      "evidence" => [%{"secret" => "not copied"}],
      "resource_usage" => %{
        "capability_runs" => [
          %{
            "actual" => %{
              "scheduled_states" => 3,
              "successful_states" => 2,
              "cache_hits" => 1,
              "provider_requests" => 3
            }
          }
        ]
      },
      "provenance" => %{"analysis_run_id" => "analysis-a", "private" => "not copied"}
    }

    revision = %{
      "id" => "writer-packet-b",
      "status" => "complete",
      "playbook" => "revision_regression",
      "source_revision" => "revision-b",
      "provenance" => %{"analysis_run_id" => "analysis-b"}
    }

    candidate = %{
      "id" => "candidate-a",
      "provenance" => %{
        "intelligence_lineage" => %{"pre_analysis_packet" => writer},
        "revision_intelligence" => revision
      }
    }

    summary = AnalysisLineage.from_candidate(candidate)

    assert summary["writer"] == %{
             "packet_id" => "writer-packet-a",
             "analysis_run_id" => "analysis-a",
             "status" => "partial",
             "playbook" => "scene_engine",
             "source_revision_id" => "revision-a",
             "resources" => %{
               "scheduled_states" => 3,
               "successful_states" => 2,
               "cache_hits" => 1,
               "provider_requests" => 3
             }
           }

    assert summary["revision"]["packet_id"] == "writer-packet-b"
    assert summary["revision"]["analysis_run_id"] == "analysis-b"
    refute Map.has_key?(summary["writer"], "finding")
    refute Map.has_key?(summary["writer"], "evidence")
    refute Map.has_key?(summary["writer"], "provenance")
  end

  test "D04 progress connects Run stage identity to safe writer and revision analysis IDs" do
    steps = [
      %{
        "id" => "step-a",
        "stage" => "write",
        "iteration" => 0,
        "session_id" => "session-a",
        "output_candidate_id" => "candidate-a",
        "output_revision_id" => "revision-a",
        "result" => %{
          "session_id" => "session-a",
          "candidate_id" => "candidate-a",
          "revision_id" => "revision-a",
          "analysis" => %{
            "writer" => %{"packet_id" => "packet-a", "analysis_run_id" => "analysis-a"},
            "revision" => %{"packet_id" => "packet-b", "analysis_run_id" => "analysis-b"}
          }
        }
      },
      %{"id" => "step-b", "stage" => "decide", "iteration" => 0, "result" => %{}}
    ]

    assert [summary] = AnalysisLineage.progress(steps)
    assert summary["step_id"] == "step-a"
    assert summary["session_id"] == "session-a"
    assert summary["candidate_id"] == "candidate-a"
    assert summary["revision_id"] == "revision-a"
    assert summary["writer"]["analysis_run_id"] == "analysis-a"
    assert summary["revision"]["analysis_run_id"] == "analysis-b"
  end
end
