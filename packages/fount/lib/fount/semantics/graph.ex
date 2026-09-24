defmodule Fount.Semantics.Graph do
  @moduledoc "Persistent-style semantic graph for entities, mentions, relations, and events."

  alias Fount.Semantics.{Entity, Event, Mention, Relation}

  defstruct entities: %{}, mentions: %{}, relations: %{}, events: %{}

  @type t :: %__MODULE__{
          entities: %{optional(String.t()) => Entity.t()},
          mentions: %{optional(String.t()) => Mention.t()},
          relations: %{optional(String.t()) => Relation.t()},
          events: %{optional(String.t()) => Event.t()}
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec put(t(), Entity.t() | Mention.t() | Relation.t() | Event.t()) :: t()
  def put(%__MODULE__{} = graph, %Entity{} = value), do: %{graph | entities: Map.put(graph.entities, value.id, value)}
  def put(%__MODULE__{} = graph, %Mention{} = value), do: %{graph | mentions: Map.put(graph.mentions, value.id, value)}
  def put(%__MODULE__{} = graph, %Relation{} = value), do: %{graph | relations: Map.put(graph.relations, value.id, value)}
  def put(%__MODULE__{} = graph, %Event{} = value), do: %{graph | events: Map.put(graph.events, value.id, value)}

  @spec entity(t(), String.t()) :: Entity.t() | nil
  def entity(%__MODULE__{} = graph, id), do: Map.get(graph.entities, id)

  @spec mentions(t(), String.t()) :: [Mention.t()]
  def mentions(%__MODULE__{} = graph, entity_id),
    do: graph.mentions |> Map.values() |> Enum.filter(&(&1.entity_id == entity_id))

  @spec neighbors(t(), String.t()) :: [Relation.t()]
  def neighbors(%__MODULE__{} = graph, entity_id) do
    graph.relations
    |> Map.values()
    |> Enum.filter(&(&1.from_id == entity_id or &1.to_id == entity_id))
  end
end
