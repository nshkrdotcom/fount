defmodule Fount.PersistenceScopeTest do
  alias Fount.Persistence.Query
  alias Fount.Persistence.Schema
  alias Fount.Writing.{CanonicalJSON, Principal, Review, ReviewGate}
  use ExUnit.Case, async: true

  test "all projection schemas carry the immutable revision key" do
    for module <- [
          Schema.Scene,
          Schema.Element,
          Schema.Character,
          Schema.DialogueBlock,
          Schema.AuthoredItem,
          Schema.Mention
        ] do
      assert :revision_id in module.__schema__(:primary_key)
      assert :screenplay_id in module.__schema__(:primary_key)
    end
  end

  test "public relational queries require an explicit revision" do
    query = Query.scenes(Fount.ID.v4(), Fount.ID.v4())
    assert [%Ecto.Query.BooleanExpr{} | _] = query.wheres
    assert Schema.Screenplay.__schema__(:fields) |> Enum.member?(:head_revision_id)
  end

  test "core review gate prevents direct persistence callers bypassing hard pins" do
    id = Fount.ID.v4()
    base = Fount.ID.v4()
    required = [%{"constraint_id" => "pin", "evaluation" => "deterministic", "overridable" => false}]
    checks = [%{"constraint_id" => "pin", "severity" => "required", "status" => "fail", "evaluation" => "deterministic"}]
    fingerprint = CanonicalJSON.hash(%{"required_checks" => required, "checks" => checks, "report_ids" => []})

    candidate = %{
      "id" => id,
      "base_revision_id" => base,
      "content_hash" => "hash",
      "report_ids" => [],
      "structural_errors" => [],
      "required_checks" => required,
      "check_set_fingerprint" => fingerprint,
      "checks" => checks
    }

    {:ok, principal} = Principal.new(:human, "writer")
    {:ok, review} = Review.new(reviewer: principal, candidate_id: id, base_revision_id: base,
      content_hash: "hash", report_ids: [], check_set_fingerprint: fingerprint,
      recommendation: :approve, overrides: [])

    assert {:error, {:review_blockers, _}} = ReviewGate.validate(candidate, review, principal)
  end
end