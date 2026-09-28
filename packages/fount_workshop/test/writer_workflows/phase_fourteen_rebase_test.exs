Code.require_file("../../support/continuation_store.ex", __DIR__)

defmodule FountWorkshop.PhaseFourteenRebaseTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.{Candidate, Rebase, Session, Store}
  alias FountWorkshop.TestSupport.ContinuationStore

  test "manual concurrent edit makes the old candidate stale, rebase exposes the conflict, and undo restores exact source bytes" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. WORKSHOP - NIGHT",
            elements: [%{type: :action, text: "Mara places the spare key on the bench."}]
          }
        ]
      )

    action = Enum.find(base.ir.elements, &(&1.type == :action))
    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)
    services = %{store: %Store{repo: repo, module: ContinuationStore}}
    assert {:ok, session} = Session.open(base, request(base), services)

    assert {:ok, stale_candidate} =
             Candidate.manual(
               session["id"],
               [replace(action.id, "Mara hides the spare key behind the vise.")],
               services,
               actor: "writer",
               label: "Old branch"
             )

    assert {:ok, manual_current} =
             Candidate.manual(
               session["id"],
               [replace(action.id, "Mara gives the spare key back to Dan.")],
               services,
               actor: "writer",
               label: "Concurrent manual edit"
             )

    assert {:ok, accepted} =
             FountWorkshop.TestApproval.accept(services, manual_current["id"])

    assert {:error, {:stale_revision, current_revision}} =
             FountWorkshop.TestApproval.accept(services, stale_candidate["id"])

    assert current_revision == accepted.revision.id

    assert {:error, {:rebase_conflicts, [conflict]}} =
             Rebase.run(stale_candidate["id"], accepted, %{"choices" => %{}}, services)

    assert conflict["group_id"] == hd(stale_candidate["change_groups"])["id"]
    assert Enum.any?(conflict["surfaces"], &(&1["kind"] == "element" and &1["id"] == action.id))

    assert {:ok, restored} = Screenplay.undo(accepted, base)
    assert Screenplay.to_fountain(restored) == Screenplay.to_fountain(base)
    assert restored.id == base.id
    assert restored.revision.parent_id == accepted.revision.id
  end

  defp replace(id, text) do
    %{
      "kind" => "replace_text",
      "target" => %{"kind" => "element", "id" => id},
      "value" => text
    }
  end

  defp request(base) do
    %{
      "version" => 1,
      "workflow" => "alternatives",
      "mode" => "revise",
      "base_revision_id" => base.revision.id,
      "instruction" => "Test two explicit manual revisions.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 1,
      "options" => %{}
    }
  end
end
