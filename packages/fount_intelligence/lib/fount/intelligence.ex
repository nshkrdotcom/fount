defmodule Fount.Intelligence do
  @moduledoc "Screenplay-specific inspection, comparison and investigation. All observations retain exact source identity."
  alias Fount.Screenplay.Model
  alias Fount.Intelligence.Playbooks.Registry, as: Registry
  alias Fount.Intelligence.Reporting.Report
  alias Fount.Intelligence.Playbooks.Request
  alias Fount.Intelligence.Runner.{Resources, ResultValidation}
  def playbooks, do: Registry.list()

  def run(model, playbook, params, clients \\ %{}, opts \\ []) do
    opts = opts |> Keyword.put(:source_model, model) |> resources()
    with :ok <- Registry.validate(model, playbook, params),
         {:ok, report} <- dispatch(model, playbook, params, clients, opts) do
      ResultValidation.finish(report, model, opts)
    end
  rescue
    _ in [ArgumentError, KeyError, FunctionClauseError, MatchError, BadMapError] ->
      {:error, :invalid_playbook_request}
  end

  def execute(model, requests, clients, opts \\ []) do
    with {:ok, validated} <- Request.parse_many(model, requests) do
      opts = resources(opts)
      {:ok, Enum.map(validated, &run_request(model, &1, clients, opts))}
    end
  end

  defp run_request(model, request, clients, opts) do
    report = case run(model, request.playbook, request.params, clients, opts) do
      {:ok, result} -> result
      {:error, reason} -> Report.failure(model, request.playbook, request.params, reason)
    end
    %{report | provenance: Map.put(report.provenance, "request_id", request.id)}
  end

  def compare(before, after_model, constraints, clients, opts \\ []) do
    run(before, "compare", %{"before_revision_id" => before.revision.id,
      "after_revision_id" => after_model.revision.id, "constraints" => constraints},
      clients, Keyword.put(opts, :models, [before, after_model]))
  end

  defp resources(opts) do
    if Resources.from_options(opts), do: opts,
      else: Keyword.put(opts, :analysis_budget, Resources.new(opts))
  end

  def plan(model, concern, clients, opts \\ []),
    do: Fount.Intelligence.Playbooks.Investigation.plan(model, concern, clients, opts)

  def explain(model, concern, reports, clients, opts \\ []),
    do: Fount.Intelligence.Playbooks.Investigation.explain(model, concern, reports, clients, opts)

  defp dispatch(m, "inventory", p, c, o) do
    with {:ok, units} <- Fount.Selection.select(m, p["selection"]),
         {:ok, inventory} <-
           Fount.Inventory.inspect(m,
             scene_ids:
               units |> Enum.map(& &1["scene_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
           ) do
      inventory_result(m, p, c, o, units, inventory)
    end
  end

  defp dispatch(m, "extract_story", p, c, o), do: Fount.Intelligence.Acquisition.Extraction.run(m, p, c, o)
  defp dispatch(m, "search", p, c, o), do: Fount.Intelligence.Playbooks.Retrieval.run(m, p, c, o)
  defp dispatch(m, "check_constraints", p, c, o), do: Fount.Intelligence.Playbooks.Constraints.run(m, p, c, o)
  defp dispatch(m, "knowledge_trace", p, c, o), do: Fount.Intelligence.Playbooks.KnowledgeTrace.run(m, p, c, o)
  defp dispatch(m, "locate_boundary", p, c, o), do: Fount.Intelligence.Playbooks.KnowledgeTrace.locate(m, p, c, o)
  defp dispatch(m, "dependencies", p, c, o), do: Fount.Intelligence.Playbooks.Dependencies.run(m, p, c, o)
  defp dispatch(m, "continuity", p, c, o), do: Fount.Intelligence.Playbooks.Continuity.run(m, p, c, o)
  defp dispatch(m, "scene_mechanics", p, c, o), do: Fount.Intelligence.Playbooks.SceneMechanics.run(m, p, c, o)
  defp dispatch(m, "dialogue", p, c, o), do: Fount.Intelligence.Playbooks.Dialogue.run(m, p, c, o)
  defp dispatch(m, "voice", p, c, o), do: Fount.Intelligence.Playbooks.Voice.run(m, p, c, o)
  defp dispatch(m, "action", p, c, o), do: Fount.Intelligence.Playbooks.Action.run(m, p, c, o)
  defp dispatch(m, "compare", p, c, o), do: Fount.Intelligence.Playbooks.Comparison.compare(m, p, c, o)
  defp dispatch(m, "scene_lift", p, c, o), do: Fount.Intelligence.Playbooks.Comparison.scene_lift(m, p, c, o)
  defp dispatch(m, "ablate", p, c, o), do: Fount.Intelligence.Playbooks.Comparison.ablate(m, p, c, o)
  defp dispatch(m, "strategy_contrast", p, c, o), do: Fount.Intelligence.Playbooks.StrategyContrast.run(m, p, c, o)

  defp inventory_result(model, params, clients, opts, units, inventory) do
    if Map.get(params, "include_summaries", true) do
      with {:ok, extracted} <-
             Fount.Intelligence.Acquisition.Extraction.run(
               model,
               %{"selection" => params["selection"], "kinds" => ["events"]},
               clients,
               opts
             ) do
        {:ok,
         %{
           Report.relabel(extracted, "inventory", params)
           |
             data: Map.put(extracted.data, "inventory", Model.plain(inventory))
         }}
      end
    else
      {:ok,
       Report.new(model, "inventory", params, %{
         data: Model.plain(inventory),
         evidence: Fount.Selection.evidence(units)
       })}
    end
  end
end
