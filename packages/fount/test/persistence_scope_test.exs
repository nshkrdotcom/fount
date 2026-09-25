defmodule Fount.PersistenceScopeTest do
  use ExUnit.Case, async: true
  alias Fount.Persistence.{Schema, Query}

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
    assert length(query.wheres) > 0
    assert Schema.Screenplay.__schema__(:fields) |> Enum.member?(:head_revision_id)
  end

  test "core review gate prevents direct persistence callers bypassing hard pins" do
    id = Fount.ID.v4()
    base = Fount.ID.v4()

    candidate = %{
      "id" => id,
      "base_revision_id" => base,
      "content_hash" => "hash",
      "report_ids" => [],
      "checks" => [
        %{"constraint_id" => "pin", "severity" => "required", "status" => "fail", "evaluation" => "deterministic"}
      ]
    }

    review = %{
      "candidate_id" => id,
      "content_hash" => "hash",
      "actor" => "writer",
      "report_ids" => [],
      "overrides" => [%{"constraint_id" => "pin", "reason" => "please"}]
    }

    assert {:error, _} = Fount.Writing.ReviewGate.validate(candidate, review, base)
  end
end
