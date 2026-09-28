Code.require_file("../../support/continuation_store.ex", __DIR__)

defmodule FountWorkshop.PhaseFourteenNotesTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.{NoteTriage, Session, Store}
  alias FountWorkshop.TestSupport.ContinuationStore

  test "A06 preserves conflicting notes and an accepted concern can reject the proposed treatment" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. KITCHEN - NIGHT",
            elements: [
              %{type: :action, text: "Mara watches the cooling cup."},
              %{type: :action, text: "Mara leaves."}
            ]
          }
        ]
      )

    leaving = Enum.find(base.ir.elements, &(&1.text == "Mara leaves."))
    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)
    services = %{store: %Store{repo: repo, module: ContinuationStore}}
    assert {:ok, session} = Session.open(base, request(base), services)

    notes = [
      note("Explain why she leaves", "Reader A", leaving.id),
      note("Keep the mystery", "Reader B", leaving.id)
    ]

    assert {:ok, captured} = NoteTriage.capture(session["id"], notes, services, actor: "writer")
    assert length(captured["notes"]) == 2
    assert [conflict] = captured["conflicts"]
    assert conflict["status"] == "potential_conflict"
    assert Enum.sort(conflict["instructions"]) == Enum.sort(["Explain why she leaves", "Keep the mystery"])

    [clarity, mystery] = captured["notes"]
    assert NoteTriage.anchor_status(clarity, base)["status"] == "exact"

    relocated =
      Screenplay.new(
        id: base.id,
        scenes: [
          %{
            heading: "INT. HALLWAY - CONTINUOUS",
            elements: [%{type: :action, text: "Mara leaves."}]
          }
        ]
      )

    assert NoteTriage.anchor_status(clarity, relocated)["status"] == "relocated_with_evidence"

    assert {:ok, decided} =
             NoteTriage.decide(
               session["id"],
               clarity["id"],
               %{
                 "action" => "experiment",
                 "concern" => "accepted",
                 "treatment" => "rejected",
                 "alternative_treatment" => "Use a physical cue instead of explanatory dialogue.",
                 "reason" => "The clarity concern is useful; the proposed explanation is too explicit."
               },
               services,
               actor: "writer"
             )

    assert decided["raw"] == "Explain why she leaves"
    assert decided["decision"]["concern"] == "accepted"
    assert decided["decision"]["treatment"] == "rejected"
    assert String.contains?(decided["decision"]["alternative_treatment"], "physical cue")

    assert {:ok, _} =
             NoteTriage.decide(
               session["id"],
               mystery["id"],
               %{"action" => "defer", "concern" => "accepted", "treatment" => "undecided"},
               services,
               actor: "writer"
             )

    split =
      Screenplay.new(
        id: base.id,
        scenes: [
          %{
            heading: "INT. KITCHEN - NIGHT",
            elements: [%{type: :action, text: "Mara leaves."}]
          },
          %{
            heading: "INT. HALLWAY - CONTINUOUS",
            elements: [%{type: :action, text: "Mara leaves."}]
          }
        ]
      )

    assert {:ok, reanchored} =
             NoteTriage.reanchor(session["id"], clarity["id"], split, services, actor: "writer")

    assert reanchored["current_anchor"]["status"] == "ambiguous"
    assert length(reanchored["current_anchor"]["candidate_targets"]) == 2
    assert reanchored["draft"]["revision_id"] == base.revision.id
    assert reanchored["source"]["label"] == "Reader A"

    orphaned =
      Screenplay.new(
        id: base.id,
        scenes: [
          %{
            heading: "EXT. STREET - NIGHT",
            elements: [%{type: :action, text: "The door closes behind her."}]
          }
        ]
      )

    assert NoteTriage.anchor_status(reanchored, orphaned)["status"] == "orphaned"
    assert ContinuationStore.head(repo).revision.id == base.revision.id
  end

  defp note(raw, source, element_id) do
    %{
      "raw" => raw,
      "source" => %{"label" => source, "author" => source},
      "confidentiality" => "development_private",
      "reaction" => raw,
      "interpretation" => "The note expresses a reader reaction, not an objective diagnosis.",
      "requested_treatment" => raw,
      "anchor" => %{
        "target" => %{"kind" => "element", "id" => element_id},
        "excerpt" => "Mara leaves."
      }
    }
  end

  defp request(base) do
    %{
      "version" => 1,
      "workflow" => "notes",
      "mode" => "revise",
      "base_revision_id" => base.revision.id,
      "instruction" => "Triage two reader notes without merging them.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 0,
      "options" => %{"note_ids" => [], "external_notes" => []}
    }
  end
end
