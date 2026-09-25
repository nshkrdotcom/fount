defmodule FountProbe.ContinuationConstraintsTest do
  use ExUnit.Case, async: true
  alias FountProbe.Constraints
  test "a shifted protected fragment is mapped, but ambiguous copies are rejected" do
    base = Fount.Screenplay.new(scenes: [%{heading: "INT. SHED - DAY", elements: [%{type: :action, text: "She keeps the key."}]}])
    e = Enum.find(base.ir.elements, &(&1.type == :action))
    c = %{"id" => "key", "target" => %{"kind" => "element", "id" => e.id}, "kind" => "pin_text", "spec" => %{"text" => "the key"}, "severity" => "required", "source" => "writer"}
    {:ok, next, _} = Fount.Screenplay.apply(base, [%{"kind" => "replace_text", "target" => c["target"], "value" => "Quietly, she keeps the key."}])
    [result] = Constraints.deterministic(base, next, [c])
    assert result["status"] == "pass"
    assert result["measurements"]["candidate_span"]["byte_start"] == 18
    {:ok, bad, _} = Fount.Screenplay.apply(base, [%{"kind" => "replace_text", "target" => c["target"], "value" => "the key and the key"}])
    assert hd(Constraints.deterministic(base, bad, [c]))["status"] == "fail"
  end
  test "negative semantic intent uses the complementary probability" do
    constraint = %{"kind" => "semantic", "spec" => %{"question_type" => "noul", "expected" => false}}
    answer = %{"type" => "noul", "probability" => 0.9}
    assert Constraints.interpret(constraint, answer)["status"] == "fail"
  end
  test "missing external pagination never becomes zero or a pass" do
    base = Fount.Screenplay.new()
    c = %{"id" => "pages", "target" => %{"kind" => "screenplay", "id" => base.id}, "kind" => "page_goal", "spec" => %{"max" => 5}, "severity" => "required"}
    assert [%{"status" => "unknown", "evaluation" => "external"}] = Constraints.deterministic(base, base, [c])
  end
end
