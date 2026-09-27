defmodule Fount.Intelligence.StoryWorld.StoryTime do
  @moduledoc "Practical partial story-time constraint graph. It preserves ambiguity and only propagates strict before/after relations."

  alias Fount.Intelligence.StoryWorld.{Conflict, StoryTimeConstraint, StoryTimeNode}

  @relations ~w(before after meets overlaps same_time during contains starts_with ends_with)
  @converse %{
    "before" => "after",
    "after" => "before",
    "overlaps" => "overlaps",
    "same_time" => "same_time",
    "during" => "contains",
    "contains" => "during"
  }

  defmodule Graph do
    @moduledoc "Compiled partial story-time graph with source-backed conflicts."
    defstruct nodes: %{}, constraints: %{}, conflicts: []
    @type t :: %__MODULE__{}
  end

  def relations, do: @relations

  @spec build([StoryTimeNode.t()], [StoryTimeConstraint.t()]) :: Graph.t()
  def build(nodes, constraints) do
    graph = %Graph{
      nodes: Map.new(nodes, &{&1.id, &1}),
      constraints: Map.new(constraints, &{&1.id, normalize_constraint(&1)})
    }

    %{graph | conflicts: direct_conflicts(graph) ++ cycle_conflicts(graph)}
  end

  @doc "Returns :unknown or a relation packet with :known/:ambiguous status."
  def relation(%Graph{} = graph, left, right) when is_binary(left) and is_binary(right) do
    cond do
      not Map.has_key?(graph.nodes, left) or not Map.has_key?(graph.nodes, right) ->
        :unknown

      left == right ->
        %{status: :known, relations: ["same_time"], evidence: [], constraint_ids: []}

      true ->
        relation_packet(graph, left, right)
    end
  end

  def relation(_graph, _left, _right), do: :unknown

  defp relation_packet(graph, left, right) do
    direct = direct_packet(graph, left, right)

    packet =
      if match?(%{status: :contradiction}, direct),
        do: direct,
        else: cyclic_packet(graph, left, right) || direct

    case packet do
      nil -> propagated_relation(graph, left, right)
      result -> result
    end
  end

  @doc "Strict precedence ancestors. Only unambiguous before/after constraints participate."
  def before?(%Graph{} = graph, left, right), do: reachable?(strict_edges(graph), left, right)

  def unresolved_pairs(%Graph{} = graph) do
    ids = graph.nodes |> Map.keys() |> Enum.sort()

    for {left, index} <- Enum.with_index(ids),
        right <- Enum.drop(ids, index + 1),
        relation(graph, left, right) == :unknown,
        do: {left, right}
  end

  defp normalize_constraint(%StoryTimeConstraint{} = constraint) do
    relations =
      constraint.relations
      |> Enum.map(&to_string/1)
      |> Enum.filter(&(&1 in @relations))
      |> Enum.uniq()
      |> Enum.sort()

    %{constraint | relations: relations}
  end

  defp direct_packet(graph, left, right) do
    packets =
      graph.constraints
      |> Map.values()
      |> Enum.flat_map(&constraint_relations(&1, left, right))

    case packets do
      [] ->
        nil

      _ ->
        sets = Enum.map(packets, fn {relations, _constraint} -> MapSet.new(relations) end)
        intersection = Enum.reduce(tl(sets), hd(sets), &MapSet.intersection/2)
        relations = intersection |> MapSet.to_list() |> Enum.sort()
        constraints = Enum.map(packets, &elem(&1, 1))

        %{
          status: relation_status(relations),
          relations: relations,
          evidence: constraints |> Enum.flat_map(& &1.evidence) |> uniq_evidence(),
          constraint_ids: constraints |> Enum.map(& &1.id) |> Enum.uniq() |> Enum.sort()
        }
    end
  end

  defp constraint_relations(%StoryTimeConstraint{} = constraint, left, right) do
    cond do
      constraint.left == left and constraint.right == right ->
        [{constraint.relations, constraint}]

      constraint.left == right and constraint.right == left ->
        reversed = Enum.map(constraint.relations, &Map.get(@converse, &1))

        if Enum.any?(reversed, &is_nil/1),
          do: [],
          else: [{Enum.sort(reversed), constraint}]

      true ->
        []
    end
  end

  defp relation_status([]), do: :contradiction
  defp relation_status([_]), do: :known
  defp relation_status(_), do: :ambiguous

  defp cyclic_packet(graph, left, right) do
    case {strict_path(graph, left, right), strict_path(graph, right, left)} do
      {{:ok, forward}, {:ok, reverse}} ->
        constraints = forward ++ reverse

        %{
          status: :contradiction,
          relations: [],
          evidence: constraints |> Enum.flat_map(& &1.evidence) |> uniq_evidence(),
          constraint_ids: constraints |> Enum.map(& &1.id) |> Enum.uniq() |> Enum.sort()
        }

      _ ->
        nil
    end
  end

  defp propagated_relation(graph, left, right) do
    case strict_path(graph, left, right) do
      {:ok, constraints} ->
        %{
          status: :known,
          relations: ["before"],
          evidence: constraints |> Enum.flat_map(& &1.evidence) |> uniq_evidence(),
          constraint_ids: constraints |> Enum.map(& &1.id) |> Enum.uniq() |> Enum.sort()
        }

      :none ->
        case strict_path(graph, right, left) do
          {:ok, constraints} ->
            %{
              status: :known,
              relations: ["after"],
              evidence: constraints |> Enum.flat_map(& &1.evidence) |> uniq_evidence(),
              constraint_ids: constraints |> Enum.map(& &1.id) |> Enum.uniq() |> Enum.sort()
            }

          :none ->
            :unknown
        end
    end
  end

  defp strict_path(graph, from, to) do
    adjacency =
      graph.constraints
      |> Map.values()
      |> Enum.reduce(%{}, fn
        %StoryTimeConstraint{left: left, right: right, relations: ["before"]} = constraint, acc ->
          Map.update(acc, left, [{right, constraint}], &[{right, constraint} | &1])

        %StoryTimeConstraint{left: left, right: right, relations: ["after"]} = constraint, acc ->
          Map.update(acc, right, [{left, constraint}], &[{left, constraint} | &1])

        _constraint, acc ->
          acc
      end)

    path_walk(adjacency, [{from, []}], %{}, to)
  end

  defp path_walk(_adjacency, [], _seen, _target), do: :none

  defp path_walk(adjacency, [{current, path} | rest], seen, target) do
    cond do
      current == target and path != [] ->
        {:ok, Enum.reverse(path)}

      Map.has_key?(seen, current) ->
        path_walk(adjacency, rest, seen, target)

      true ->
        next =
          adjacency
          |> Map.get(current, [])
          |> Enum.sort_by(fn {node, constraint} -> {node, constraint.id} end)
          |> Enum.map(fn {node, constraint} -> {node, [constraint | path]} end)

        path_walk(adjacency, rest ++ next, Map.put(seen, current, true), target)
    end
  end

  defp strict_edges(graph) do
    graph.constraints
    |> Map.values()
    |> Enum.reduce(%{}, fn
      %StoryTimeConstraint{left: left, right: right, relations: ["before"]}, acc ->
        Map.update(acc, left, MapSet.new([right]), &MapSet.put(&1, right))

      %StoryTimeConstraint{left: left, right: right, relations: ["after"]}, acc ->
        Map.update(acc, right, MapSet.new([left]), &MapSet.put(&1, left))

      _constraint, acc ->
        acc
    end)
  end

  defp reachable?(edges, from, to), do: walk(edges, [from], %{}, to)

  defp walk(_edges, [], _seen, _target), do: false

  defp walk(edges, [current | rest], seen, target) do
    cond do
      current == target and map_size(seen) > 0 ->
        true

      Map.has_key?(seen, current) ->
        walk(edges, rest, seen, target)

      true ->
        next = Map.get(edges, current, MapSet.new()) |> MapSet.to_list()
        walk(edges, next ++ rest, Map.put(seen, current, true), target)
    end
  end

  defp direct_conflicts(%Graph{} = graph) do
    ids = graph.nodes |> Map.keys() |> Enum.sort()

    for {left, index} <- Enum.with_index(ids),
        right <- Enum.drop(ids, index + 1),
        packet = direct_packet(graph, left, right),
        packet != nil and packet.status == :contradiction do
      %Conflict{
        id: conflict_id("temporal_relation", [left, right | packet.constraint_ids]),
        kind: "temporal_contradiction",
        message: "Story-time evidence for #{left} and #{right} has no compatible relation.",
        severity: "error",
        involved_ids: [left, right | packet.constraint_ids],
        evidence: packet.evidence,
        dependencies: Enum.map(packet.constraint_ids, &"story:#{&1}")
      }
    end
  end

  defp cycle_conflicts(%Graph{} = graph) do
    edges = strict_edges(graph)

    cycle_nodes =
      graph.nodes |> Map.keys() |> Enum.filter(&reachable?(edges, &1, &1)) |> Enum.sort()

    if cycle_nodes == [] do
      []
    else
      strict_constraints =
        graph.constraints
        |> Map.values()
        |> Enum.filter(&(&1.relations in [["before"], ["after"]]))
        |> Enum.sort_by(& &1.id)

      involved_ids = cycle_nodes ++ Enum.map(strict_constraints, & &1.id)

      [
        %Conflict{
          id: conflict_id("strict_cycle", involved_ids),
          kind: "temporal_contradiction",
          message: "Strict story-time precedence contains a cycle.",
          severity: "error",
          involved_ids: involved_ids,
          evidence: strict_constraints |> Enum.flat_map(& &1.evidence) |> uniq_evidence(),
          dependencies: Enum.map(strict_constraints, &"story:#{&1.id}")
        }
      ]
    end
  end

  defp conflict_id(kind, ids),
    do: "sw_conflict_" <> Fount.ID.hash([kind, ":", Enum.join(ids, "|")])

  defp uniq_evidence(evidence) do
    evidence
    |> Enum.uniq_by(fn item -> Map.get(item, :id) || Map.get(item, "id") || inspect(item) end)
    |> Enum.sort_by(fn item -> Map.get(item, :id) || Map.get(item, "id") || inspect(item) end)
  end
end
