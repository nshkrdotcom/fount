defmodule Fount.Annotations do
  @moduledoc "Immutable annotation-set helpers."
  alias Fount.Annotation

  @type t :: %{optional(String.t()) => Annotation.t()}

  @spec new() :: t()
  def new, do: %{}

  @spec put(t(), Annotation.t()) :: t()
  def put(set, %Annotation{} = annotation), do: Map.put(set, annotation.id, annotation)

  @spec put_many(t(), [Annotation.t()]) :: t()
  def put_many(set, annotations), do: Enum.reduce(annotations, set, &put(&2, &1))

  @spec list(t()) :: [Annotation.t()]
  def list(set), do: Map.values(set)

  @spec for_node(t(), String.t()) :: [Annotation.t()]
  def for_node(set, node_id) do
    set |> Map.values() |> Enum.filter(&(&1.target.node_id == node_id))
  end

  @spec by_kind(t(), atom() | String.t()) :: [Annotation.t()]
  def by_kind(set, kind) do
    wanted = to_string(kind)
    set |> Map.values() |> Enum.filter(&(to_string(&1.kind) == wanted))
  end

  @spec invalidate_nodes(t(), MapSet.t(String.t())) :: t()
  def invalidate_nodes(set, node_ids) do
    Map.reject(set, fn {_id, annotation} ->
      MapSet.member?(node_ids, annotation.target.node_id) or
        Enum.any?(annotation.dependencies || [], &MapSet.member?(node_ids, &1))
    end)
  end

  @doc "Drops annotations whose target or declared node dependencies no longer exist."
  @spec prune(t(), MapSet.t(String.t()) | [String.t()]) :: t()
  def prune(set, valid_node_ids) do
    valid = if match?(%MapSet{}, valid_node_ids), do: valid_node_ids, else: MapSet.new(valid_node_ids)

    Map.reject(set, fn {_id, annotation} ->
      not MapSet.member?(valid, annotation.target.node_id) or
        Enum.any?(annotation.dependencies || [], &(not MapSet.member?(valid, &1)))
    end)
  end
end
