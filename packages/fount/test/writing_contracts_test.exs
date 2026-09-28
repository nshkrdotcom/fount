defmodule Fount.WritingContractsTest do
  use ExUnit.Case, async: true
  alias Fount.Writing.{Approval, CanonicalJSON, Principal, Review, ReviewGate, LocalReferences, UTF8Span}

  test "spans are bytes, cannot split codepoints, and require exact excerpts" do
    assert {:ok, "é"} = UTF8Span.extract("café.", {3, 5})
    assert {:error, :split_utf8_codepoint} = UTF8Span.extract("café.", {3, 4})
    assert {:error, :excerpt_mismatch} = UTF8Span.verify("café.", [3, 5], "e")
    assert {:error, :invalid_span} = UTF8Span.extract("café.", {5, 5})
  end

  test "relocation detects overlap and does not reuse old pin offsets" do
    assert {:ok, {7, 11}} = UTF8Span.relocate("Before hold after", "hold")
    assert {:error, :ambiguous_protected_text} = UTF8Span.relocate("aaaa", "aaa")
    assert {:error, :protected_text_changed} = UTF8Span.relocate("changed", "hold")
  end

  test "canonical JSON sorts objects but retains array order" do
    assert CanonicalJSON.encode!(%{"z" => 1, "a" => %{"c" => 3, "b" => 2}}) ==
             ~s({"a":{"b":2,"c":3},"z":1})

    refute CanonicalJSON.hash([1, 2]) == CanonicalJSON.hash([2, 1])
    assert {:error, :object_keys_must_be_strings} = CanonicalJSON.encode(%{bad: 1})
  end

  test "local references allocate once and prose remains literal" do
    uuid = "f8136c1a-fb18-4c24-bd41-c2cb602c98a0"

    input = [
      %{"local_id" => "new:mara", "name" => "Mara"},
      %{"character_id" => "new:mara", "text" => "new:literal-dialogue"}
    ]

    assert {:ok, [character, line], %{"new:mara" => ^uuid}} =
             LocalReferences.compile(input, uuid: fn -> uuid end)

    assert character["id"] == uuid
    assert line["character_id"] == uuid
    assert line["text"] == "new:literal-dialogue"
  end

  test "duplicate declarations and undeclared references fail" do
    assert {:error, {:duplicate_local_ids, ["new:a"]}} =
             LocalReferences.compile([%{"local_id" => "new:a"}, %{"local_id" => "new:a"}])

    assert {:error, {:undeclared_local_reference, "new:missing"}} =
             LocalReferences.compile(%{"anchor_id" => "new:missing"})
  end

  test "typed review and approval serialize with stable identity" do
    {:ok, principal} = Principal.new(:human, "owner-1")
    fingerprint = CanonicalJSON.hash(%{"required_checks" => [], "checks" => [], "report_ids" => []})

    {:ok, review} =
      Review.new(
        reviewer: principal,
        candidate_id: "candidate-1",
        base_revision_id: "base-1",
        content_hash: "sha256-content",
        report_ids: [],
        check_set_fingerprint: fingerprint,
        recommendation: :approve
      )

    {:ok, approval} =
      Approval.new(
        id: Fount.ID.v4(),
        approver: principal,
        screenplay_id: "screenplay-1",
        candidate_id: "candidate-1",
        base_revision_id: "base-1",
        content_hash: "sha256-content",
        review: review
      )

    assert {:ok, ^review} = review |> Review.to_map() |> Review.from_map()
    assert {:ok, roundtrip} = approval |> Approval.to_map() |> Approval.from_map()
    assert Approval.fingerprint(roundtrip) == Approval.fingerprint(approval)
  end

  test "approval gate rejects automated overrides and hard required failures" do
    {:ok, human} = Principal.new(:human, "owner-1")
    {:ok, agent} = Principal.new(:agent, "reviewer-1")
    required = [%{"constraint_id" => "knowledge", "evaluation" => "semantic", "overridable" => true}]
    checks = [%{"constraint_id" => "knowledge", "severity" => "required", "evaluation" => "semantic", "status" => "unknown"}]
    fingerprint = CanonicalJSON.hash(%{"required_checks" => required, "checks" => checks, "report_ids" => []})
    candidate = %{
      "id" => "candidate-1",
      "base_revision_id" => "base-1",
      "content_hash" => "hash-1",
      "structural_errors" => [],
      "required_checks" => required,
      "checks" => checks,
      "report_ids" => [],
      "check_set_fingerprint" => fingerprint
    }

    attrs = [
      candidate_id: "candidate-1",
      base_revision_id: "base-1",
      content_hash: "hash-1",
      report_ids: [],
      check_set_fingerprint: fingerprint,
      recommendation: :approve,
      overrides: [%{"constraint_id" => "knowledge", "reason" => "Reviewed directly"}]
    ]

    {:ok, human_review} = Review.new(Keyword.put(attrs, :reviewer, human))
    assert :ok = ReviewGate.validate(candidate, human_review, human)

    {:ok, agent_review} = Review.new(Keyword.put(attrs, :reviewer, agent))
    assert {:error, :automated_override_forbidden} = ReviewGate.validate(candidate, agent_review, agent)

    hard_checks = [Map.merge(hd(checks), %{"evaluation" => "deterministic", "status" => "fail"})]
    hard_required = [%{"constraint_id" => "knowledge", "evaluation" => "deterministic", "overridable" => false}]
    hard_fp = CanonicalJSON.hash(%{"required_checks" => hard_required, "checks" => hard_checks, "report_ids" => []})
    hard_candidate = %{candidate | "required_checks" => hard_required, "checks" => hard_checks, "check_set_fingerprint" => hard_fp}
    {:ok, hard_review} = Review.new(Keyword.merge(attrs, reviewer: human, check_set_fingerprint: hard_fp, overrides: []))
    assert {:error, {:review_blockers, _}} = ReviewGate.validate(hard_candidate, hard_review, human)
  end
end