defmodule Fount.Intelligence.WritingPoliciesTest do
  use ExUnit.Case, async: true
  alias Fount.Intelligence.Capabilities.DecisionPolicy
  alias Fount.Intelligence.Reader.Reveal
  alias Fount.Observe.Association, as: Association
  alias Fount.Observe.Error
  alias Fount.Observe.Request
  alias Fount.SourceEvidence, as: Evidence

  test "negative intent uses complement and missing values never become zero" do
    assert {:ok, %{"status" => "pass", "allowed_mass" => mass}} =
             DecisionPolicy.semantic_noul(0.1, false)

    assert_in_delta mass, 0.9, 0.000001
    assert {:error, :missing_or_invalid_probability} = DecisionPolicy.noul(nil)

    assert {:ok, %{"status" => "insufficient_evidence"}} =
             DecisionPolicy.noul(0.1, complete_context: false)
  end

  test "a reveal can retract and cross again" do
    curve =
      for {p, i} <- Enum.with_index([0.1, 0.9, 0.2, 0.95]),
          do: %{"point" => i, "probability" => p}

    assert {:ok, result} = Reveal.boundary(curve)
    assert result["first_crossing"] == 1
    assert result["crossings"] == [1, 3]
    assert result["drops"] == [2]
  end

  test "unordered responses are associated with their input indices" do
    model = Fount.Screenplay.new()

    requests =
      for id <- ["a", "b", "c"] do
        {:ok, request} = Request.new(model, id, %{"passage" => id})
        request
      end

    {entries, errors} =
      Association.assemble(requests, [
        %Fount.Observe.ProviderResult{batch_index: 2, answers: %{}},
        %Fount.Observe.ProviderResult{
          batch_index: 0,
          error: Error.new(:provider_timeout)
        },
        %Fount.Observe.ProviderResult{batch_index: 1, answers: %{}}
      ])

    assert Enum.map(entries, fn {request, _} -> request.id end) == ["a", "b", "c"]
    assert elem(hd(entries), 1).error.class == :provider_timeout
    assert [%Error{request_id: "a", class: :provider_timeout}] = errors
  end

  test "score labels and empty allowed regions are not silently coerced" do
    assert {:ok, %{0 => 0.2, 1 => 0.8}} =
             DecisionPolicy.score_keys(%{"0" => 0.2, "1" => 0.8}, 2)

    assert {:error, :unknown_or_empty_allowed_region} =
             DecisionPolicy.semantic_distribution(%{"yes" => 1.0}, [], 0.9)
  end

  test "evidence must resolve to the exact source revision and excerpt" do
    entry = %{
      "evidence_id" => "ev_1",
      "screenplay_id" => "s",
      "revision_id" => "r",
      "target" => %{"kind" => "element", "id" => "e", "span" => [3, 5]},
      "excerpt" => "é"
    }

    resolver = fn "s", "r", %{"id" => "e"} -> {:ok, "café"} end
    assert {:ok, registry} = Evidence.validate([entry], resolver)
    assert :ok = Evidence.citations(["ev_1"], registry)

    assert {:error, {:uninspected_citations, ["invented"]}} =
             Evidence.citations(["invented"], registry)
  end
end
