defmodule Fount.Intelligence do
  @moduledoc "Screenplay-specific inspection, comparison and investigation. All observations retain exact source identity."
  alias Fount.Intelligence.Acquisition.Extraction
  alias Fount.Intelligence.Playbooks.Action
  alias Fount.Intelligence.Playbooks.Comparison
  alias Fount.Intelligence.Playbooks.Constraints
  alias Fount.Intelligence.Playbooks.Continuity
  alias Fount.Intelligence.Playbooks.Dependencies
  alias Fount.Intelligence.Playbooks.Dialogue
  alias Fount.Intelligence.Playbooks.Investigation
  alias Fount.Intelligence.Playbooks.KnowledgeTrace
  alias Fount.Intelligence.Playbooks.Registry, as: Registry
  alias Fount.Intelligence.Playbooks.Request
  alias Fount.Intelligence.Playbooks.Retrieval
  alias Fount.Intelligence.Playbooks.SceneMechanics
  alias Fount.Intelligence.Playbooks.StrategyContrast
  alias Fount.Intelligence.Playbooks.Voice
  alias Fount.Intelligence.Playbooks.{CapabilityRunner, WriterRegistry, WriterRunner}
  alias Fount.Intelligence.Reporting.{Renderer, Report, WriterPacket}
  alias Fount.Intelligence.Runner.{Resources, ResultValidation}
  alias Fount.Screenplay.Model
  def playbooks, do: Registry.list()

  @doc "Lists the ten writer-facing Phase-5 diagnosis playbooks."
  def writer_playbooks, do: WriterRegistry.list()

  @doc "Provider-free resource/context preflight for a writer-facing playbook."
  def preflight_playbook(model, playbook, request, opts \\ []),
    do: WriterRunner.preflight(model, playbook, request, opts)

  @doc "Runs the Phase-5 Observe -> pure -> contextual Observe -> pure diagnosis shell."
  def run_playbook(model, playbook, request, clients \\ %{}, opts \\ []),
    do: WriterRunner.run(model, playbook, request, clients, opts)

  @doc "Lists the four installed Phase-6 capability families."
  def capability_families, do: Fount.Intelligence.Capabilities.families()

  @doc "Provider-free preflight for one Phase-6 screenplay capability."
  def preflight_capability(model, family, request, opts \\ []),
    do: CapabilityRunner.preflight(model, family, request, opts)

  @doc "Runs one Phase-6 source-grounded capability through Observe and pure Intelligence reasoning."
  def run_capability(model, family, request, clients \\ %{}, opts \\ []),
    do: CapabilityRunner.run(model, family, request, clients, opts)

  @doc "Provider-free preflight for a Phase-6 writer playbook integration."
  def preflight_capability_playbook(model, playbook, request, opts \\ []),
    do: CapabilityRunner.preflight_playbook(model, playbook, request, opts)

  @doc "Runs a Phase-6 Scene Doctor, Character Trajectory, or Relationship Pass packet without generating pages."
  def run_capability_playbook(model, playbook, request, clients \\ %{}, opts \\ []),
    do: CapabilityRunner.run_playbook(model, playbook, request, clients, opts)

  @doc "Renders a writer result packet as deterministic Markdown or canonical JSON."
  def render_packet(%WriterPacket{} = packet, format \\ :markdown),
    do: Renderer.render(packet, format)

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
    report =
      case run(model, request.playbook, request.params, clients, opts) do
        {:ok, result} -> result
        {:error, reason} -> Report.failure(model, request.playbook, request.params, reason)
      end

    %{report | provenance: Map.put(report.provenance, "request_id", request.id)}
  end

  def compare(before, after_model, constraints, clients, opts \\ []) do
    run(
      before,
      "compare",
      %{
        "before_revision_id" => before.revision.id,
        "after_revision_id" => after_model.revision.id,
        "constraints" => constraints
      },
      clients,
      Keyword.put(opts, :models, [before, after_model])
    )
  end

  defp resources(opts) do
    if Resources.from_options(opts),
      do: opts,
      else: Keyword.put(opts, :analysis_budget, Resources.new(opts))
  end

  def plan(model, concern, clients, opts \\ []),
    do: Investigation.plan(model, concern, clients, opts)

  def explain(model, concern, reports, clients, opts \\ []),
    do: Investigation.explain(model, concern, reports, clients, opts)

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

  defp dispatch(m, "extract_story", p, c, o),
    do: Extraction.run(m, p, c, o)

  defp dispatch(m, "search", p, c, o), do: Retrieval.run(m, p, c, o)

  defp dispatch(m, "check_constraints", p, c, o),
    do: Constraints.run(m, p, c, o)

  defp dispatch(m, "knowledge_trace", p, c, o),
    do: KnowledgeTrace.run(m, p, c, o)

  defp dispatch(m, "locate_boundary", p, c, o),
    do: KnowledgeTrace.locate(m, p, c, o)

  defp dispatch(m, "dependencies", p, c, o),
    do: Dependencies.run(m, p, c, o)

  defp dispatch(m, "continuity", p, c, o),
    do: Continuity.run(m, p, c, o)

  defp dispatch(m, "scene_mechanics", p, c, o),
    do: SceneMechanics.run(m, p, c, o)

  defp dispatch(m, "dialogue", p, c, o), do: Dialogue.run(m, p, c, o)
  defp dispatch(m, "voice", p, c, o), do: Voice.run(m, p, c, o)
  defp dispatch(m, "action", p, c, o), do: Action.run(m, p, c, o)

  defp dispatch(m, "compare", p, c, o),
    do: Comparison.compare(m, p, c, o)

  defp dispatch(m, "scene_lift", p, c, o),
    do: Comparison.scene_lift(m, p, c, o)

  defp dispatch(m, "ablate", p, c, o),
    do: Comparison.ablate(m, p, c, o)

  defp dispatch(m, "strategy_contrast", p, c, o),
    do: StrategyContrast.run(m, p, c, o)

  defp inventory_result(model, params, clients, opts, units, inventory) do
    if Map.get(params, "include_summaries", true) do
      with {:ok, extracted} <-
             Extraction.run(
               model,
               %{"selection" => params["selection"], "kinds" => ["events"]},
               clients,
               opts
             ) do
        {:ok,
         %{
           Report.relabel(extracted, "inventory", params)
           | data: Map.put(extracted.data, "inventory", Model.plain(inventory))
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