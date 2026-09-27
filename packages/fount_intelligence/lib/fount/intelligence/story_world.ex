defmodule Fount.Intelligence.StoryWorld do
  @moduledoc """
  Pure, source-grounded interpreted story world for a screenplay revision.

  `compile/3` never acquires measurements, opens a repository, reads environment
  state, or generates prose. It receives a canonical `Fount.Screenplay` plus
  frozen `Fount.Observe.Observation` values and optional explicit replay records.

  Presentation order, partial diegetic story time, and causality remain separate.
  Unknown chronology stays unknown.
  """

  alias Fount.Intelligence.StoryWorld.{Compiler, Counterfactual, Inspection, Query, Renderer}

  @enforce_keys [:id, :screenplay_id, :revision_id]
  defstruct [
    :id,
    :screenplay_id,
    :revision_id,
    scopes: %{},
    entities: %{},
    mentions: %{},
    events: %{},
    interactions: %{},
    assertions: %{},
    goals: %{},
    commitments: %{},
    state_transitions: %{},
    beats: %{},
    motifs: %{},
    story_time: nil,
    causal: nil,
    conflicts: [],
    dependency_index: nil,
    observation_ids: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  def compile(screenplay, observations, opts \\ []), do: Compiler.compile(screenplay, observations, opts)
  def story_time_relation(world, left, right), do: Query.story_time_relation(world, left, right)
  def state_at(world, subject, attribute, event_id, opts \\ []), do: Query.state_at(world, subject, attribute, event_id, opts)
  def facts_at(world, opts \\ []), do: Query.facts_at(world, opts)
  def knowledge_at(world, owner, event_id, opts \\ []), do: Query.knowledge_at(world, owner, event_id, opts)
  def causal_ancestors(world, id), do: Query.causal_ancestors(world, id)
  def causal_descendants(world, id), do: Query.causal_descendants(world, id)
  def affected_by(world, changed_dependencies), do: Query.affected_by(world, changed_dependencies)
  def evidence_for(world, id), do: Query.evidence_for(world, id)
  def inspection_packet(world, opts \\ []), do: Inspection.packet(world, opts)
  def render_markdown(world, opts \\ []), do: Renderer.markdown(world, opts)
  def render_json(world, opts \\ []), do: Renderer.json(world, opts)
  def counterfactual_remove(world, ids), do: Counterfactual.remove(world, ids)

end
