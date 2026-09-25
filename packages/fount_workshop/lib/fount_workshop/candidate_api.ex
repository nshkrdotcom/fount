defmodule FountWorkshop.CandidateAPI do
  @moduledoc false
  alias FountWorkshop.{Store, Candidate, Session}
  def select(id, group_ids, services, opts \\ []) do
    with {:ok, c} <- Store.call(services[:store], :candidate, [id]),
         {:ok, base} <- Store.call(services[:store], :load_revision, [c["screenplay_id"], c["base_revision_id"]]),
         {:ok, selected} <- Candidate.select(base, c, group_ids, opts) do
      save_checked(base, selected, c["session_id"], services, opts)
    end
  end
  def edit(id, operations, services, opts \\ []) do
    with {:ok, c} <- Store.call(services[:store], :candidate, [id]),
         {:ok, base} <- Store.call(services[:store], :load_revision, [c["screenplay_id"], c["base_revision_id"]]),
         {:ok, edited} <- Candidate.edit(base, c, operations, Keyword.get(opts, :actor), opts) do
      save_checked(base, edited, c["session_id"], services, opts)
    end
  end
  def combine(ids, selection, services, opts \\ []) do
    with {:ok, candidates} <- load_candidates(ids, services), first = hd(candidates),
         {:ok, base} <- Store.call(services[:store], :load_revision, [first["screenplay_id"], first["base_revision_id"]]),
         {:ok, constraints} <- combined_constraints(candidates),
         {:ok, combined} <- Candidate.combine(base, candidates, selection, Keyword.put(opts, :constraints, constraints)),
         :ok <- save_join_source(base, combined, first["session_id"], selection["join"], services),
         {:ok, combined} <- joins(base, combined, selection["join"], services, opts) do
      save_checked(base, combined, first["session_id"], services, opts)
    end
  end
  def save_checked(base, candidate, session_id, services, opts) do
    with {:ok, checked, reports} <- Candidate.check(base, candidate, services, opts),
         {:ok, ids} <- Session.save_reports(reports, session_id, services, [base, checked["screenplay"]]),
         checked = put_in(checked, ["provenance", "report_ids"], ids),
         {:ok, saved} <- Store.call(services[:store], :save_candidate, [session_id, checked]) do
      {:ok, Map.put(saved, "session_id", session_id)}
    end
  end
  defp load_candidates(ids, services) when is_list(ids) and ids != [] do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} -> case Store.call(services[:store], :candidate, [id]) do {:ok, c} -> {:cont, {:ok, acc ++ [c]}}; error -> {:halt, error} end end)
  end
  defp load_candidates(_, _), do: {:error, :empty_candidates}
  defp combined_constraints(candidates) do
    cs = Enum.flat_map(candidates, &(&1["provenance"]["constraints"] || []))
    grouped = Enum.group_by(cs, & &1["id"])
    if Enum.any?(grouped, fn {_, values} -> length(Enum.uniq(values)) > 1 end), do: {:error, :conflicting_source_constraints},
      else: {:ok, Enum.uniq_by(cs, & &1["id"])}
  end

  defp save_join_source(_, _, _, nil, _), do: :ok
  defp save_join_source(base, combined, session_id, _, services) do
    report = FountProbe.Report.new(combined["screenplay"], "combination_source", %{}, %{source_revision_ids: [base.revision.id, combined["screenplay"].revision.id],
      data: %{"lineage" => combined["lineage"], "purpose" => "Immutable intermediate source for writer-selected passages before connective writing"}})
    case Session.save_reports([report], session_id, services, [base, combined["screenplay"]]) do {:ok, _} -> :ok; error -> error end
  end
  defp joins(_, combined, nil, _, _), do: {:ok, combined}
  defp joins(base, combined, %{"instruction" => instruction, "selection" => selection}, services, opts) when is_binary(instruction) do
    draft = combined["screenplay"]
    {:ok, units} = FountProbe.Projection.select(draft, %{"whole_screenplay" => true})
    {:ok, allowed} = FountProbe.Projection.selected_ids(draft, selection)
    # Every substantive selected passage is fixed while connective material is generated.
    changed = Enum.filter(draft.ir.elements, fn e -> old = Fount.Query.node(base, e.id); is_nil(old) or old.text != e.text end)
    pins = Enum.map(changed, &%{"id" => &1.id, "text" => &1.text})
    schema = Fount.Writing.Schema.inline("proposal.schema.json")
    validator = fn p ->
      with :ok <- Fount.Writing.Schema.validate(schema, p),
           true <- p["base_revision_id"] == draft.revision.id or {:error, :wrong_join_base},
           true <- Enum.all?(p["groups"], &(&1["origin"] in ["generated_text", "generated_structural_edit"])) or {:error, :invalid_join_origin},
           {:ok, ops} <- FountWorkshop.Writing.ChangeGroups.operations(p["groups"]),
           {:ok, next, _} <- Fount.Screenplay.apply(draft, ops),
           true <- Enum.all?(pins, fn pin -> e = Fount.Query.node(next, pin["id"]); e && e.text == pin["text"] end) or {:error, :selected_passage_changed},
           true <- Enum.all?(draft.ir.elements, fn e -> next_e = Fount.Query.node(next, e.id); (next_e && next_e.text == e.text) or MapSet.member?(allowed, e.id) end) or {:error, :join_outside_scope} do :ok end
    end
    prompt = "Write new connective screenplay material that makes this selected combination play continuously. The pinned selected passages must remain byte-identical, with their IDs retained. Do not 'smooth' them by rewriting them. Only the explicit join selection is editable; insertion of new connecting action/dialogue is permitted there. Output a typed proposal against this intermediate revision, no prose summary.\n" <>
      Jason.encode!(%{"instruction" => instruction, "base_revision_id" => draft.revision.id, "selection" => selection, "pins" => pins, "pages" => units, "confirmed_cast" => Fount.Screenplay.Model.plain(Map.values(draft.cast))})
    with {:ok, joins, traces} <- FountProbe.Completion.complete(services[:inference], prompt, schema, validator, opts) do
      existing = Candidate.proposal(combined)
      namespaced = Fount.Writing.LocalReferences.namespace(joins["groups"], "join")
      names = Map.new(namespaced, &{&1["id"], "join:" <> &1["id"]})
      groups = Enum.map(namespaced, fn g ->
        g |> Map.put("id", names[g["id"]]) |> Map.put("depends_on", Enum.map(existing["groups"], & &1["id"]) ++ Enum.map(g["depends_on"], &names[&1]))
          |> Map.update!("operations", &Fount.Writing.LocalReferences.localize(&1, combined["provenance"]["allocated_ids"]))
      end)
      proposal = existing |> Map.update!("groups", &(&1 ++ groups)) |> Map.update!("inventions", &(&1 ++ joins["inventions"]))
      with {:ok, final} <- Candidate.compile(base, proposal, opts |> Keyword.put(:writer_edit, true) |> Keyword.put(:reference_map, combined["provenance"]["allocated_ids"])
        |> Keyword.put(:evidence, Enum.uniq_by(combined["provenance"]["evidence"] ++ FountProbe.Projection.evidence(units), & &1["evidence_id"]))
        |> Keyword.put(:constraints, combined["provenance"]["constraints"]) |> Keyword.put(:lineage, combined["lineage"])) do
        preserved = Enum.all?(pins, fn pin -> e = Fount.Query.node(final["screenplay"], pin["id"]); e && e.text == pin["text"] end)
        if preserved do
          check = %{"constraint_id" => "selected-passages", "kind" => "selected_pin", "severity" => "required", "evaluation" => "deterministic", "status" => "pass"}
          {:ok, final |> put_in(["provenance", "application_checks"], [check]) |> put_in(["provenance", "join_completions"], traces)
            |> put_in(["provenance", "selected_pins"], pins) |> put_in(["provenance", "join_source_revision_id"], draft.revision.id)}
        else {:error, :join_failed_selected_pin_replay} end
      end
    end
  end
  defp joins(_, _, _, _, _), do: {:error, :join_requires_instruction_and_selection}
end
