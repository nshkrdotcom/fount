defmodule FountProbe do
  @moduledoc "Screenplay-specific inspection, comparison and investigation. All observations retain exact source identity."
  alias FountProbe.{Catalog, Report}
  def tools, do: Catalog.tools()
  defp option_coverage(report, tool, params) do
    pending = case tool do
      "extract_story" -> if Map.get(params, "adjacent_scenes", 0) > 0, do: ["adjacent_scenes"], else: []
      "knowledge_trace" -> Enum.filter(~w(behavior_element_ids intended_reveal_point), &(params[&1] not in [nil, []]))
      "dependencies" -> if params["record_report_ids"] not in [nil, []], do: ["record_report_ids"], else: []
      "continuity" -> Enum.filter(~w(record_report_ids changed_targets), &(params[&1] not in [nil, []]))
      "action" -> if params["layout_report_id"], do: ["layout_report_id"], else: []
      _ -> []
    end
    if pending == [] do
      report
    else
      %{report | status: "partial", coverage: Map.put(report.coverage, "unimplemented_options", pending),
        errors: report.errors ++ [%{"code" => "incomplete_option_implementation", "options" => pending}]}
    end
  end
  def run(model, tool, params, clients \\ %{}, opts \\ []) do
    with :ok <- Catalog.validate(model, tool, params) do
      case dispatch(model, tool, params, clients, opts) do
        {:ok, report} -> {:ok, option_coverage(report, tool, params)}
        error -> error
      end
    end
  rescue
    error in [ArgumentError, KeyError, FunctionClauseError, MatchError, BadMapError] -> {:error, {:invalid_probe_request, error.__struct__}}
  end
  def execute(model, requests, clients, opts \\ []) when is_list(requests) do
    ids = Enum.map(requests, & &1["id"])
    if Enum.any?(ids, &(not is_binary(&1) or &1 == "")) or length(ids) != length(Enum.uniq(ids)) do
      {:error, :invalid_or_duplicate_request_id}
    else
      reports = Enum.map(requests, fn request ->
        case run(model, request["tool"], request["params"], clients, opts) do
          {:ok, report} -> %{report | provenance: Map.put(report.provenance, "request_id", request["id"])}
          {:error, reason} -> Report.failure(model, request["tool"], request["params"], reason)
        end
      end)
      {:ok, reports}
    end
  end
  def compare(before, after_model, constraints, clients, opts \\ []) do
    FountProbe.Comparison.compare(before, %{"before_revision_id" => before.revision.id, "after_revision_id" => after_model.revision.id, "constraints" => constraints}, clients,
      Keyword.put(opts, :models, [before, after_model]))
  end
  def plan(model, concern, clients, opts \\ []), do: FountProbe.Investigation.plan(model, concern, clients, opts)
  def explain(model, concern, reports, clients, opts \\ []), do: FountProbe.Investigation.explain(model, concern, reports, clients, opts)
  defp dispatch(m, "inventory", p, c, o) do
    with {:ok, units} <- FountProbe.Projection.select(m, p["selection"]),
         {:ok, inventory} <- FountProbe.Inventory.inspect(m, scene_ids: units |> Enum.map(& &1["scene_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()) do
      if Map.get(p, "include_summaries", true) do
        with {:ok, extracted} <- FountProbe.Extraction.run(m, %{"selection" => p["selection"], "kinds" => ["events"]}, c, o) do
          {:ok, %{extracted | tool: "inventory", request: p, data: Map.put(extracted.data, "inventory", Fount.Screenplay.Model.plain(inventory))}}
        end
      else
        {:ok, Report.new(m, "inventory", p, %{data: Fount.Screenplay.Model.plain(inventory), evidence: FountProbe.Projection.evidence(units)})}
      end
    end
  end
  defp dispatch(m, "extract_story", p, c, o), do: FountProbe.Extraction.run(m, p, c, o)
  defp dispatch(m, "search", p, c, o), do: FountProbe.Retrieval.run(m, p, c, o)
  defp dispatch(m, "check_constraints", p, c, o), do: FountProbe.Constraints.run(m, p, c, o)
  defp dispatch(m, "knowledge_trace", p, c, o), do: FountProbe.KnowledgeTrace.run(m, p, c, o)
  defp dispatch(m, "locate_boundary", p, c, o), do: FountProbe.KnowledgeTrace.locate(m, p, c, o)
  defp dispatch(m, "dependencies", p, c, o), do: FountProbe.Dependencies.run(m, p, c, o)
  defp dispatch(m, "continuity", p, c, o), do: FountProbe.Continuity.run(m, p, c, o)
  defp dispatch(m, "scene_mechanics", p, c, o), do: FountProbe.SceneMechanics.run(m, p, c, o)
  defp dispatch(m, "dialogue", p, c, o), do: FountProbe.Dialogue.run(m, p, c, o)
  defp dispatch(m, "voice", p, c, o), do: FountProbe.Voice.run(m, p, c, o)
  defp dispatch(m, "action", p, c, o), do: FountProbe.Action.run(m, p, c, o)
  defp dispatch(m, "compare", p, c, o), do: FountProbe.Comparison.compare(m, p, c, o)
  defp dispatch(m, "scene_lift", p, c, o), do: FountProbe.Comparison.scene_lift(m, p, c, o)
  defp dispatch(m, "ablate", p, c, o), do: FountProbe.Comparison.ablate(m, p, c, o)
  defp dispatch(m, "strategy_contrast", p, c, o), do: FountProbe.StrategyContrast.run(m, p, c, o)
end
