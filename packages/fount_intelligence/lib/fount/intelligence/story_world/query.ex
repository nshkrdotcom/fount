defmodule Fount.Intelligence.StoryWorld.Query do
  @moduledoc "Pure StoryWorld query operations. Unknown chronology stays unknown and never inherits presentation order."

  alias Fount.Intelligence.StoryWorld.{Causal, DependencyIndex, StoryTime}
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  def story_time_relation(%{story_time: story_time}, left, right),
    do: StoryTime.relation(story_time, left, right)

  def state_at(world, subject, attribute, event_id, opts \\ []) do
    scope_id = Keyword.get(opts, :scope_id, Keyword.get(opts, :scope, "base"))

    candidates =
      world.state_transitions
      |> Map.values()
      |> Enum.filter(fn transition ->
        transition.scope_id == scope_id and transition.attribute == attribute and
          same_value?(transition.subject, subject) and
          applicable?(world, transition.event_id, event_id)
      end)

    latest = maximal_transitions(world, candidates)

    case latest do
      [] ->
        :unknown

      transitions ->
        grouped = Enum.group_by(transitions, &value_key(&1.to))
        evidence = transitions |> Enum.flat_map(& &1.evidence) |> uniq_evidence()

        if map_size(grouped) == 1 do
          transition = transitions |> Enum.sort_by(& &1.id) |> List.last()

          {:known,
           %{
             value: transition.to,
             transition_ids: transitions |> Enum.map(& &1.id) |> Enum.sort(),
             evidence: evidence,
             scope_id: scope_id,
             event_id: event_id
           }}
        else
          {:ambiguous,
           %{
             alternatives:
               grouped
               |> Enum.map(fn {_key, items} ->
                 %{
                   value: hd(items).to,
                   transition_ids: items |> Enum.map(& &1.id) |> Enum.sort(),
                   evidence: items |> Enum.flat_map(& &1.evidence) |> uniq_evidence()
                 }
               end)
               |> Enum.sort_by(&value_key(&1.value)),
             evidence: evidence,
             scope_id: scope_id,
             event_id: event_id
           }}
        end
    end
  end

  def facts_at(world, opts \\ []) do
    scope_id = Keyword.get(opts, :scope_id, Keyword.get(opts, :scope, "base"))
    event_id = Keyword.get(opts, :event_id)
    predicate = Keyword.get(opts, :predicate)
    subject = Keyword.get(opts, :subject, :any)

    world.assertions
    |> Map.values()
    |> Enum.filter(fn assertion ->
      assertion.scope_id == scope_id and
        (is_nil(predicate) or assertion.predicate == predicate) and
        (subject == :any or same_value?(assertion.subject, subject)) and
        assertion_applicable?(world, assertion, event_id)
    end)
    |> Enum.sort_by(& &1.id)
  end

  def knowledge_at(world, owner, event_id, opts \\ []) do
    opts = Keyword.put(opts, :event_id, event_id)

    world
    |> facts_at(opts)
    |> Enum.filter(&same_value?(&1.epistemic_owner, owner))
  end

  def causal_ancestors(%{causal: causal}, id), do: Causal.ancestors(causal, id)
  def causal_descendants(%{causal: causal}, id), do: Causal.descendants(causal, id)

  def affected_by(%{dependency_index: %DependencyIndex{} = index}, dependencies),
    do: DependencyIndex.affected_by(index, dependencies)

  def affected_by(_world, _dependencies), do: []

  def evidence_for(world, id) when is_binary(id) do
    case find_object(world, id) do
      nil -> []
      object -> Map.get(object, :evidence, []) |> uniq_evidence()
    end
  end

  def find_object(world, id) do
    collections = [
      world.entities,
      world.mentions,
      world.events,
      world.interactions,
      world.assertions,
      world.goals,
      world.commitments,
      world.state_transitions,
      world.beats,
      world.motifs,
      world.story_time.nodes,
      world.story_time.constraints,
      world.causal.edges
    ]

    Enum.find_value(collections, &Map.get(&1, id)) || Enum.find(world.conflicts, &(&1.id == id))
  end

  defp assertion_applicable?(_world, _assertion, nil), do: true
  defp assertion_applicable?(_world, %{story_time_refs: []}, _event_id), do: true

  defp assertion_applicable?(world, assertion, event_id) do
    Enum.any?(assertion.story_time_refs, fn reference ->
      applicable?(world, reference, event_id)
    end)
  end

  defp applicable?(_world, event_id, event_id), do: true

  defp applicable?(world, source_event_id, query_event_id) do
    case StoryTime.relation(world.story_time, source_event_id, query_event_id) do
      %{status: :known, relations: relations} ->
        Enum.any?(relations, &(&1 in ["before", "same_time", "meets"]))

      _ ->
        false
    end
  end

  defp maximal_transitions(world, transitions) do
    Enum.reject(transitions, fn transition ->
      Enum.any?(transitions, fn other ->
        other.id != transition.id and strictly_before?(world, transition.event_id, other.event_id)
      end)
    end)
  end

  defp strictly_before?(_world, event_id, event_id), do: false

  defp strictly_before?(world, left, right) do
    case StoryTime.relation(world.story_time, left, right) do
      %{status: :known, relations: ["before"]} -> true
      _ -> false
    end
  end

  defp same_value?(left, right), do: value_key(left) == value_key(right)
  defp value_key(value), do: CanonicalJSON.hash(Model.plain(value))

  defp uniq_evidence(evidence),
    do: evidence |> Enum.uniq_by(& &1.id) |> Enum.sort_by(& &1.id)
end
