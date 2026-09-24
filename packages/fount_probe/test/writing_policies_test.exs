defmodule FountProbe.WritingPoliciesTest do
  use ExUnit.Case, async: true
  alias FountProbe.Writing.{DecisionPolicy, Evidence, Executor}

  test "negative intent uses complement and missing values never become zero" do
    assert {:ok, %{"status" => "pass", "allowed_mass" => mass}} =
             DecisionPolicy.semantic_noul(0.1, false)
    assert_in_delta mass, 0.9, 0.000001
    assert {:error, :missing_or_invalid_probability} = DecisionPolicy.noul(nil)
    assert {:ok, %{"status" => "insufficient_evidence"}} =
             DecisionPolicy.noul(0.1, complete_context: false)
  end

  test "a reveal can retract and cross again" do
    curve = for {p, i} <- Enum.with_index([0.1, 0.9, 0.2, 0.95]),
      do: %{"point" => i, "probability" => p}
    assert {:ok, result} = DecisionPolicy.boundary(curve)
    assert result["first_crossing"] == 1
    assert result["crossings"] == [1, 3]
    assert result["drops"] == [2]
  end

  test "unordered responses are associated with their input indices" do
    requests = [%{"id" => "a"}, %{"id" => "b"}, %{"id" => "c"}]
    result = Executor.assemble(requests, [
      {:ok, %{batch_index: 2, value: "third"}},
      {:error, %{details: %{batch_index: 0}}},
      {:ok, %{batch_index: 1, value: "second"}}
    ])
    assert Enum.map(result["entries"], & &1["input_id"]) == ["a", "b", "c"]
    assert hd(result["entries"])["result"] == {:error, %{details: %{batch_index: 0}}}
    assert result["status"] == "partial"
  end

  test "score labels and empty allowed regions are not silently coerced" do
    assert {:ok, %{0 => 0.2, 1 => 0.8}} =
             DecisionPolicy.score_keys(%{"0" => 0.2, "1" => 0.8}, 2)
    assert {:error, :unknown_or_empty_allowed_region} =
             DecisionPolicy.semantic_distribution(%{"yes" => 1.0}, [], 0.9)
  end

  test "evidence must resolve to the exact source revision and excerpt" do
    entry = %{"evidence_id" => "ev_1", "screenplay_id" => "s", "revision_id" => "r",
      "target" => %{"kind" => "element", "id" => "e", "span" => [3, 5]}, "excerpt" => "é"}
    resolver = fn "s", "r", %{"id" => "e"} -> {:ok, "café"} end
    assert {:ok, registry} = Evidence.validate([entry], resolver)
    assert :ok = Evidence.citations(["ev_1"], registry)
    assert {:error, {:uninspected_citations, ["invented"]}} =
             Evidence.citations(["invented"], registry)
  end
end
