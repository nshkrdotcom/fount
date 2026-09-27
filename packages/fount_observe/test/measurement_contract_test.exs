defmodule Fount.Observe.MeasurementContractTest do
  use ExUnit.Case, async: true
  alias Fount.Observe.{Context, Distribution, EvidenceRef, Question, Request, TargetRef}

  test "questions are provider-neutral and preserve declared option order" do
    q = Question.choice("Which tactic is present?", evade: "Evade", answer: "Answer")
    assert q.kind == :choice
    assert q.criteria == [{"evade", "Evade"}, {"answer", "Answer"}]
    assert {:ok, [{"tactic", ^q}]} = Question.validate_many(tactic: q)
    assert {:error, _} = Question.validate_many([{:a, q}, {"a", q}])
    refute Map.has_key?(Question.specification(q), "version")
  end

  test "proposition probability is not confidence and score is not rounded to a modal label" do
    assert {:ok, p} = Distribution.proposition(0.7)
    assert p.confidence == nil
    assert Distribution.to_map(p)["probability"] == 0.7
    assert {:ok, score} = Distribution.score(%{"0" => 0.7, "1" => 0.3}, ["low", "high"], 0.3, 0.8)
    assert score.scalar == 0.3
    assert Distribution.to_map(score)["score"] == 0.3
    assert {:error, _} = Distribution.proposition(nil)
    assert {:error, _} = Distribution.choice(%{"a" => 0.4}, ["a", "b"], "a", 0.8)
  end

  test "exact source evidence rejects stale revisions, invented excerpts and split UTF-8" do
    model = Fount.Screenplay.new(scenes: [%{heading: "INT. CAFE - DAY", elements: [%{type: :action, text: "A caf\u00e9 closes."}]}])
    {:ok, units} = Fount.Selection.select(model, %{"whole_screenplay" => true})
    unit = Enum.find(units, &(&1["type"] == "action"))
    [entry] = Fount.Selection.evidence([unit])
    assert {:ok, %EvidenceRef{}} = EvidenceRef.from_source(model, entry)
    assert {:error, _} = EvidenceRef.from_source(model, Map.put(entry, "revision_id", "stale"))
    assert {:error, _} = EvidenceRef.from_source(model, Map.put(entry, "excerpt", "invented"))
    broken = put_in(entry, ["target", "span"], %{"byte_start" => 6, "byte_end" => 7})
    assert {:error, _} = EvidenceRef.from_source(model, broken)
    assert {:ok, %TargetRef{revision_id: revision}} = TargetRef.from_source(model, %{"kind" => "element", "id" => unit["target"]["id"]})
    assert revision == model.revision.id
  end

  test "context slots are closed, typed and deterministic; arbitrary structs never cross the boundary" do
    contract = %{"required" => %{"facts" => %{"type" => "list", "items" => "fact"}}, "optional" => %{}, "allow_unknown" => false}
    fact = %Fount.Observe.Context.Fact{subject: "key", predicate: "held_by", object: "Mara", stance: "asserted"}
    assert :ok = Context.validate(%Context{slots: %{"facts" => [fact]}}, contract)
    assert {:error, _} = Context.validate(%Context{}, contract)
    assert {:error, _} = Context.validate(%Context{slots: %{"facts" => [], "instructions" => "execute"}}, contract)
    assert {:error, _} = Context.validate(%Context{slots: %{"facts" => [%URI{}]}}, contract)
    assert Context.hash(%Context{slots: %{"facts" => [fact]}}) == Context.hash(%Context{slots: %{"facts" => [fact]}})
  end

  test "request metadata and evidence do not enter the semantic input" do
    model = Fount.Screenplay.new()
    assert {:ok, request} = Request.new(model, "r", %{"passage" => "Mara waits."})
    assert request.input == %{"passage" => "Mara waits."}
    assert request.target.revision_id == model.revision.id
    assert {:error, _} = Request.new(model, "", %{})
    assert {:error, _} = Request.new(model, "r", %{not_json: true})
  end
  test "malformed distributions return typed errors rather than raising" do
    assert {:error, _} = Distribution.validate(%Distribution{kind: :choice, values: [:bad]})
    assert {:error, _} = Distribution.choice(%{"a" => 0.5, "b" => 0.5}, ["a", "b"], %{}, 0.8)
    assert_raise ArgumentError, fn -> Question.noul("Visible?", extra: %{"type" => "other"}) end
  end

end
