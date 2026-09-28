defmodule FountWorkshop.PhaseFifteenReadShareResumeIntegrationTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias FountWorkshop.{Acceptance, Candidate, Session, Share, Store, TableRead}

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "accepted head, candidate decisions, clean share and read identity survive a fresh database read" do
    base =
      Screenplay.new(
        title: [{"Title", ["Phase Fifteen"]}],
        scenes: [
          %{
            heading: "INT. DINER - NIGHT",
            elements: [
              %{type: :note, text: "PRIVATE NOTE"},
              %{type: :action, text: "Mara leaves the receipt under the cup."},
              %{type: :character, text: "MARA"},
              %{type: :dialogue, text: "He already knows."}
            ]
          }
        ]
      )

    key = "phase15-read-share-resume-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, base)
    services = %{store: Store.new(Repo)}
    assert {:ok, opened} = Session.open(base, request(base), services)
    action = Enum.find(base.ir.elements, &(&1.type == :action))

    assert {:ok, chosen} =
             Candidate.manual(
               opened["id"],
               [replace(action.id, "Mara folds the receipt once and leaves it under the cup.")],
               services,
               actor: "writer",
               label: "Chosen"
             )

    assert {:ok, rejected} =
             Candidate.manual(
               opened["id"],
               [replace(action.id, "Mara explains the receipt before leaving it under the cup.")],
               services,
               actor: "writer",
               label: "Rejected"
             )

    assert {:ok, accepted} =
             FountWorkshop.TestApproval.accept(services, chosen["id"])

    assert {:ok, _} = Acceptance.reject(rejected["id"], "writer", services)

    fresh_services = %{store: Store.new(Repo)}
    assert {:ok, fresh_head} = Persistence.load(Repo, key)
    assert fresh_head.id == base.id
    assert fresh_head.revision.id == accepted.revision.id

    assert {:ok, resumed} = Session.resume_view(opened["id"], fresh_services)
    decisions = Map.new(resumed["candidates"], &{&1["id"], &1["decision"]})
    assert decisions[chosen["id"]] == "accepted"
    assert decisions[rejected["id"]] == "rejected"

    assert {:ok, packet} = TableRead.packet(fresh_head)
    assert packet["source"]["screenplay_id"] == base.id
    assert packet["source"]["revision_id"] == accepted.revision.id

    directory = Path.join(System.tmp_dir!(), "fount-phase15-db-share-#{ID.v4()}")
    on_exit(fn -> File.rm_rf(directory) end)
    assert {:ok, share} = Share.export(fresh_head, %{"whole_screenplay" => true}, directory)
    assert share["source"]["revision_id"] == accepted.revision.id
    refute File.read!(Path.join(directory, "screenplay.fountain")) =~ "PRIVATE NOTE"
  end

  defp replace(id, text),
    do: %{
      "kind" => "replace_text",
      "target" => %{"kind" => "element", "id" => id},
      "value" => text
    }


  defp request(base),
    do: %{
      "version" => 1,
      "workflow" => "alternatives",
      "mode" => "revise",
      "base_revision_id" => base.revision.id,
      "instruction" => "Try two explicit writer-controlled variants.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 2,
      "options" => %{"pending_question" => "Which version reads cleanly?"}
    }
end