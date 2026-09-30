defmodule FountWeb.Phase06AnalysisContractTest do
  use ExUnit.Case, async: true

  alias FountWeb.AnalysisDashboard

  test "A02 inspection projection has no generation/measurement/provider dispatch path" do
    source = File.read!(Path.expand("../../lib/fount_web/analysis_dashboard.ex", __DIR__))
    live = File.read!(Path.expand("../../lib/fount_web/live/analysis_live.ex", __DIR__))

    assert source =~ "Owner-scoped, read-only projection"
    assert source =~ "FountRun.progress"
    assert source =~ "analysis_runs"
    assert source =~ "analysis_observations"
    refute source =~ "FountWorkshop."
    refute source =~ "Fount.Observe."
    refute source =~ "Inference."
    refute source =~ "reserve_usage"
    refute source =~ "enqueue_step"
    refute live =~ "pushEvent"
  end

  test "A04 graph is functional, evidence-backed and bounded" do
    observation = %{
      "id" => "observation-1",
      "revision_id" => "revision-1",
      "evidence" => [
        %{
          "evidence_id" => "e1",
          "target" => %{"kind" => "scene", "id" => "scene-a", "revision_id" => "revision-1"}
        }
      ],
      "payload" => %{
        "result" => %{
          "value" => %{
            "story_world_records" => [
              %{
                "id" => "event-a",
                "record_type" => "event",
                "label" => "Door opens",
                "subjects" => ["NORA"],
                "evidence_ids" => ["e1"],
                "uncertainty" => "low"
              },
              %{
                "id" => "relation-a",
                "record_type" => "relation",
                "label" => "Recorded relation",
                "subjects" => ["NORA", "OWEN"],
                "evidence_ids" => ["e1"]
              }
            ]
          }
        }
      }
    }

    graph = AnalysisDashboard.graph_from_observations([observation], node_limit: 3, edge_limit: 2)
    assert graph.nodes != []
    assert graph.events |> hd() |> Map.fetch!(:label) == "Door opens"
    assert graph.truncated
    assert length(graph.nodes) <= 3
    assert length(graph.edges) <= 2
    assert graph.explanation =~ "causality is never inferred"
    assert AnalysisDashboard.graph_from_observations([]).nodes == []

    dense_records =
      for n <- 1..5 do
        %{
          "id" => "dense-#{n}",
          "record_type" => "event",
          "subjects" => Enum.map(1..30, &"subject-#{&1}")
        }
      end

    dense =
      put_in(observation, ["payload", "result", "value", "story_world_records"], dense_records)

    bounded = AnalysisDashboard.graph_from_observations([dense])
    assert length(bounded.nodes) == 35
    assert bounded.total_edges == 150
    assert length(bounded.edges) == 96
    assert bounded.truncated
    refute Enum.any?(bounded.edges, &(&1.kind == "recorded_causal_relation"))

    causal =
      put_in(observation, ["payload", "result", "value", "story_world_records"], [
        %{
          "id" => "cause",
          "record_type" => "causal_relation",
          "from" => "event-a",
          "to" => "event-b",
          "evidence_ids" => ["e1"]
        }
      ])

    assert [%{kind: "recorded_causal_relation", evidence_ids: ["e1"]}] =
             AnalysisDashboard.graph_from_observations([causal]).edges
  end

  test "A06 comparisons require aligned definitions, provider fingerprints, scope and evidence" do
    base = %{
      "id" => "left",
      "output_contract_id" => "writer-packet.v1",
      "output_contract_sha256" => String.duplicate("a", 64),
      "scope" => %{"scene_ids" => ["s1"]},
      "_provider_fingerprints" => [%{"provider" => "sandbox", "model" => "fixture"}],
      "result" => %{
        "provenance" => %{"measurement_spec_sha256" => String.duplicate("b", 64)},
        "evidence" => [
          %{
            "evidence_id" => "e1",
            "revision_id" => "revision-1",
            "target" => %{"kind" => "scene", "id" => "s1"},
            "excerpt_sha256" => String.duplicate("c", 64)
          }
        ],
        "coverage" => %{"observed" => 2, "possible" => 4}
      }
    }

    right = put_in(base, ["result", "coverage", "observed"], 3) |> Map.put("id", "right")
    assert %{state: :comparable, deltas: deltas} = AnalysisDashboard.compare_runs(base, right)
    assert Enum.any?(deltas, &(&1.path == "coverage.observed" and &1.delta == 1))

    incompatible = Map.put(right, "_provider_fingerprints", [%{"provider" => "other"}])

    assert %{state: :incomparable, reasons: reasons, deltas: []} =
             AnalysisDashboard.compare_runs(base, incompatible)

    assert Enum.any?(reasons, &String.contains?(&1, "provider/model fingerprint"))

    for missing <- [
          Map.delete(right, "scope"),
          Map.delete(right, "output_contract_sha256"),
          put_in(right, ["result", "provenance"], %{}),
          Map.put(right, "_provider_fingerprints", [%{}]),
          put_in(right, ["result", "evidence"], [%{}])
        ] do
      assert %{state: :incomparable, deltas: []} = AnalysisDashboard.compare_runs(base, missing)
    end

    for mismatch <- [
          Map.put(right, "scope", %{"scene_ids" => ["other"]}),
          Map.put(right, "output_contract_sha256", String.duplicate("d", 64)),
          put_in(
            right,
            ["result", "provenance", "measurement_spec_sha256"],
            String.duplicate("e", 64)
          ),
          put_in(right, ["result", "evidence"], [%{"evidence_id" => "different"}])
        ] do
      assert %{state: :incomparable, deltas: []} = AnalysisDashboard.compare_runs(base, mismatch)
    end
  end

  test "A01/A03/A07 UI preserves status, exact binding and stale-draft language" do
    live = File.read!(Path.expand("../../lib/fount_web/live/analysis_live.ex", __DIR__))
    review = File.read!(Path.expand("../../lib/fount_web/live/run_live.ex", __DIR__))
    editor = File.read!(Path.expand("../../lib/fount_web/live/editor_live.ex", __DIR__))
    views = File.read!(Path.expand("../../lib/fount_web/screenplay_views.ex", __DIR__))

    for state <- ~w(complete partial failed stale not_run), do: assert(live =~ state)
    assert review =~ "Exact evidence binding"
    assert review =~ "check_set_fingerprint"
    assert editor =~ "unsaved local draft is unanalyzed"
    assert views =~ "def token(%{kind: :evidence"
    assert views =~ "do: \"evidence:"
    assert views =~ "analysis_run_id"
  end
end
