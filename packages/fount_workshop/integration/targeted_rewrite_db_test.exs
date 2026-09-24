defmodule FountWorkshop.TargetedRewriteDatabaseIntegrationTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Query, Repo, Screenplay}
  alias FountWorkshop.TargetedRewrite

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "exact rewrite saves and reopens a candidate without changing the accepted page" do
    key = "rewrite-#{ID.v4()}"

    root =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - NIGHT",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "I know you took it."}
            ]
          }
        ]
      )

    {:ok, _} = Persistence.create(Repo, key, root)
    target = Enum.find(root.ir.elements, &(&1.text == "I know you took it."))

    output = %{
      "changes" => [%{"element_id" => target.id, "text" => "Then why is the safe open?"}]
    }

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        adapter_opts: [response_text: Jason.encode!(output)]
      )

    assert {:ok, result} =
             TargetedRewrite.run(Repo, key, [target.id], "Make the accusation indirect.", client)

    assert {:ok, saved} = Persistence.candidate(Repo, result.candidate.id)
    assert Query.node(saved["screenplay"], target.id).text == "Then why is the safe open?"
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == root.revision.id
    assert Query.node(head, target.id).text == "I know you took it."
  end
end
