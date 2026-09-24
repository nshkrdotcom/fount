defmodule Fount.WritingPersistenceIntegrationTest do
  use ExUnit.Case, async: false
  alias Fount.{ID, Persistence, Query, Repo, Screenplay}

  setup_all do
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    start_supervised!({Repo, url: url, pool_size: 2})
    :ok
  end

  test "accepted revisions reload with immutable history and scoped structural rows" do
    key = "writing-#{ID.v4()}"
    root = Screenplay.new(scenes: [%{heading: "INT. ROOM - NIGHT", elements: [
      %{type: :action, text: "Mara waits."}
    ]}])

    assert {:ok, ^root} = Persistence.create(Repo, key, root)
    assert {:ok, loaded} = Persistence.load(Repo, key)
    assert Screenplay.to_fountain(loaded) == Screenplay.to_fountain(root)
    line = Enum.find(root.ir.elements, &(&1.type == :action))
    assert {:ok, edited, _} = Screenplay.apply(root, [%{
      "kind" => "replace_text", "target" => %{"kind" => "element", "id" => line.id},
      "value" => "Mara leaves."
    }], [])
    assert {:ok, ^edited} = Persistence.save_edit(Repo, key, edited, expected_revision: root.revision.id)
    assert {:ok, head} = Persistence.load(Repo, key)
    assert Query.node(head, line.id).text == "Mara leaves."
    assert {:ok, old} = Persistence.load_revision(Repo, root.id, root.revision.id)
    assert Query.node(old, line.id).text == "Mara waits."
    assert Enum.map(Persistence.history(Repo, root.id), & &1.id) == [edited.revision.id, root.revision.id]
    assert {:error, {:stale_revision, _}} = Persistence.save_edit(Repo, key, edited, expected_revision: root.revision.id)
  end

  test "candidate save preserves head; review acceptance moves it exactly once" do
    key = "candidates-#{ID.v4()}"
    root = Screenplay.new()
    assert {:ok, _} = Persistence.create(Repo, key, root)

    session = %{
      screenplay_id: root.id, base_revision_id: root.revision.id, workflow: "develop",
      request: %{"brief" => "A banker follows the wrong person."}, status: "open"
    }
    assert {:ok, session} = Persistence.save_session(Repo, session)
    assert {:error, :stale_session} = Persistence.save_session(Repo, %{session | lock_version: 0})

    op = %{"kind" => "insert_scene", "value" => %{
      "after_scene_id" => nil,
      "scene" => %{"local_id" => "new:one", "heading" => "EXT. STATION - NIGHT",
        "elements" => [%{"local_id" => "new:action", "type" => "action", "text" => "Mara misses the last train."}]}
    }}
    assert {:ok, materialized, changes} = Screenplay.apply(root, [op], [])
    candidate = %{screenplay: materialized, label: "Missed train", change_groups: [%{"id" => "scene", "operations" => changes.operations}]}
    assert {:ok, candidate} = Persistence.save_candidate(Repo, session.id, candidate)
    assert {:ok, still_root} = Persistence.load(Repo, key)
    assert still_root.revision.id == root.revision.id
    assert {:ok, _} = Persistence.load_revision(Repo, root.id, materialized.revision.id)

    review = %{candidate_id: candidate.id, content_hash: materialized.revision.content_hash,
      actor: "writer", structural_errors: []}
    assert {:error, :review_content_mismatch} = Persistence.accept_candidate(Repo, candidate.id,
      expected_revision: root.revision.id, actor: "writer", review: %{review | content_hash: "wrong"})
    assert {:ok, accepted} = Persistence.accept_candidate(Repo, candidate.id,
      expected_revision: root.revision.id, actor: "writer", review: review)
    assert accepted.revision.id == materialized.revision.id
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == materialized.revision.id
    assert {:error, :already_accepted} = Persistence.accept_candidate(Repo, candidate.id,
      expected_revision: root.revision.id, actor: "writer", review: review)
    assert {:error, :already_accepted} = Persistence.reject_candidate(Repo, candidate.id, actor: "writer")
  end

  test "imported Fountain bytes survive a round trip through PostgreSQL" do
    raw = "Title: The Debt\r\n\r\nINT. VAULT - NIGHT\r\n\r\nMARA\r\nGive me the clé.\r\n"
    key = "fountain-#{ID.v4()}"
    root = raw |> Fount.parse!() |> Screenplay.from_document(cast_resolution: :literal_cues)
    assert {:ok, _} = Persistence.create(Repo, key, root)
    assert {:ok, loaded} = Persistence.load(Repo, key)
    assert Screenplay.to_fountain(loaded) == raw
    assert length(loaded.ir.dialogue_blocks) == 1
    assert length(Fount.Query.characters(loaded)) == 1
  end

  test "a report cannot cite uninspected evidence or a changed excerpt" do
    root = Screenplay.new(scenes: [%{heading: "INT. ROOM - DAY", elements: [
      %{type: :action, text: "Mara pockets the key."}
    ]}])
    assert {:ok, _} = Persistence.create(Repo, "report-#{ID.v4()}", root)
    line = Enum.find(root.ir.elements, &(&1.type == :action))
    evidence = %{"evidence_id" => "e1", "screenplay_id" => root.id,
      "revision_id" => root.revision.id, "target" => %{"kind" => "element", "id" => line.id},
      "excerpt" => line.text}
    base = %{screenplay_id: root.id, primary_revision_id: root.revision.id,
      tool: "continuity", fingerprint: "probe-v1", payload: %{"evidence" => [evidence], "citations" => ["e1"]}}
    assert {:ok, _} = Persistence.save_report(Repo, base)
    assert {:error, :uninspected_citation} = Persistence.save_report(Repo,
      %{base | payload: %{"evidence" => [evidence], "citations" => ["missing"]}})
    assert {:error, :evidence_excerpt_mismatch} = Persistence.save_report(Repo,
      %{base | payload: %{"evidence" => [%{evidence | "excerpt" => "Mara drops the key."}]}})
  end
end
