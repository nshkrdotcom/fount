defmodule Fount.ContinuationConcurrencyIntegrationTest do
  use ExUnit.Case, async: false
  alias Fount.{Persistence, Repo, Screenplay}
  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 5})
    :ok
  end
  test "same revision ID cannot disguise changed text on a no-op save" do
    root = Screenplay.new(scenes: [%{heading: "INT. ROOM - NIGHT", elements: [%{type: :action, text: "Mara waits."}]}])
    key = "identity-#{Fount.ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)
    e = Enum.find(root.ir.elements, &(&1.type == :action))
    assert {:ok, changed, _} = Screenplay.apply(root, [%{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => e.id}, "value" => "Mara leaves."}], [])
    forged = %{changed | revision: %{changed.revision | id: root.revision.id, parent_id: nil}}
    assert {:error, :revision_identity_conflict} = Persistence.save_edit(Repo, key, forged, expected_revision: root.revision.id)
    assert {:ok, head} = Persistence.load(Repo, key)
    assert Fount.Query.node(head, e.id).text == "Mara waits."
  end
  test "two accepted edits racing the same head cannot both advance it" do
    root = Screenplay.new(scenes: [%{heading: "INT. ROOM - NIGHT", elements: [%{type: :action, text: "Mara waits."}]}])
    key = "race-#{Fount.ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)
    e = Enum.find(root.ir.elements, &(&1.type == :action))
    results = ["Mara leaves.", "Mara locks the door."] |> Task.async_stream(fn text ->
      {:ok, candidate, _} = Screenplay.apply(root, [%{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => e.id}, "value" => text}], [])
      Persistence.save_edit(Repo, key, candidate, expected_revision: root.revision.id, actor: "integration-writer")
    end, max_concurrency: 2, timeout: 15_000) |> Enum.map(fn {:ok, result} -> result end)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, {:stale_revision, _}}, &1)) == 1
  end

  test "two candidate acceptances racing the same head cannot both advance it" do
    root = Screenplay.new(scenes: [%{heading: "INT. ROOM - NIGHT", elements: [%{type: :action, text: "Mara waits."}]}])
    key = "candidate-race-#{Fount.ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)

    assert {:ok, session} =
             Persistence.save_session(Repo, %{
               screenplay_id: root.id,
               base_revision_id: root.revision.id,
               workflow: "pass",
               request: %{},
               status: "open"
             })

    line = Enum.find(root.ir.elements, &(&1.type == :action))

    candidates =
      Enum.map(["Mara leaves.", "Mara locks the door."], fn text ->
        operation = %{
          "kind" => "replace_text",
          "target" => %{"kind" => "element", "id" => line.id},
          "value" => text
        }

        {:ok, draft, _} = Screenplay.apply(root, [operation], [])
        {:ok, candidate} = Persistence.save_candidate(Repo, session.id, %{screenplay: draft})
        candidate
      end)

    results =
      candidates
      |> Task.async_stream(
        fn candidate ->
          review = %{
            candidate_id: candidate.id,
            content_hash: candidate.screenplay.revision.content_hash,
            actor: "writer"
          }

          Persistence.accept_candidate(Repo, candidate.id,
            expected_revision: root.revision.id,
            actor: "writer",
            review: review
          )
        end,
        max_concurrency: 2,
        timeout: 15_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, {:stale_revision, _}}, &1)) == 1
    {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.parent_id == root.revision.id
  end
end
