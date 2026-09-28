Code.require_file("../../support/continuation_store.ex", __DIR__)

defmodule FountWorkshop.PhaseFourteenConsequenceTest do
  use ExUnit.Case, async: true

  alias Fount.Screenplay
  alias FountWorkshop.{Comparison, NoteTriage, Session, Store}
  alias FountWorkshop.TestSupport.ContinuationStore

  test "A07 links a note decision to a reveal-move candidate and exposes supported, uncertain, and unresolved consequences" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. ENTRYWAY - MORNING",
            elements: [
              %{type: :action, text: "Mara studies the locked door, unsure how Dan got in."}
            ]
          },
          %{
            heading: "INT. GARAGE - NIGHT",
            elements: [
              %{type: :action, text: "Dan finally shows Mara the spare key under the paint tin."}
            ]
          },
          %{
            heading: "EXT. BUS STOP - DAWN",
            elements: [
              %{type: :action, text: "A bus exhales at the curb. Mara does not look up."}
            ]
          }
        ]
      )

    [early, late, unrelated] = base.ir.scenes
    early_action = Fount.Query.node(base, Enum.at(early.element_ids, 1))
    late_action = Fount.Query.node(base, Enum.at(late.element_ids, 1))

    {:ok, repo} = ContinuationStore.start_link(base)
    on_exit(fn -> if Process.alive?(repo), do: Agent.stop(repo) end)
    services = %{store: %Store{repo: repo, module: ContinuationStore}}
    assert {:ok, session} = Session.open(base, request(base), services)

    assert {:ok, captured} =
             NoteTriage.capture(
               session["id"],
               [
                 %{
                   "raw" => "Move the spare-key reveal earlier.",
                   "source" => %{"label" => "Writer", "author" => "Writer"},
                   "confidentiality" => "private",
                   "reaction" => "The late reveal arrives after the lock question has gone cold.",
                   "interpretation" =>
                     "Test whether earlier audience knowledge changes the later pressure.",
                   "requested_treatment" => "Move the reveal to the entryway scene.",
                   "anchor" => %{
                     "target" => %{"kind" => "element", "id" => late_action.id},
                     "excerpt" => late_action.text
                   }
                 }
               ],
               services
             )

    [note] = captured["notes"]

    assert {:ok, _} =
             NoteTriage.decide(
               session["id"],
               note["id"],
               %{"action" => "experiment", "concern" => "accepted", "treatment" => "accepted"},
               services,
               actor: "writer"
             )

    operations = [
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => early_action.id},
        "value" => "Mara checks the spare key under the paint tin, then studies the locked door."
      },
      %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => late_action.id},
        "value" => "Dan notices the paint tin has been moved. Mara says nothing."
      }
    ]

    plan = %{
      "supported" => [
        %{
          "basis" => "supported_dependency",
          "target" => "later lockout decision",
          "why" => "The earlier scene now gives Mara the key before the later door choice."
        }
      ],
      "uncertain" => [
        %{
          "basis" => "hypothesis",
          "target" => "Dan's suspicion timing",
          "why" =>
            "The moved paint tin may make his suspicion arrive sooner, but that beat was not rewritten."
        }
      ],
      "unresolved" => [
        "Re-read the next Dan/Mara exchange for whether the moved knowledge changes subtext."
      ],
      "checked_scene_ids" => [early.id, late.id],
      "not_analyzed_scene_ids" => [unrelated.id]
    }

    assert {:ok, candidate} =
             NoteTriage.candidate(session["id"], [note["id"]], operations, services,
               actor: "writer",
               scope: "sequence",
               approved_scene_ids: [early.id, late.id],
               preserved: ["The bus-stop scene remains byte-for-byte untouched."],
               consequence_plan: plan,
               label: "Move spare-key reveal"
             )

    assert hd(candidate["change_groups"])["addresses_notes"] == [note["id"]]

    comparison = Comparison.compare(base, candidate)
    consequence = comparison["consequence_review"]

    assert consequence["status"] == "declared"
    assert consequence["scope"] == "sequence"
    assert MapSet.new(consequence["changed_scene_ids"]) == MapSet.new([early.id, late.id])
    assert consequence["unrelated_rewritten_scene_ids"] == []
    assert consequence["supported_dependencies"] == plan["supported"]
    assert consequence["uncertain_consequences"] == plan["uncertain"]
    assert consequence["unresolved_downstream_work"] == plan["unresolved"]
    assert consequence["candidate_claims_are_evidence"] == false

    assert Fount.Query.node(candidate["screenplay"], Enum.at(unrelated.element_ids, 1)).text ==
             Fount.Query.node(base, Enum.at(unrelated.element_ids, 1)).text

    assert ContinuationStore.head(repo).revision.id == base.revision.id
  end

  defp request(base) do
    %{
      "version" => 1,
      "workflow" => "notes",
      "mode" => "revise",
      "base_revision_id" => base.revision.id,
      "instruction" => "Experiment with one note and review the downstream consequences.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 1,
      "options" => %{"note_ids" => [], "external_notes" => []}
    }
  end
end
