defmodule FountWorkshop.CandidateContinuationTest do
  use ExUnit.Case, async: true
  alias FountWorkshop.Candidate
  defp base do
    Fount.parse!("INT. OFFICE - DAY\n\nMara keeps the key.\n\nDAN\nThe boat leaves at six.\n") |> Fount.Screenplay.from_document()
  end
  defp proposal(model, groups), do: %{"version" => 1, "base_revision_id" => model.revision.id, "strategy_id" => nil, "summary" => "A playable choice", "groups" => groups, "inventions" => [], "unresolved_questions" => []}
  defp group(id, op, deps \\ []), do: %{"id" => id, "title" => id, "reason" => "Writer choice", "depends_on" => deps, "addresses_notes" => [], "evidence_ids" => [], "operations" => [op], "origin" => "generated_text"}
  defp replace(e, text), do: %{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => e.id}, "value" => text}
  test "selection remains on the original base and requires explicit dependency closure" do
    m = base(); a = Enum.find(m.ir.elements, &(&1.type == :action)); d = Enum.find(m.ir.elements, &(&1.type == :dialogue))
    p = proposal(m, [group("decision", replace(a, "Mara gives him the key.")), group("reply", replace(d, "Keep it. You need it more."), ["decision"])])
    assert {:ok, c} = Candidate.compile(m, p)
    assert {:error, {:missing_required_groups, _}} = Candidate.select(m, c, ["reply"])
    assert {:ok, selected} = Candidate.select(m, c, ["decision"])
    assert selected["screenplay"].revision.parent_id == m.revision.id
    assert Fount.Query.node(selected["screenplay"], d.id).text == d.text
    assert selected["lineage"] != []
  end
  test "two alternatives touching the same passage require a winner" do
    m = base(); a = Enum.find(m.ir.elements, &(&1.type == :action))
    {:ok, left} = Candidate.compile(m, proposal(m, [group("a", replace(a, "Mara drops the key."))]))
    {:ok, right} = Candidate.compile(m, proposal(m, [group("b", replace(a, "Mara hides the key."))]))
    picks = [%{"candidate_id" => left["id"], "group_ids" => ["a"]}, %{"candidate_id" => right["id"], "group_ids" => ["b"]}]
    assert {:error, {:overlapping_selections, overlaps}} = Candidate.combine(m, [left, right], %{"picks" => picks})
    winner = hd(overlaps)["left"]
    assert {:ok, combined} = Candidate.combine(m, [left, right], %{"picks" => picks, "choose" => [winner]})
    assert combined["screenplay"].revision.parent_id == m.revision.id
    assert combined["id"] not in [left["id"], right["id"]]
  end
  test "writer edit replays original groups without making the old candidate its base" do
    m = base(); a = Enum.find(m.ir.elements, &(&1.type == :action))
    {:ok, c} = Candidate.compile(m, proposal(m, [group("a", replace(a, "Mara drops the key."))]))
    assert {:ok, edited} = Candidate.edit(m, c, [replace(a, "Mara catches the key before it falls.")], "Paul")
    assert edited["screenplay"].revision.parent_id == m.revision.id
    assert List.last(edited["change_groups"])["origin"] == "writer_edit"
    assert {:error, :model_cannot_claim_writer_origin} = Candidate.compile(m, edited["provenance"]["proposal"])
  end
end
