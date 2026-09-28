Code.require_file("../../support/continuation_store.ex", __DIR__)

defmodule FountWorkshop.PhaseTwelveInspectTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.{Discovery, Session, Store}
  alias FountWorkshop.TestSupport.ContinuationStore

  test "inspect keeps fact and interpretation distinct and leaves the quiet original untouched" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. KITCHEN - DAWN",
            elements: [
              %{type: :action, text: "Mara sets Dan's key beside his untouched coffee."},
              %{type: :action, text: "She leaves without waking him."}
            ]
          }
        ]
      )

    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)
    services = %{store: %Store{repo: repo, module: ContinuationStore}}
    scene_id = hd(base.ir.scenes).id

    request = %{
      "version" => 1,
      "workflow" => "investigate",
      "mode" => "inspect",
      "base_revision_id" => base.revision.id,
      "instruction" => "Inspect whether the key choice is legible without adding explanation.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "options" => %{
        "concern" =>
          "Can a first reader register the physical choice without assigning a motive?",
        "write_fixes" => false,
        "protected_strengths" => ["Mara leaves without waking Dan."]
      }
    }

    assert {:ok, session} = Session.open(base, request, services)
    assert get_in(session, ["progress", "discovery", "current_mode"]) == "inspect"
    assert session["strategies"] == []
    assert ContinuationStore.head(repo).revision.content_hash == base.revision.content_hash

    assert {:ok, outline} =
             Discovery.reverse_outline(session["id"], services, %{
               scene_id => "The key placement may read as forgiveness."
             })

    [card] = outline["cards"]
    assert card["scene_id"] == scene_id
    assert card["function_status"] == "interpretation"
    assert card["function"] == "The key placement may read as forgiveness."

    source = Screenplay.to_fountain(base)
    assert String.contains?(source, "Mara sets Dan's key beside his untouched coffee.")
    refute String.contains?(source, "forgiveness")
    assert ContinuationStore.head(repo).revision.content_hash == base.revision.content_hash
  end
end
