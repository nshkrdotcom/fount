defmodule FountWorkshop.CandidateAPI do
  @moduledoc false
  alias Fount.Screenplay.Model
  alias Fount.Writing.LocalReferences
  alias Fount.Writing.Schema
  alias FountWorkshop.Candidate
  alias FountWorkshop.Session
  alias FountWorkshop.Store
  alias FountWorkshop.Writing.ChangeGroups
  alias FountWorkshop.Writing.ProposalGuide

  def select(id, group_ids, services, opts \\ []) do
    with {:ok, c} <- Store.call(services[:store], :candidate, [id]),
         {:ok, base} <-
           Store.call(services[:store], :load_revision, [
             c["screenplay_id"],
             c["base_revision_id"]
           ]),
         {:ok, selected} <- Candidate.select(base, c, group_ids, opts) do
      save_checked(base, selected, c["session_id"], services, opts)
    end
  end

  def edit(id, operations, services, opts \\ []) do
    with {:ok, c} <- Store.call(services[:store], :candidate, [id]),
         {:ok, base} <-
           Store.call(services[:store], :load_revision, [
             c["screenplay_id"],
             c["base_revision_id"]
           ]),
         {:ok, edited} <- Candidate.edit(base, c, operations, Keyword.get(opts, :actor), opts) do
      save_checked(base, edited, c["session_id"], services, opts)
    end
  end

  def combine(ids, selection, services, opts \\ []) do
    with {:ok, candidates} <- load_candidates(ids, services),
         first = hd(candidates),
         {:ok, base} <-
           Store.call(services[:store], :load_revision, [
             first["screenplay_id"],
             first["base_revision_id"]
           ]),
         {:ok, constraints} <- combined_constraints(candidates),
         {:ok, combined} <-
           Candidate.combine(
             base,
             candidates,
             selection,
             Keyword.put(opts, :constraints, constraints)
           ),
         :ok <- save_join_source(base, combined, first["session_id"], selection["join"], services),
         {:ok, combined} <- joins(base, combined, selection["join"], services, opts) do
      save_checked(base, combined, first["session_id"], services, opts)
    end
  end

  def save_checked(base, candidate, session_id, services, opts) do
    with {:ok, checked, reports} <- Candidate.check(base, candidate, services, opts),
         {:ok, ids} <-
           Session.save_reports(reports, session_id, services, [base, checked["screenplay"]]),
         checked = put_in(checked, ["provenance", "report_ids"], ids),
         {:ok, saved} <- Store.call(services[:store], :save_candidate, [session_id, checked]) do
      {:ok, Map.put(saved, "session_id", session_id)}
    end
  end

  defp load_candidates(ids, services) when is_list(ids) and ids != [] do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case Store.call(services[:store], :candidate, [id]) do
        {:ok, c} -> {:cont, {:ok, acc ++ [c]}}
        error -> {:halt, error}
      end
    end)
  end

  defp load_candidates(_, _), do: {:error, :empty_candidates}

  defp combined_constraints(candidates) do
    cs = Enum.flat_map(candidates, &(&1["provenance"]["constraints"] || []))
    grouped = Enum.group_by(cs, & &1["id"])

    if Enum.any?(grouped, fn {_, values} -> length(Enum.uniq(values)) > 1 end),
      do: {:error, :conflicting_source_constraints},
      else: {:ok, Enum.uniq_by(cs, & &1["id"])}
  end

  defp save_join_source(_, _, _, nil, _), do: :ok

  defp save_join_source(base, combined, session_id, _, services) do
    report =
      FountProbe.Report.new(combined["screenplay"], "combination_source", %{}, %{
        source_revision_ids: [base.revision.id, combined["screenplay"].revision.id],
        data: %{
          "lineage" => combined["lineage"],
          "purpose" =>
            "Immutable intermediate source for writer-selected passages before connective writing"
        }
      })

    case Session.save_reports([report], session_id, services, [base, combined["screenplay"]]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp joins(_, combined, nil, _, _), do: {:ok, combined}

  defp joins(
         base,
         combined,
         %{"instruction" => instruction, "selection" => selection},
         services,
         opts
       )
       when is_binary(instruction) do
    draft = combined["screenplay"]
    {:ok, units} = FountProbe.Projection.select(draft, %{"whole_screenplay" => true})
    {:ok, allowed} = FountProbe.Projection.selected_ids(draft, selection)
    # Every substantive selected passage is fixed while connective material is generated.
    changed =
      Enum.filter(draft.ir.elements, fn e ->
        old = Fount.Query.node(base, e.id)
        is_nil(old) or old.text != e.text
      end)

    pins = Enum.map(changed, &%{"id" => &1.id, "text" => &1.text})
    schema = Schema.inline("proposal.schema.json")

    validator = &validate_join_proposal(&1, schema, draft, pins, allowed)

    prompt =
      "Write new connective screenplay material that makes this selected combination play continuously. The pinned selected passages must remain byte-identical, with their IDs retained. Do not 'smooth' them by rewriting them. Only the explicit join selection is editable; insertion of new connecting action/dialogue is permitted there. Output a typed proposal against this intermediate revision, no prose summary.\n" <>
        Jason.encode!(%{
          "instruction" => instruction,
          "base_revision_id" => draft.revision.id,
          "selection" => selection,
          "pins" => pins,
          "pages" => units,
          "confirmed_cast" => Model.plain(Map.values(draft.cast))
        })

    with {:ok, joins, traces} <-
           FountProbe.Completion.complete(
             services[:inference],
             prompt,
             schema,
             validator,
             opts
             |> Keyword.put(:force_json_text, true)
             |> Keyword.put_new(:decode_repairs, 2)
             |> Keyword.put(:schema_prompt, ProposalGuide.text())
           ) do
      compile_join_result(base, combined, joins, traces, units, pins, draft, opts)
    end
  end

  defp joins(_, _, _, _, _), do: {:error, :join_requires_instruction_and_selection}

  defp validate_join_proposal(proposal, schema, draft, pins, allowed) do
    with :ok <- Schema.validate(schema, proposal),
         true <- proposal["base_revision_id"] == draft.revision.id or {:error, :wrong_join_base},
         true <-
           Enum.all?(
             proposal["groups"],
             &(&1["origin"] in ["generated_text", "generated_structural_edit"])
           ) or {:error, :invalid_join_origin},
         {:ok, ops} <- ChangeGroups.operations(proposal["groups"]),
         {:ok, next, _} <- Fount.Screenplay.apply(draft, ops, []),
         true <- pins_preserved?(next, pins) or {:error, :selected_passage_changed},
         true <- within_join_scope?(draft, next, allowed) or {:error, :join_outside_scope} do
      :ok
    end
  end

  defp pins_preserved?(model, pins) do
    Enum.all?(pins, fn pin ->
      element = Fount.Query.node(model, pin["id"])
      element && element.text == pin["text"]
    end)
  end

  defp within_join_scope?(draft, next, allowed) do
    Enum.all?(draft.ir.elements, fn element ->
      next_element = Fount.Query.node(next, element.id)
      (next_element && next_element.text == element.text) or MapSet.member?(allowed, element.id)
    end)
  end

  defp compile_join_result(base, combined, joins, traces, units, pins, draft, opts) do
    existing = Candidate.proposal(combined)
    namespaced = LocalReferences.namespace(joins["groups"], "join")
    names = Map.new(namespaced, &{&1["id"], "join:" <> &1["id"]})

    groups =
      Enum.map(namespaced, fn g ->
        g
        |> Map.put("id", names[g["id"]])
        |> Map.put(
          "depends_on",
          Enum.map(existing["groups"], & &1["id"]) ++ Enum.map(g["depends_on"], &names[&1])
        )
        |> Map.update!(
          "operations",
          &LocalReferences.localize(&1, combined["provenance"]["allocated_ids"])
        )
      end)

    proposal =
      existing
      |> Map.update!("groups", &(&1 ++ groups))
      |> Map.update!("inventions", &(&1 ++ joins["inventions"]))

    with {:ok, final} <-
           Candidate.compile(
             base,
             proposal,
             opts
             |> Keyword.put(:writer_edit, true)
             |> Keyword.put(:reference_map, combined["provenance"]["allocated_ids"])
             |> Keyword.put(
               :evidence,
               Enum.uniq_by(
                 combined["provenance"]["evidence"] ++ FountProbe.Projection.evidence(units),
                 & &1["evidence_id"]
               )
             )
             |> Keyword.put(:constraints, combined["provenance"]["constraints"])
             |> Keyword.put(:lineage, combined["lineage"])
           ) do
      preserved =
        Enum.all?(pins, fn pin ->
          e = Fount.Query.node(final["screenplay"], pin["id"])
          e && e.text == pin["text"]
        end)

      if preserved do
        check = %{
          "constraint_id" => "selected-passages",
          "kind" => "selected_pin",
          "severity" => "required",
          "evaluation" => "deterministic",
          "status" => "pass"
        }

        {:ok,
         final
         |> put_in(["provenance", "application_checks"], [check])
         |> put_in(["provenance", "join_completions"], traces)
         |> put_in(["provenance", "selected_pins"], pins)
         |> put_in(["provenance", "join_source_revision_id"], draft.revision.id)}
      else
        {:error, :join_failed_selected_pin_replay}
      end
    end
  end
end
