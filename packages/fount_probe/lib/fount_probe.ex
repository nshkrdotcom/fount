defmodule FountProbe do
  @moduledoc "Screenplay-specific inspection, comparison and investigation. All observations retain exact source identity."
  alias Fount.Screenplay.Model
  alias FountProbe.Catalog
  alias FountProbe.Report
  def tools, do: Catalog.tools()

  def run(model, tool, params, clients \\ %{}, opts \\ []) do
    with :ok <- Catalog.validate(model, tool, params) do
      dispatch(model, tool, params, clients, opts)
    end
  rescue
    error in [ArgumentError, KeyError, FunctionClauseError, MatchError, BadMapError] ->
      {:error, {:invalid_probe_request, error.__struct__}}
  end

  def execute(model, requests, clients, opts \\ []) when is_list(requests) do
    ids = Enum.map(requests, & &1["id"])

    if Enum.any?(ids, &(not is_binary(&1) or &1 == "")) or length(ids) != length(Enum.uniq(ids)) do
      {:error, :invalid_or_duplicate_request_id}
    else
      reports = Enum.map(requests, &run_request(model, &1, clients, opts))

      {:ok, reports}
    end
  end

  defp run_request(model, request, clients, opts) do
    report =
      case run(model, request["tool"], request["params"], clients, opts) do
        {:ok, result} -> result
        {:error, reason} -> Report.failure(model, request["tool"], request["params"], reason)
      end

    %{report | provenance: Map.put(report.provenance, "request_id", request["id"])}
  end

  def compare(before, after_model, constraints, clients, opts \\ []) do
    FountProbe.Comparison.compare(
      before,
      %{
        "before_revision_id" => before.revision.id,
        "after_revision_id" => after_model.revision.id,
        "constraints" => constraints
      },
      clients,
      Keyword.put(opts, :models, [before, after_model])
    )
  end

  def plan(model, concern, clients, opts \\ []),
    do: FountProbe.Investigation.plan(model, concern, clients, opts)

  def explain(model, concern, reports, clients, opts \\ []),
    do: FountProbe.Investigation.explain(model, concern, reports, clients, opts)

  defp dispatch(m, "inventory", p, c, o) do
    with {:ok, units} <- FountProbe.Projection.select(m, p["selection"]),
         {:ok, inventory} <-
           FountProbe.Inventory.inspect(m,
             scene_ids:
               units |> Enum.map(& &1["scene_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
           ) do
      inventory_result(m, p, c, o, units, inventory)
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

  defp inventory_result(model, params, clients, opts, units, inventory) do
    if Map.get(params, "include_summaries", true) do
      with {:ok, extracted} <-
             FountProbe.Extraction.run(
               model,
               %{"selection" => params["selection"], "kinds" => ["events"]},
               clients,
               opts
             ) do
        {:ok,
         %{
           extracted
           | tool: "inventory",
             request: params,
             data: Map.put(extracted.data, "inventory", Model.plain(inventory))
         }}
      end
    else
      {:ok,
       Report.new(model, "inventory", params, %{
         data: Model.plain(inventory),
         evidence: FountProbe.Projection.evidence(units)
       })}
    end
  end
end
