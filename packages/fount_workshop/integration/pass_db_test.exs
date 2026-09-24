defmodule FountWorkshop.PassDatabaseIntegrationTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Query, Repo, Screenplay}
  alias FountWorkshop.Pass

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "dialogue pass stores real dialogue edits without moving the accepted draft" do
    key = "pass-#{ID.v4()}"

    root =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "I am angry with you."}
            ]
          }
        ]
      )

    {:ok, _} = Persistence.create(Repo, key, root)
    [scene] = root.ir.scenes
    line = Enum.find(root.ir.elements, &(&1.type == :dialogue))
    response = %{"changes" => [%{"element_id" => line.id, "text" => "You kept the spare key."}]}

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        adapter_opts: [response_text: Jason.encode!(response)]
      )

    assert {:ok, result} =
             Pass.run(
               Repo,
               key,
               "dialogue_subtext",
               [scene.id],
               "Make the accusation indirect.",
               client
             )

    assert {:ok, saved} = Persistence.candidate(Repo, result.candidate.id)
    assert Query.node(saved["screenplay"], line.id).text == "You kept the spare key."
    assert {:ok, head} = Persistence.load(Repo, key)
    assert Query.node(head, line.id).text == line.text
    assert head.revision.id == root.revision.id
  end
end
