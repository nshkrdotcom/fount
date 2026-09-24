defmodule FountWorkshop.RecoverDatabaseIntegrationTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Query, Repo, Screenplay}
  alias FountWorkshop.Recover

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "a cut beat is found in history and restored only to a candidate" do
    key = "recover-#{ID.v4()}"

    root =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ROOM - DAY",
            elements: [
              %{type: :action, text: "Mara takes the brass key."},
              %{type: :action, text: "Dan watches her pocket it."}
            ]
          }
        ]
      )

    {:ok, _} = Persistence.create(Repo, key, root)
    lost = Enum.find(root.ir.elements, &(&1.text == "Dan watches her pocket it."))

    {:ok, edited, _} =
      Screenplay.apply(root, [
        %{
          "kind" => "delete_elements",
          "value" => %{"ids" => [lost.id]}
        }
      ])

    assert {:ok, _} =
             Persistence.save_edit(Repo, key, edited, expected_revision: root.revision.id)

    assert {:ok, result} = Recover.run(Repo, key, root.revision.id, lost.id)
    assert {:ok, saved} = Persistence.candidate(Repo, result.candidate.id)
    assert Query.node(saved["screenplay"], lost.id).text == lost.text
    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == edited.revision.id
    assert Query.node(head, lost.id) == nil
  end
end
