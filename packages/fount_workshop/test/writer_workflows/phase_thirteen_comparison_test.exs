Code.require_file("../../support/continuation_store.ex", __DIR__)

defmodule FountWorkshop.PhaseThirteenComparisonTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.{Acceptance, Comparison, Store}
  alias FountWorkshop.TestSupport.ContinuationStore

  test "A02 compares two quiet cinematic revisions against actual pages and rejects the generic control" do
    repeated = "Not today. Not today."

    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. KITCHEN - LATE AFTERNOON",
            elements: [
              %{
                type: :action,
                text:
                  "Mara places Dan's key beside a cooling cup. She waits, then leaves without speaking."
              },
              %{type: :character, text: "DAN (V.O.)"},
              %{type: :dialogue, text: repeated}
            ]
          }
        ]
      )

    action = Enum.find(base.ir.elements, &(&1.type == :action))
    dialogue = Enum.find(base.ir.elements, &(&1.type == :dialogue))

    {:ok, visual, _} =
      Screenplay.apply(base, [
        %{
          "kind" => "replace_text",
          "target" => %{"kind" => "element", "id" => action.id},
          "value" =>
            "Mara sets Dan's key beside the cooling cup. She does not move. Steam thins. She waits until it is gone, then leaves without speaking."
        }
      ])

    {:ok, sound, _} =
      Screenplay.apply(base, [
        %{
          "kind" => "replace_text",
          "target" => %{"kind" => "element", "id" => action.id},
          "value" =>
            "Mara sets Dan's key beside the cooling cup. Offscreen, the elevator bell sounds once. In the sudden quiet, she waits, then leaves without speaking."
        }
      ])

    {:ok, generic, _} =
      Screenplay.apply(base, [
        %{
          "kind" => "replace_text",
          "target" => %{"kind" => "element", "id" => dialogue.id},
          "value" => "I forgive you, Dan, but I need more time."
        }
      ])

    pin = %{
      "constraint_id" => "voice-protection:not-today",
      "kind" => "pin_text",
      "severity" => "required",
      "evaluation" => "deterministic",
      "status" => "pass"
    }

    visual_candidate = candidate(base, visual, "visual", [pin])
    sound_candidate = candidate(base, sound, "sound-space", [pin])
    generic_candidate = candidate(base, generic, "generic-control", [])

    visual_comparison = Comparison.compare(base, visual_candidate)
    sound_comparison = Comparison.compare(base, sound_candidate)
    generic_comparison = Comparison.compare(base, generic_candidate)

    assert visual_comparison["language_changes"] == []
    assert sound_comparison["language_changes"] == []
    assert visual_comparison["dialogue_delta"] == %{"added" => 0, "removed" => 0, "modified" => 0}
    assert sound_comparison["dialogue_delta"] == %{"added" => 0, "removed" => 0, "modified" => 0}

    assert Enum.any?(
             visual_comparison["action_changes"],
             &String.contains?(&1["after"], "Steam thins")
           )

    assert Enum.any?(
             sound_comparison["action_changes"],
             &String.contains?(&1["after"], "Offscreen, the elevator bell")
           )

    assert [protected] = visual_comparison["protected_text_checks"]
    assert protected["status"] == "pass"
    assert generic_comparison["generator_claim_is_evidence"] == false

    assert Enum.any?(
             generic_comparison["language_changes"],
             &String.contains?(&1["after"], "I forgive you")
           )

    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)
    store = %Store{repo: repo, module: ContinuationStore}
    session_id = "phase-13-a02-demo"
    assert {:ok, saved} = Store.call(store, :save_candidate, [session_id, generic_candidate])
    assert {:ok, rejected} = Acceptance.reject(saved["id"], "writer", %{store: store})
    assert rejected["decision"] == "rejected"
  end

  defp candidate(base, screenplay, label, checks) do
    %{
      "id" => Fount.ID.v4(),
      "screenplay_id" => base.id,
      "base_revision_id" => base.revision.id,
      "result_revision_id" => screenplay.revision.id,
      "screenplay" => screenplay,
      "status" => "open",
      "label" => label,
      "strategy" => %{"title" => label},
      "change_groups" => [],
      "lineage" => [],
      "provenance" => %{
        "proposal" => %{"summary" => "The generator says this is stronger."},
        "checks" => checks
      }
    }
  end
end
