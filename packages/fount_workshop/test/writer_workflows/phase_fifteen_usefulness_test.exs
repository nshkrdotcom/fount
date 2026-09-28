defmodule FountWorkshop.PhaseFifteenUsefulnessTest do
  use ExUnit.Case, async: true

  alias FountWorkshop.Usefulness

  test "A12 keeps helpful, unchanged-original and generic outcomes separate without a winner or screenplay score" do
    records = [
      record!(%{
        "task_id" => "scene-pass-1",
        "condition" => "human_only",
        "outcome" => "neutral",
        "kept_original" => true,
        "output_refs" => ["original.fountain"],
        "engineering" => %{"completed" => true, "elapsed_ms" => 420_000, "errors" => []},
        "preference" => "Kept the original because the manual pass already solved the note.",
        "friction" => [],
        "dimensions" => %{
          "task_completion" => "complete",
          "next_decision" => "keep original",
          "agency" => "writer chose without generated alternatives"
        }
      }),
      record!(%{
        "task_id" => "scene-pass-2",
        "condition" => "basic_llm",
        "outcome" => "negative",
        "kept_original" => true,
        "output_refs" => ["basic-llm.txt"],
        "engineering" => %{"completed" => true, "elapsed_ms" => 85_000, "errors" => []},
        "preference" => "Suggestions were generic; none were adopted.",
        "friction" => ["time spent rejecting generic rewrites"],
        "dimensions" => %{
          "task_completion" => "complete",
          "voice_retention" => "weak",
          "rejection_time_ms" => 51_000
        }
      }),
      record!(%{
        "task_id" => "scene-pass-3",
        "condition" => "fount_assisted",
        "outcome" => "positive",
        "kept_original" => false,
        "output_refs" => ["candidate.fountain", "comparison.json"],
        "engineering" => %{
          "completed" => true,
          "elapsed_ms" => 110_000,
          "errors" => [],
          "resource_usage" => %{"provider_requests" => 1}
        },
        "preference" => "One alternative exposed the consequence clearly enough to adopt.",
        "friction" => ["reviewed two rejected alternatives"],
        "dimensions" => %{
          "task_completion" => "complete",
          "next_decision" => "accept candidate",
          "agency" => "explicit writer acceptance",
          "alternative_diversity" => "useful contrast",
          "consequence_usefulness" => "helpful"
        }
      })
    ]

    assert {:ok, report} =
             Usefulness.report(records,
               evidence_status: "deterministic_fixture",
               human_study: "not_run"
             )

    assert report["human_study"] == "not_run"
    assert report["conditions_present"] == ["basic_llm", "fount_assisted", "human_only"]

    assert Enum.map(report["records"], & &1["human_response"]["outcome"]) == [
             "neutral",
             "negative",
             "positive"
           ]

    assert report["claims"]["aggregate_screenplay_score"] == false
    assert report["claims"]["automatic_winner"] == false
    assert report["claims"]["expert_endorsement"] == false
    assert report["claims"]["representative_sample"] == false
    refute Map.has_key?(report, "score")
    refute Map.has_key?(report, "winner")
  end

  defp record!(attrs) do
    assert {:ok, record} = Usefulness.record(attrs)
    record
  end
end
