defmodule FountWorkshop.PhaseThirteenRehearsalDurabilityTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias FountWorkshop.{Rehearsal, Session, Store}

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "rehearsal decisions survive a fresh database read without changing canon" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. KITCHEN - NIGHT",
            elements: [%{type: :action, text: "Dan waits at the window."}]
          }
        ]
      )

    key = "phase13-rehearsal-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, base)
    services = %{store: Store.new(Repo)}

    request = %{
      "version" => 1,
      "workflow" => "pass",
      "mode" => "explore",
      "base_revision_id" => base.revision.id,
      "instruction" => "Explore a private possibility without changing the pages.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{"profile" => "cinematic_rhythm"}
    }

    assert {:ok, opened} = Session.open(base, request, services)

    assert {:ok, active} =
             Rehearsal.add(
               opened["id"],
               %{
                 "kind" => "invented_backstory",
                 "prompt" => "Privately try the boat history.",
                 "invented_claims" => ["Dan once stole a boat"]
               },
               services,
               actor: "writer"
             )

    assert {:ok, before_decision} = Session.resume_view(opened["id"], services)
    assert Rehearsal.generation_context(before_decision) == []

    assert {:ok, adopted} =
             Rehearsal.adopt(opened["id"], active["id"], services,
               actor: "writer",
               note: "Use only for exploratory drafts."
             )

    assert adopted["adoption"]["actor"] == "writer"
    assert adopted["adoption"]["note"] == "Use only for exploratory drafts."

    assert {:ok, rejected} =
             Rehearsal.add(
               opened["id"],
               %{
                 "kind" => "private_conversation",
                 "prompt" => "Try an off-page talk.",
                 "invented_claims" => ["Mara owns the marina"]
               },
               services
             )

    assert {:ok, _} =
             Rehearsal.reject(opened["id"], rejected["id"], services,
               actor: "writer",
               note: "Do not use this."
             )

    fresh_services = %{store: Store.new(Repo)}
    assert {:ok, resumed} = Session.resume_view(opened["id"], fresh_services)
    assert Enum.map(Rehearsal.list(resumed), & &1["status"]) == ["adopted", "rejected"]
    assert [material] = Rehearsal.generation_context(resumed)
    assert material["invented_claims"] == ["Dan once stole a boat"]
    assert material["canonical"] == false
    refute String.contains?(inspect(resumed["request"]), "stole a boat")
    refute String.contains?(inspect(resumed["request"]), "marina")

    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == base.revision.id
    refute String.contains?(Screenplay.to_fountain(head), "stole a boat")
    refute String.contains?(Screenplay.to_fountain(head), "marina")
  end
end
