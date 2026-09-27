defmodule Fount.Intelligence.DiagnosisTest do
  use ExUnit.Case, async: true

  alias Fount.Intelligence.Diagnosis

  @evidence [
    %{
      "evidence_id" => "ev-1",
      "revision_id" => "rev-1",
      "target" => %{"kind" => "element", "id" => "e-1"},
      "excerpt" => "Mara changes the subject.",
      "role" => "input_context"
    }
  ]

  test "pure diagnosis returns an evidence need instead of acquiring or forcing a conclusion" do
    {:ok, result} =
      Diagnosis.evaluate(
        %{"statement" => "The exchange loses pressure."},
        [%{"id" => "h1", "hypothesis" => "The tactic stops changing.", "evidence_ids" => ["ev-1"]}],
        @evidence
      )

    assert result.diagnoses == []
    assert [%{measurement: "diagnosis.evidence_support", hypothesis_id: "h1"}] = result.missing_evidence
    assert [%{"reason" => "needs_measurement"}] = result.abstentions
  end

  test "competing supported diagnoses coexist and counterevidence remains visible" do
    hypotheses = [
      %{
        "id" => "h1",
        "code" => "repeated_tactic",
        "hypothesis" => "The tactic stops changing.",
        "evidence_ids" => ["ev-1"],
        "alternatives" => ["The stillness may be intentional entrapment."],
        "assessment" => %{
          "support" => %{"status" => "supported", "probability" => 0.92},
          "counterevidence" => %{"status" => "not_supported", "probability" => 0.08},
          "observation_ids" => ["obs-1", "obs-2"]
        }
      },
      %{
        "id" => "h2",
        "code" => "information_without_leverage",
        "hypothesis" => "Information accumulates without changing leverage.",
        "evidence_ids" => ["ev-1"],
        "assessment" => %{
          "support" => %{"status" => "supported", "probability" => 0.87},
          "counterevidence" => %{"status" => "supported", "probability" => 0.81},
          "observation_ids" => ["obs-3", "obs-4"]
        }
      }
    ]

    {:ok, result} = Diagnosis.evaluate("The exchange loses pressure.", hypotheses, @evidence)
    assert Enum.map(result.diagnoses, & &1["code"]) == ["repeated_tactic", "information_without_leverage"]
    assert Enum.at(result.diagnoses, 1)["uncertainty"] == "high"
    assert length(Enum.at(result.diagnoses, 1)["counterevidence"]) == 1
    refute Enum.any?(result.diagnoses, &Map.has_key?(&1, "severity"))
    refute Enum.any?(result.diagnoses, &Map.has_key?(&1, "quality_score"))
  end

  test "uncertain support abstains rather than becoming a diagnosis" do
    hypothesis = %{
      "id" => "h1",
      "hypothesis" => "The tactic stops changing.",
      "evidence_ids" => ["ev-1"],
      "assessment" => %{
        "support" => %{"status" => "uncertain", "probability" => 0.55},
        "counterevidence" => %{"status" => "uncertain", "probability" => 0.45}
      }
    }

    {:ok, result} = Diagnosis.evaluate("The exchange loses pressure.", [hypothesis], @evidence)
    assert result.diagnoses == []
    assert [%{"reason" => "uncertain_support", "assessment" => assessment}] = result.abstentions
    assert assessment["support"]["status"] == "uncertain"
    assert result.next_investigations != []
  end

  test "counterevidence-dominant abstention preserves evidence and alternatives" do
    hypothesis = %{
      "id" => "h1",
      "hypothesis" => "The tactic stops changing.",
      "evidence_ids" => ["ev-1"],
      "alternatives" => ["The stillness is deliberate entrapment."],
      "assessment" => %{
        "support" => %{"status" => "not_supported", "probability" => 0.1},
        "counterevidence" => %{"status" => "supported", "probability" => 0.9}
      }
    }

    {:ok, result} = Diagnosis.evaluate("The exchange loses pressure.", [hypothesis], @evidence)
    assert result.diagnoses == []
    assert [%{"reason" => "counterevidence_dominates"} = abstention] = result.abstentions
    assert length(abstention["counterevidence"]) == 1
    assert abstention["alternatives"] == ["The stillness is deliberate entrapment."]
  end
end
