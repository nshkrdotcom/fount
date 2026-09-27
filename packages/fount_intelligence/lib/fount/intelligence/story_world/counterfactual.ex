defmodule Fount.Intelligence.StoryWorld.Counterfactual do
  @moduledoc "Counterfactual impact primitives for writer exploration. They report support changes without pretending to simulate a rewritten film."

  alias Fount.Intelligence.StoryWorld.Query
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  def remove(world, ids) do
    ids = ids |> List.wrap() |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()

    dependencies =
      Enum.flat_map(
        ids,
        &["story:#{&1}", "canonical:#{&1}", "observation:#{&1}", "evidence:#{&1}"]
      )

    affected = Query.affected_by(world, dependencies) |> Enum.reject(&(&1 in ids))

    %{
      source_revision: world.revision_id,
      removed_ids: ids,
      affected_ids: affected,
      causal_edges_removed: matching_edges(world.causal.edges, ids),
      temporal_constraints_removed: matching_constraints(world.story_time.constraints, ids),
      alternate_support: alternate_support(world, ids ++ affected),
      limitations: [
        "This is a dependency/support analysis, not generated replacement pages.",
        "Unknown chronology and competing interpretations remain unresolved rather than being guessed."
      ]
    }
  end

  defp matching_edges(edges, ids) do
    edges
    |> Map.values()
    |> Enum.filter(&(&1.id in ids or &1.from in ids or &1.to in ids or dependent?(&1, ids)))
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp matching_constraints(constraints, ids) do
    constraints
    |> Map.values()
    |> Enum.filter(&(&1.id in ids or &1.left in ids or &1.right in ids or dependent?(&1, ids)))
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp alternate_support(world, removed_or_affected) do
    removed = MapSet.new(removed_or_affected)

    world.assertions
    |> Map.values()
    |> Enum.group_by(fn assertion ->
      {value_key(assertion.subject), assertion.predicate, value_key(assertion.object),
       assertion.scope_id}
    end)
    |> Enum.flat_map(fn {_claim, assertions} ->
      removed_assertions = Enum.filter(assertions, &MapSet.member?(removed, &1.id))
      survivors = Enum.reject(assertions, &MapSet.member?(removed, &1.id))

      if removed_assertions != [] and survivors != [] do
        [
          %{
            removed_assertion_ids: Enum.map(removed_assertions, & &1.id) |> Enum.sort(),
            surviving_assertion_ids: Enum.map(survivors, & &1.id) |> Enum.sort()
          }
        ]
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.removed_assertion_ids)
  end

  defp dependent?(object, ids) do
    dependencies = Map.get(object, :dependencies, [])
    Enum.any?(ids, fn id -> "story:#{id}" in dependencies end)
  end

  defp value_key(value), do: CanonicalJSON.hash(Model.plain(value))
end
