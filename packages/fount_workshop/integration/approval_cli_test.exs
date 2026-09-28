defmodule FountWorkshop.ApprovalCLIIntegrationTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias FountWorkshop.CLI

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "local CLI accepts only the configured human owner for the candidate screenplay" do
    original = for key <- ["FOUNT_LOCAL_OWNER_ID", "FOUNT_LOCAL_SCREENPLAY_ID"], into: %{}, do: {key, System.get_env(key)}

    on_exit(fn ->
      for {key, value} <- original do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    root = Screenplay.new()
    key = "cli-owner-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, root)
    assert {:ok, session} = Persistence.save_session(Repo, %{
      screenplay_id: root.id, base_revision_id: root.revision.id,
      workflow: "pass", request: %{}, status: "open"
    })

    operation = %{"kind" => "insert_scene", "value" => %{"after_scene_id" => nil, "scene" => %{
      "local_id" => "new:scene", "heading" => "INT. OFFICE - DAY",
      "elements" => [%{"local_id" => "new:action", "type" => "action", "text" => "Mara opens the file.", "attrs" => %{}}]
    }}}
    assert {:ok, draft, _} = Screenplay.apply(root, [operation], [])
    assert {:ok, candidate} = Persistence.save_candidate(Repo, session.id, %{screenplay: draft})

    args = ["--candidate", candidate.id, "--expected-revision", root.revision.id,
      "--actor", "writer", "--principal-type", "human", "--approval-id", ID.v4()]

    System.delete_env("FOUNT_LOCAL_OWNER_ID")
    System.delete_env("FOUNT_LOCAL_SCREENPLAY_ID")
    assert {:error, :local_approval_authority_unconfigured} = CLI.run("accept", args)

    System.put_env("FOUNT_LOCAL_OWNER_ID", "writer")
    System.put_env("FOUNT_LOCAL_SCREENPLAY_ID", ID.v4())
    assert {:error, :local_approval_authority_mismatch} = CLI.run("accept", args)

    System.put_env("FOUNT_LOCAL_SCREENPLAY_ID", root.id)
    assert {:error, :local_approval_authority_mismatch} =
             CLI.run("accept", List.replace_at(args, 7, "agent"))
    assert {:error, :local_approval_authority_mismatch} =
             CLI.run("accept", List.replace_at(args, 5, "intruder"))

    assert {:ok, _} = CLI.run("accept", args)
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == draft.revision.id
  end
end
