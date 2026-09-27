defmodule Fount.Intelligence.StoryWorld.DependencyIndex do
  @moduledoc "Pure reverse dependency index for connected StoryWorld recomputation."

  defstruct by_dependency: %{}, dependencies_by_object: %{}
  @type t :: %__MODULE__{}

  @collections [
    :entities,
    :mentions,
    :events,
    :interactions,
    :assertions,
    :goals,
    :commitments,
    :state_transitions,
    :beats,
    :motifs
  ]

  def build(world) do
    objects =
      Enum.flat_map(@collections, fn collection ->
        world |> Map.fetch!(collection) |> Map.values()
      end) ++
        Map.values(world.story_time.nodes) ++
        Map.values(world.story_time.constraints) ++
        Map.values(world.causal.edges) ++
        world.conflicts

    Enum.reduce(objects, %__MODULE__{}, fn object, index ->
      id = object_id(object)
      deps = object_dependencies(object)

      by_dependency =
        Enum.reduce(deps, index.by_dependency, fn dependency, acc ->
          Map.update(acc, dependency, MapSet.new([id]), &MapSet.put(&1, id))
        end)

      %{
        index
        | by_dependency: by_dependency,
          dependencies_by_object: Map.put(index.dependencies_by_object, id, deps)
      }
    end)
  end

  def affected_by(%__MODULE__{} = index, dependencies) do
    dependencies
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> walk(index, %{}, %{})
    |> Map.keys()
    |> Enum.sort()
  end

  def dependencies_for(%__MODULE__{} = index, object_id),
    do: Map.get(index.dependencies_by_object, object_id, [])

  defp walk([], _index, _seen_dependencies, affected), do: affected

  defp walk([dependency | rest], index, seen_dependencies, affected) do
    if Map.has_key?(seen_dependencies, dependency) do
      walk(rest, index, seen_dependencies, affected)
    else
      directly_affected = Map.get(index.by_dependency, dependency, MapSet.new())
      new_ids = directly_affected |> MapSet.to_list() |> Enum.reject(&Map.has_key?(affected, &1))
      next_dependencies = Enum.map(new_ids, &"story:#{&1}")

      walk(
        rest ++ next_dependencies,
        index,
        Map.put(seen_dependencies, dependency, true),
        Enum.reduce(new_ids, affected, &Map.put(&2, &1, true))
      )
    end
  end

  defp object_id(%{id: id}) when is_binary(id), do: id

  defp object_dependencies(object) do
    direct = Map.get(object, :dependencies, []) |> List.wrap() |> Enum.map(&to_string/1)
    Enum.sort(Enum.uniq(direct))
  end
end
