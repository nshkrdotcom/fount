defmodule FountWorkshop.PhaseFourteenResearchNotesDurabilityTest do
  use ExUnit.Case, async: false

  alias Fount.{ID, Persistence, Repo, Screenplay}
  alias FountWorkshop.{NoteTriage, Research, Review, Session, Store}

  setup_all do
    start_supervised!({Repo, url: System.fetch_env!("FOUNT_DATABASE_URL"), pool_size: 2})
    :ok
  end

  test "research provenance and note decisions survive a fresh database read without changing canon" do
    base =
      Screenplay.new(
        scenes: [
          %{
            heading: "INT. RECORDS ROOM - DAY",
            elements: [%{type: :action, text: "Mara leaves the copied memo on the table."}]
          }
        ]
      )

    key = "phase14-research-notes-#{ID.v4()}"
    assert {:ok, _} = Persistence.create(Repo, key, base)
    services = %{store: Store.new(Repo)}
    assert {:ok, opened} = Session.open(base, request(base), services)

    source_id = "source-#{ID.v4()}"

    assert {:ok, _} =
             Research.record(
               opened["id"],
               %{
                 "sources" => [
                   %{
                     "id" => source_id,
                     "label" => "Writer interview notes",
                     "location" => "private notebook",
                     "content" => "A witness remembers 1974 but is not certain.",
                     "confidentiality" => "private",
                     "provider_export_allowed" => false
                   }
                 ],
                 "claims" => [
                   %{
                     "id" => "claim-#{ID.v4()}",
                     "text" => "The event happened in 1974.",
                     "status" => "unverified",
                     "origin" => "source",
                     "source_id" => source_id,
                     "note" => "Memory only; not independently verified."
                   }
                 ],
                 "questions" => []
               },
               services,
               actor: "writer"
             )

    action = Enum.find(base.ir.elements, &(&1.type == :action))

    assert {:ok, captured} =
             NoteTriage.capture(
               opened["id"],
               [
                 %{
                   "raw" => "Clarify why she leaves.",
                   "source" => %{"label" => "Producer notes", "author" => "Producer"},
                   "confidentiality" => "private",
                   "reaction" => "The exit feels abrupt.",
                   "interpretation" => "The concern is clarity, not a command to add dialogue.",
                   "requested_treatment" => "Explain it in dialogue.",
                   "anchor" => %{
                     "target" => %{"kind" => "element", "id" => action.id},
                     "excerpt" => action.text
                   }
                 }
               ],
               services
             )

    [note] = captured["notes"]

    assert {:ok, _} =
             NoteTriage.decide(
               opened["id"],
               note["id"],
               %{
                 "action" => "experiment",
                 "concern" => "accepted",
                 "treatment" => "rejected",
                 "alternative_treatment" => "Try a physical hesitation instead."
               },
               services,
               actor: "writer"
             )

    scene_id = hd(base.ir.scenes).id

    operation = %{
      "kind" => "replace_text",
      "target" => %{"kind" => "element", "id" => action.id},
      "value" => "Mara reaches for the copied memo, stops, then leaves it on the table."
    }

    assert {:ok, candidate} =
             NoteTriage.candidate(opened["id"], [note["id"]], [operation], services,
               actor: "writer",
               scope: "local",
               approved_scene_ids: [scene_id],
               preserved: ["Keep the memo on the table."],
               consequence_plan: %{
                 "supported" => [],
                 "uncertain" => [
                   %{
                     "basis" => "hypothesis",
                     "target" => "exit motivation",
                     "why" =>
                       "The physical hesitation may clarify choice without explaining motive."
                   }
                 ],
                 "unresolved" => ["Ask whether the cue is legible in the next table read."],
                 "checked_scene_ids" => [scene_id],
                 "not_analyzed_scene_ids" => []
               }
             )

    assert {:ok, packet} = Review.packet(Repo, candidate["id"])
    assert packet["note_decisions"] |> hd() |> Map.fetch!("note_id") == note["id"]
    consequence = get_in(packet, ["comparison", "consequence_review"])
    assert consequence["status"] == "declared"
    assert consequence["local_scope_respected"] == true
    assert consequence["unrelated_rewritten_scene_ids"] == []

    fresh_services = %{store: Store.new(Repo)}
    assert {:ok, resumed} = Session.resume_view(opened["id"], fresh_services)
    assert [source] = Research.list(resumed)["sources"]
    assert source["trust"] == "untrusted_content"
    assert [saved_note] = NoteTriage.list(resumed)["notes"]
    assert saved_note["decision"]["concern"] == "accepted"
    assert saved_note["decision"]["treatment"] == "rejected"

    assert {:ok, head} = Persistence.load(Repo, key)
    assert head.revision.id == base.revision.id
    assert Screenplay.to_fountain(head) == Screenplay.to_fountain(base)
  end

  defp request(base) do
    %{
      "version" => 1,
      "workflow" => "notes",
      "mode" => "revise",
      "base_revision_id" => base.revision.id,
      "instruction" => "Keep research and note decisions traceable before rewriting.",
      "selection" => %{"whole_screenplay" => true},
      "constraints" => [],
      "alternatives" => 1,
      "options" => %{"note_ids" => [], "external_notes" => []}
    }
  end
end
