defmodule Fount.ContinuationConcurrencyIntegrationTest do
  use ExUnit.Case, async: false
  alias Ecto.Adapters.SQL
  alias Fount.{Persistence, Repo, Screenplay}
  alias Fount.Writing.{Approval, Authority, Principal}

  defmodule RaceRepoOne do
    use Ecto.Repo, otp_app: :fount, adapter: Ecto.Adapters.Postgres
  end

  defmodule RaceRepoTwo do
    use Ecto.Repo, otp_app: :fount, adapter: Ecto.Adapters.Postgres
  end

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 5})
    :ok
  end

  defp direct_approval(repo, id, actor) do
    {:ok, candidate} = Persistence.candidate(repo, id)
    {:ok, principal} = Principal.new(:human, actor)
    {:ok, authority} = Authority.new(principal, candidate["screenplay_id"], [:approve])
    {:ok, approval} = Approval.direct(candidate, principal, Fount.ID.v4())
    {approval, authority}
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
  test "direct edits racing the same head are both blocked before persistence" do
    root = Screenplay.new(scenes: [%{heading: "INT. ROOM - NIGHT", elements: [%{type: :action, text: "Mara waits."}]}])
    key = "direct-race-#{Fount.ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)
    e = Enum.find(root.ir.elements, &(&1.type == :action))

    results =
      ["Mara leaves.", "Mara locks the door."]
      |> Task.async_stream(fn text ->
        {:ok, candidate, _} = Screenplay.apply(root, [%{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => e.id}, "value" => text}], [])
        Persistence.save_edit(Repo, key, candidate, expected_revision: root.revision.id)
      end, max_concurrency: 2, timeout: 15_000)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &(&1 == {:error, :approval_required}))
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == root.revision.id
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

    parent = self()
    url = System.fetch_env!("FOUNT_DATABASE_URL")
    start_supervised!({RaceRepoOne, url: url, pool_size: 1})
    start_supervised!({RaceRepoTwo, url: url, pool_size: 1})

    tasks =
      Enum.zip(candidates, [RaceRepoOne, RaceRepoTwo])
      |> Enum.map(fn {candidate, race_repo} ->
        Task.async(fn ->
          backend_pid = SQL.query!(race_repo, "SELECT pg_backend_pid()", [], log: false).rows |> hd() |> hd()
          send(parent, {:ready, self(), backend_pid})
          receive do
            :go -> :ok
          end

          {approval, authority} = direct_approval(race_repo, candidate.id, "writer-#{candidate.id}")
          Persistence.accept_candidate(race_repo, candidate.id, approval: approval, authority: authority)
        end)
      end)

    ready =
      for _ <- tasks do
        receive do
          {:ready, task_pid, backend_pid} -> {task_pid, backend_pid}
        end
      end
    assert ready |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 2
    Enum.each(ready, fn {task_pid, _} -> send(task_pid, :go) end)
    results = Enum.map(tasks, &Task.await(&1, 15_000))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, {:stale_revision, _}}, &1)) == 1
    {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.parent_id == root.revision.id

    assert [[1]] =
             SQL.query!(
               Repo,
               "SELECT count(*) FROM acceptances WHERE screenplay_id=$1::text::uuid AND acceptance_kind='approved'",
               [root.id],
               log: false
             ).rows
  end
end
