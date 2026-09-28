Code.require_file("../../support/continuation_store.ex", __DIR__)

defmodule FountWorkshop.PhaseThirteenRehearsalTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.{Rehearsal, Session, Store}
  alias FountWorkshop.TestSupport.ContinuationStore

  test "A05 invented rehearsal backstory stays noncanonical and out of generation context until adoption" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. KITCHEN - NIGHT",
            elements: [%{type: :action, text: "Dan waits beside the dark window."}]
          }
        ]
      )

    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)
    services = %{store: %Store{repo: repo, module: ContinuationStore}}

    request = %{
      "version" => 1,
      "workflow" => "pass",
      "mode" => "explore",
      "base_revision_id" => base.revision.id,
      "instruction" => "Rehearse private possibilities without changing canon.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{"profile" => "cinematic_rhythm"}
    }

    assert {:ok, session} = Session.open(base, request, services)

    assert {:ok, exercise} =
             Rehearsal.add(
               session["id"],
               %{
                 "kind" => "invented_backstory",
                 "prompt" => "Privately improvise how Dan behaves if he once stole a boat.",
                 "invented_claims" => ["Dan once stole a boat"]
               },
               services,
               actor: "writer"
             )

    assert {:ok, before_adoption} = Store.call(services.store, :session, [session["id"]])
    assert Rehearsal.generation_context(before_adoption) == []
    refute String.contains?(Screenplay.to_fountain(ContinuationStore.head(repo)), "stole a boat")
    refute String.contains?(inspect(before_adoption["request"]), "stole a boat")

    assert {:ok, adopted} =
             Rehearsal.adopt(session["id"], exercise["id"], services,
               actor: "writer",
               note: "Keep this as project-room material for later exploration."
             )

    assert adopted["status"] == "adopted"
    assert adopted["canonical"] == false

    assert {:ok, after_adoption} = Store.call(services.store, :session, [session["id"]])
    assert [context] = Rehearsal.generation_context(after_adoption)
    assert context["invented_claims"] == ["Dan once stole a boat"]
    assert context["source"] == "explicitly_adopted_rehearsal"
    assert context["canonical"] == false
    assert ContinuationStore.head(repo).revision.id == base.revision.id

    assert {:ok, rejected_exercise} =
             Rehearsal.add(
               session["id"],
               %{
                 "kind" => "private_conversation",
                 "prompt" => "Try a conversation that never appears in the film.",
                 "invented_claims" => ["Mara secretly owns the marina"]
               },
               services
             )

    assert {:ok, _} =
             Rehearsal.reject(session["id"], rejected_exercise["id"], services,
               actor: "writer",
               note: "Useful exercise, not project material."
             )

    assert {:ok, final} = Store.call(services.store, :session, [session["id"]])
    [only] = Rehearsal.generation_context(final)
    refute Enum.any?(only["invented_claims"], &String.contains?(&1, "marina"))
  end
end
