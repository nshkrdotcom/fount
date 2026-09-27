defmodule Fount.Intelligence.StoryWorld.Causal do
  @moduledoc "Typed causal graph that never infers story-time or presentation order from causal direction."

  alias Fount.Intelligence.StoryWorld.CausalRelation

  @types ~w(enables causes motivates prevents reveals requires pays_off complicates resolves contradicts)

  defmodule Graph do
    @moduledoc false
    defstruct edges: %{}
    @type t :: %__MODULE__{}
  end

  def types, do: @types
  def build(edges), do: %Graph{edges: Map.new(edges, &{&1.id, &1})}

  def ancestors(%Graph{} = graph, id), do: traverse(graph, id, :ancestors)
  def descendants(%Graph{} = graph, id), do: traverse(graph, id, :descendants)

  def edges_for(%Graph{} = graph, id) do
    graph.edges
    |> Map.values()
    |> Enum.filter(&(&1.from == id or &1.to == id))
    |> Enum.sort_by(& &1.id)
  end

  defp traverse(graph, id, direction) do
    adjacency =
      Enum.reduce(graph.edges, %{}, fn {_edge_id, %CausalRelation{} = edge}, acc ->
        {from, to} = if direction == :descendants, do: {edge.from, edge.to}, else: {edge.to, edge.from}
        Map.update(acc, from, MapSet.new([to]), &MapSet.put(&1, to))
      end)

    walk(adjacency, Map.get(adjacency, id, MapSet.new()) |> MapSet.to_list(), MapSet.new())
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp walk(_adjacency, [], seen), do: seen

  defp walk(adjacency, [current | rest], seen) do
    if MapSet.member?(seen, current) do
      walk(adjacency, rest, seen)
    else
      next = Map.get(adjacency, current, MapSet.new()) |> MapSet.to_list()
      walk(adjacency, next ++ rest, MapSet.put(seen, current))
    end
  end
end
