defmodule FountWorkshop.Candidate do
  @moduledoc "Actual screenplay branches compiled from typed change groups, with explicit selection and source attribution."
  alias Fount.{Screenplay, ID}
  alias Fount.Writing.{Schema, LocalReferences}
  alias FountWorkshop.Writing.{ChangeGroups, Footprint}

  def compile(base, proposal, opts \\ []) do
    with :ok <- Schema.validate("proposal.schema.json", proposal),
         true <- proposal["base_revision_id"] == base.revision.id or {:error, :proposal_base_mismatch},
         :ok <- origins(proposal["groups"], opts),
         {:ok, groups} <- ChangeGroups.order(proposal["groups"]),
         :ok <- citations(groups, Keyword.get(opts, :evidence, [])),
         {:ok, operations} <- ChangeGroups.operations(groups),
         {:ok, draft, changes} <- Screenplay.apply(base, operations, opts),
         true <- draft.revision.id != base.revision.id or {:error, :proposal_contains_no_change},
         :ok <- scope(base, draft, Keyword.get(opts, :editable_selection)),
         :ok <- placement(base, draft, Keyword.get(opts, :placement)),
         :ok <- target_scene_count(base, draft, opts) do
      # Resolution is an authored result of accepted groups, never a model assertion.
      all_groups = Keyword.get(opts, :all_groups, groups)
      draft = resolve_notes(draft, groups, all_groups)
      constraints = Keyword.get(opts, :constraints, [])
      checks = FountProbe.Constraints.deterministic(base, draft, constraints, Keyword.put(opts, :inventions, proposal["inventions"]))
      provenance = %{"proposal" => proposal, "allocated_ids" => changes.local_references,
        "compiled_operations" => case LocalReferences.compile(operations, reference_map: changes.local_references, screenplay_id: base.id) do {:ok, compiled, _} -> compiled; _ -> [] end,
        "evidence" => Keyword.get(opts, :evidence, []), "checks" => checks, "report_ids" => [],
        "constraints" => constraints, "unresolved_questions" => proposal["unresolved_questions"],
        "origin_by_group" => Map.new(groups, &{&1["id"], &1["origin"]})}
      {:ok, %{"id" => ID.v4(), "screenplay_id" => base.id, "base_revision_id" => base.revision.id,
        "result_revision_id" => draft.revision.id, "screenplay" => draft, "status" => "open",
        "label" => Keyword.get(opts, :label, proposal["summary"]), "strategy" => Keyword.get(opts, :strategy, %{}),
        "change_groups" => groups, "lineage" => Keyword.get(opts, :lineage, []),
        "parent_candidate_id" => Keyword.get(opts, :parent_candidate_id), "provenance" => provenance}}
    end
  end

  def select(first, second, third, opts \\ [])
  def select(id, groups, services, opts) when is_binary(id), do: FountWorkshop.CandidateAPI.select(id, groups, services, opts)
  def select(%Fount.Screenplay{} = base, candidate, group_ids, opts) do
    original = proposal(candidate)
    with {:ok, selected} <- ChangeGroups.select(original["groups"], group_ids) do
      next = Map.put(original, "groups", selected)
      compile(base, next, inherited(candidate, opts) |> Keyword.put(:all_groups, original["groups"])
        |> Keyword.put(:lineage, [%{"candidate_id" => candidate["id"], "group_ids" => group_ids, "operation" => "select"}])
        |> Keyword.put(:parent_candidate_id, candidate["id"]))
    end
  end

  def edit(id, operations, services) when is_binary(id), do: FountWorkshop.CandidateAPI.edit(id, operations, services, [])
  def edit(id, operations, services, opts) when is_binary(id), do: FountWorkshop.CandidateAPI.edit(id, operations, services, opts)
  def edit(%Fount.Screenplay{} = base, candidate, operations, actor), do: edit(base, candidate, operations, actor, [])
  def edit(base, candidate, operations, actor, opts) do
    if not is_binary(actor) or String.trim(actor) == "" do
      {:error, :missing_actor}
    else
      ops = LocalReferences.localize(operations, candidate["provenance"]["allocated_ids"] || %{})
      group = %{"id" => "writer-" <> ID.v4(), "title" => "Writer edit", "reason" => "Explicit writer revision by " <> actor,
        "depends_on" => Enum.map(candidate["change_groups"], & &1["id"]), "addresses_notes" => [], "evidence_ids" => [], "operations" => ops, "origin" => "writer_edit"}
      p = proposal(candidate) |> Map.update!("groups", &(&1 ++ [group]))
      compile(base, p, inherited(candidate, opts) |> Keyword.put(:writer_edit, true) |> Keyword.put(:actor, actor)
        |> Keyword.put(:parent_candidate_id, candidate["id"]) |> Keyword.put(:lineage, [%{"candidate_id" => candidate["id"], "operation" => "writer_edit", "actor" => actor}]))
    end
  end

  @doc "Combines explicitly selected groups or exact ranges; returns overlap choices before applying any shared edit surface."
  def combine(first, second, third, opts \\ [])
  def combine(ids, selection, services, opts) when is_list(ids), do: FountWorkshop.CandidateAPI.combine(ids, selection, services, opts)
  def combine(%Fount.Screenplay{} = base, candidates, request, opts) do
    by_id = Map.new(candidates, &{&1["id"], &1})
    with true <- is_list(request["picks"]) and request["picks"] != [] or {:error, :empty_combination},
         true <- Enum.all?(candidates, &(&1["base_revision_id"] == base.revision.id and &1["screenplay_id"] == base.id)) or {:error, :combination_base_mismatch},
         {:ok, groups, lineage} <- combine_picks(base, by_id, request["picks"]),
         {:ok, chosen} <- choose_overlaps(base, groups, Map.get(request, "choose", [])) do
      p = %{"version" => 1, "base_revision_id" => base.revision.id, "strategy_id" => nil,
        "summary" => Map.get(request, "label", "Writer-selected combination"), "groups" => chosen,
        "inventions" => Enum.flat_map(candidates, &(proposal(&1)["inventions"])), "unresolved_questions" => []}
      evidence = candidates |> Enum.flat_map(&(&1["provenance"]["evidence"] || [])) |> Enum.uniq_by(& &1["evidence_id"])
      compile(base, p, opts |> Keyword.put(:writer_edit, true) |> Keyword.put(:evidence, evidence) |> Keyword.put(:lineage, lineage))
    end
  end

  defp combine_picks(base, by_id, picks) do
    Enum.reduce_while(Enum.with_index(picks), {:ok, [], []}, fn {pick, n}, {:ok, acc, lineage} ->
      case Map.fetch(by_id, pick["candidate_id"]) do
        :error -> {:halt, {:error, :unknown_combination_candidate}}
        {:ok, source} ->
          result = if pick["ranges"], do: range_groups(base, source, pick["ranges"]), else: ChangeGroups.select(proposal(source)["groups"], pick["group_ids"])
          case result do
            {:ok, selected} ->
              prefix = "source" <> Integer.to_string(n + 1)
              names = Map.new(selected, &{&1["id"], prefix <> ":" <> &1["id"]})
              selected = LocalReferences.namespace(selected, prefix) |> Enum.map(fn g -> g |> Map.put("id", names[g["id"]]) |> Map.update!("depends_on", &Enum.map(&1, fn id -> names[id] end)) end)
              link = %{"candidate_id" => source["id"], "revision_id" => source["screenplay"].revision.id,
                "operation" => "combine", "source_group_ids" => pick["group_ids"] || [], "source_ranges" => pick["ranges"] || [], "result_group_ids" => Enum.map(selected, & &1["id"])}
              {:cont, {:ok, acc ++ selected, lineage ++ [link]}}
            error -> {:halt, error}
          end
      end
    end)
  end

  defp range_groups(base, source, ranges) when is_list(ranges) and ranges != [] do
    Enum.reduce_while(Enum.with_index(ranges), {:ok, []}, fn {range, n}, {:ok, groups} ->
      with %{"source" => %{"kind" => "element"} = from, "target" => %{"kind" => "element"} = to} <- range,
           {:ok, value} <- Fount.Target.resolve(source["screenplay"], from),
           {:ok, _} <- Fount.Target.resolve(base, to),
           {:ok, text} <- extract(value.text, from["span"]) do
        op = %{"kind" => "replace_text", "target" => to, "value" => text}
        group = %{"id" => "range-#{n}", "title" => "Selected passage", "reason" => "Writer-selected exact source range", "depends_on" => [], "addresses_notes" => [], "evidence_ids" => [], "operations" => [op], "origin" => "writer_edit"}
        {:cont, {:ok, groups ++ [group]}}
      else _ -> {:halt, {:error, :invalid_combination_range}} end
    end)
  end
  defp range_groups(_, _, _), do: {:error, :empty_ranges}
  defp extract(text, nil), do: {:ok, text}
  defp extract(text, span), do: Fount.Writing.UTF8Span.extract(text, span)

  defp choose_overlaps(base, groups, choices) do
    overlaps = Footprint.overlaps(base, groups)
    ids = Enum.map(groups, & &1["id"])
    cond do
      not is_list(choices) or Enum.any?(choices, &(&1 not in ids)) -> {:error, :invalid_overlap_choice}
      overlaps == [] -> {:ok, groups}
      Enum.any?(overlaps, fn o -> Enum.count([o["left"], o["right"]], &(&1 in choices)) != 1 end) -> {:error, {:overlapping_selections, overlaps}}
      true ->
        losers = overlaps |> Enum.flat_map(fn o -> Enum.reject([o["left"], o["right"]], &(&1 in choices)) end) |> MapSet.new()
        selected = Enum.reject(groups, &MapSet.member?(losers, &1["id"]))
        ChangeGroups.select(groups, Enum.map(selected, & &1["id"]))
    end
  end

  @doc "Checks the actual branch and, when requested, compares two real same-settings PDF files."
  def check(base, candidate, services, opts \\ []) do
    constraints = candidate["provenance"]["constraints"] || []
    {layout, layout_reports, layout_errors} = case FountWorkshop.Writing.Layout.compare(base, candidate, services, opts) do
      {:ok, nil, nil} -> {nil, [], []}
      {:ok, data, report} -> {data, [report], []}
      {:error, reason} -> {nil, [], [%{"code" => "layout_unavailable", "reason" => inspect(reason, limit: 10)}]}
    end
    options = opts |> Keyword.put(:base_model, base) |> Keyword.put(:layout, layout) |> Keyword.put(:inventions, proposal(candidate)["inventions"])
    with {:ok, report} <- FountProbe.Constraints.run(candidate["screenplay"], %{"constraints" => constraints}, FountWorkshop.Store.clients(services), options) do
      application_checks = candidate["provenance"]["application_checks"] || []
      report = %{report | errors: report.errors ++ layout_errors, status: if(layout_errors == [], do: report.status, else: "partial")}
      reports = [report | layout_reports]
      provenance = candidate["provenance"] |> Map.put("checks", report.data["checks"] ++ application_checks) |> Map.put("report_ids", Enum.map(reports, & &1.id))
      {:ok, Map.put(candidate, "provenance", provenance), reports}
    end
  end

  @doc "Rebase creates a new session and generated branch; it never mutates or silently retargets the old candidate."
  def rebase(id, current, resolutions, services) when is_binary(id), do: FountWorkshop.Rebase.run(id, current, resolutions, services)
  def rebase(candidate, current, request, services, opts) do
    if candidate["screenplay_id"] != current.id do
      {:error, :different_screenplay}
    else
      request = request |> Map.put("base_revision_id", current.revision.id)
      context = %{"previous_candidate_id" => candidate["id"], "previous_base_revision_id" => candidate["base_revision_id"],
        "previous_candidate_pages" => Screenplay.to_fountain(candidate["screenplay"]), "previous_proposal" => proposal(candidate)}
      FountWorkshop.Session.start(current, request, services, Keyword.put(opts, :rebase_context, context))
    end
  end

  def proposal(candidate), do: candidate["provenance"]["proposal"]
  defp inherited(c, opts), do: opts |> Keyword.put_new(:writer_edit, Enum.any?(c["change_groups"], &(&1["origin"] in ["writer_edit", "mixed"])))
    |> Keyword.put_new(:reference_map, c["provenance"]["allocated_ids"] || %{}) |> Keyword.put_new(:evidence, c["provenance"]["evidence"] || [])
    |> Keyword.put_new(:constraints, c["provenance"]["constraints"] || []) |> Keyword.put_new(:strategy, c["strategy"] || %{})
  defp origins(groups, opts) do
    if Enum.any?(groups, &(&1["origin"] in ["writer_edit", "mixed"])) and not Keyword.get(opts, :writer_edit, false), do: {:error, :model_cannot_claim_writer_origin}, else: :ok
  end
  defp citations(groups, evidence) do
    registry = Map.new(evidence, &{&1["evidence_id"], &1})
    FountProbe.Writing.Evidence.citations(Enum.flat_map(groups, & &1["evidence_ids"]), registry)
  end
  defp resolve_notes(draft, selected, all) do
    selected_ids = MapSet.new(selected, & &1["id"])
    addressed = ChangeGroups.notes_addressed(selected)
    items = Enum.reduce(addressed, draft.authored_items, fn id, acc ->
      required = for g <- all, id in g["addresses_notes"], do: g["id"]
      case acc[id] do
        %{"kind" => "note"} = note ->
          if Enum.all?(required, &MapSet.member?(selected_ids, &1)) do
            Map.put(acc, id, note |> Map.put("status", "resolved") |> Map.update("value", %{}, &Map.put(&1, "resolution", %{"group_ids" => required, "candidate_revision_id" => draft.revision.id})))
          else acc end
        _ -> acc
      end
    end)
    %{draft | authored_items: items} |> Fount.Screenplay.Model.refresh()
  end
  defp scope(_, _, nil), do: :ok
  defp scope(base, draft, selection) do
    with {:ok, allowed} <- FountProbe.Projection.selected_ids(base, selection) do
      changed = Enum.filter(base.ir.elements, fn e -> next = Fount.Query.node(draft, e.id); is_nil(next) or Map.take(next, [:text, :type, :attrs]) != Map.take(e, [:text, :type, :attrs]) end)
      outside = Enum.reject(changed, &MapSet.member?(allowed, &1.id))
      if outside == [], do: :ok, else: {:error, {:outside_editable_scope, Enum.map(outside, & &1.id)}}
    end
  end
  defp placement(_, _, nil), do: :ok
  defp placement(base, draft, %{"kind" => "between_scenes", "after_scene_id" => left, "before_scene_id" => right}) do
    a = Fount.Query.scene(draft, left); b = Fount.Query.scene(draft, right)
    ids = Enum.map(draft.ir.scenes, & &1.id)
    unchanged = a && b && Enum.all?([left, right], fn id -> s = Fount.Query.scene(base, id); s.element_ids == Fount.Query.scene(draft, id).element_ids and Enum.all?(s.element_ids, &(Fount.Query.node(base, &1).text == Fount.Query.node(draft, &1).text)) end)
    if unchanged and Enum.find_index(ids, &(&1 == right)) - Enum.find_index(ids, &(&1 == left)) > 1, do: :ok, else: {:error, :bridge_must_retain_both_neighbors_and_add_pages}
  end
  defp placement(_, _, _), do: :ok
  defp target_scene_count(_, _, opts) when not is_list(opts), do: {:error, :invalid_options}
  defp target_scene_count(base, draft, opts) do
    case Keyword.get(opts, :target_scene_count) do
      nil -> :ok
      target ->
        removed = Keyword.get(opts, :sequence_scene_ids, [])
        outside = Enum.map(base.ir.scenes, & &1.id) -- removed
        result_count = Enum.count(draft.ir.scenes, &(&1.id not in outside and not &1.omitted?))
        if result_count == target, do: :ok, else: {:error, {:wrong_rebuilt_scene_count, target, result_count}}
    end
  end
end
