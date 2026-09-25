defmodule FountProbe.ConstraintContractNamesTest do
  use ExUnit.Case, async: true
  test "canonical numeric names and typed before/after targets are accepted" do
    m = Fount.Screenplay.new(scenes: [%{heading: "INT. OFFICE - DAY", elements: [%{type: :action, text: "Mara waits."}]}])
    [s] = m.ir.scenes
    target = %{"kind" => "screenplay", "id" => m.id}
    c = %{"id" => "short", "kind" => "word_limit", "target" => target,
      "spec" => %{"maximum" => 3, "scope" => "action"}, "severity" => "required", "source" => "writer"}
    assert :ok = FountProbe.Constraints.validate(c)
    assert [%{"status" => "pass"}] = FountProbe.Constraints.deterministic(m, m, [c])
    c = %{c | "id" => "keep", "kind" => "retain_ids", "spec" => %{"ids" => [%{"kind" => "scene", "id" => s.id}]}}
    assert :ok = FountProbe.Constraints.validate(c)
    assert [%{"status" => "pass"}] = FountProbe.Constraints.deterministic(m, m, [c])
  end
  test "a suggestion cannot become a required constraint without writer adoption" do
    m = Fount.Screenplay.new()
    c = %{"id" => "suggestion", "kind" => "scene_count", "target" => %{"kind" => "screenplay", "id" => m.id},
      "spec" => %{"minimum" => 2}, "severity" => "required", "source" => "suggested"}
    assert {:ok, [%{"severity" => "advisory"}]} = FountProbe.Constraints.resolve(m, [c])
  end
end
