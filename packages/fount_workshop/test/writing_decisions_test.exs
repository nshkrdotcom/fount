defmodule FountWorkshop.WritingDecisionsTest do
  use ExUnit.Case, async: true
  alias FountWorkshop.Writing.{ChangeGroups, ReviewGate}

  defp group(id, dependencies \\ []) do
    %{"id" => id, "depends_on" => dependencies,
      "operations" => [%{"kind" => "replace_text", "value" => id}]}
  end

  test "selection proposes required repairs without silently selecting them" do
    groups = [group("reveal", ["repair"]), group("independent"), group("repair")]
    assert {:ok, ordered} = ChangeGroups.order(groups)
    assert Enum.map(ordered, & &1["id"]) == ["independent", "repair", "reveal"]

    assert {:error, {:missing_required_groups, detail}} =
             ChangeGroups.select(groups, ["reveal"])
    assert detail["missing"] == ["repair"]
    assert detail["proposed_selection"] == ["repair", "reveal"]
  end

  test "cycles and missing dependencies are invalid" do
    assert {:error, {:cyclic_group_dependencies, _}} =
             ChangeGroups.order([group("a", ["b"]), group("b", ["a"])])
    assert {:error, {:unknown_group_dependencies, _}} =
             ChangeGroups.order([group("a", ["missing"])])
  end

  test "an unchecked semantic requirement needs an explicit reason" do
    candidate = %{
      "id" => "candidate", "base_revision_id" => "base", "content_hash" => "hash",
      "report_ids" => ["report"], "structural_errors" => [],
      "checks" => [%{"constraint_id" => "knowledge", "severity" => "required",
        "evaluation" => "semantic", "status" => "not_checked"}]
    }
    review = %{"candidate_id" => "candidate", "content_hash" => "hash",
      "report_ids" => ["report"], "actor" => "writer", "overrides" => []}

    assert {:error, {:review_blockers, _}} = ReviewGate.validate(candidate, review, "base")
    approved = Map.put(review, "overrides", [
      %{"constraint_id" => "knowledge", "reason" => "Reviewed the pages personally"}
    ])
    assert :ok = ReviewGate.validate(candidate, approved, "base")

    hard = put_in(candidate, ["checks"], [
      %{"constraint_id" => "knowledge", "severity" => "required",
        "evaluation" => "deterministic", "status" => "fail"}
    ])
    assert {:error, {:review_blockers, _}} = ReviewGate.validate(hard, approved, "base")
  end

  test "a review cannot be reused for different content" do
    candidate = %{"id" => "c", "base_revision_id" => "base", "content_hash" => "new"}
    review = %{"candidate_id" => "c", "content_hash" => "old", "actor" => "writer"}
    assert {:error, :review_content_mismatch} = ReviewGate.validate(candidate, review, "base")
  end
end
