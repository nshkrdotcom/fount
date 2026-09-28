defmodule FountWorkshop.WritingDecisionsTest do
  use ExUnit.Case, async: true
  alias Fount.Writing.{CanonicalJSON, Principal, Review}
  alias FountWorkshop.Writing.{ChangeGroups, ReviewGate}

  defp group(id, dependencies \\ []) do
    %{
      "id" => id,
      "depends_on" => dependencies,
      "operations" => [%{"kind" => "replace_text", "value" => id}]
    }
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

  test "an unchecked semantic requirement needs an explicit authorized human override" do
    required = [%{"constraint_id" => "knowledge", "evaluation" => "semantic", "overridable" => true}]
    checks = [%{"constraint_id" => "knowledge", "severity" => "required", "evaluation" => "semantic", "status" => "not_checked"}]
    fingerprint = CanonicalJSON.hash(%{"required_checks" => required, "checks" => checks, "report_ids" => ["report"]})
    candidate = %{
      "id" => "candidate", "base_revision_id" => "base", "content_hash" => "hash",
      "report_ids" => ["report"], "structural_errors" => [], "checks" => checks,
      "required_checks" => required, "check_set_fingerprint" => fingerprint
    }
    {:ok, principal} = Principal.new(:human, "writer")
    attrs = [reviewer: principal, candidate_id: "candidate", base_revision_id: "base",
      content_hash: "hash", report_ids: ["report"], check_set_fingerprint: fingerprint,
      recommendation: :approve, overrides: []]
    {:ok, review} = Review.new(attrs)
    assert {:error, {:review_blockers, _}} = ReviewGate.validate(candidate, review, principal)

    {:ok, approved} = Review.new(Keyword.put(attrs, :overrides, [%{"constraint_id" => "knowledge", "reason" => "Reviewed the pages personally"}]))
    assert :ok = ReviewGate.validate(candidate, approved, principal)

    hard_required = [%{"constraint_id" => "knowledge", "evaluation" => "deterministic", "overridable" => false}]
    hard_checks = [%{"constraint_id" => "knowledge", "severity" => "required", "evaluation" => "deterministic", "status" => "fail"}]
    hard_fp = CanonicalJSON.hash(%{"required_checks" => hard_required, "checks" => hard_checks, "report_ids" => ["report"]})
    hard = %{candidate | "required_checks" => hard_required, "checks" => hard_checks, "check_set_fingerprint" => hard_fp}
    {:ok, hard_review} = Review.new(Keyword.merge(attrs, check_set_fingerprint: hard_fp, overrides: []))
    assert {:error, {:review_blockers, _}} = ReviewGate.validate(hard, hard_review, principal)
  end

  test "a review cannot be reused for different content" do
    {:ok, principal} = Principal.new(:human, "writer")
    fingerprint = CanonicalJSON.hash(%{"required_checks" => [], "checks" => [], "report_ids" => []})
    candidate = %{"id" => "c", "base_revision_id" => "base", "content_hash" => "new", "report_ids" => [],
      "structural_errors" => [], "checks" => [], "required_checks" => [], "check_set_fingerprint" => fingerprint}
    {:ok, review} = Review.new(reviewer: principal, candidate_id: "c", base_revision_id: "base",
      content_hash: "old", report_ids: [], check_set_fingerprint: fingerprint, recommendation: :approve)
    assert {:error, :review_content_mismatch} = ReviewGate.validate(candidate, review, principal)
  end
end