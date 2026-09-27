defmodule Fount.Intelligence.Temporal do
  @moduledoc """
  Pure, explicitly qualified temporal views over `Fount.Intelligence.StoryWorld`.

  Presentation order and diegetic story time remain separate. Story-time views
  preserve unknown or ambiguous relations instead of manufacturing a total
  chronology from screenplay order.
  """

  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.StoryWorld.StoryTime
  alias Fount.Screenplay.Model
  alias Fount.Writing.CanonicalJSON

  @relationship_prefix "relationship."
  @resource_prefixes ["possession", "access", "resource"]
  @payoff_types ~w(pays_off resolves complicates)

  @doc "A diegetic, event-qualified character state view."
  def character_state(%StoryWorld{} = world, character, event_id, opts \\ []) do
    scope_id = scope(opts)

    attributes =
      world.state_transitions
      |> Map.values()
      |> Enum.filter(&(&1.scope_id == scope_id and same_value?(&1.subject, character)))
      |> Enum.map(& &1.attribute)
      |> Enum.uniq()
      |> Enum.sort()

    %{
      "semantics" => "diegetic_story_time_qualified",
      "scope_id" => scope_id,
      "event_id" => event_id,
      "subject" => Model.plain(character),
      "attributes" =>
        Map.new(attributes, &{&1, state_packet(world, character, &1, event_id, opts)}),
      "knowledge" => knowledge_state(world, character, event_id, opts),
      "commitments" => commitments_at(world, character, event_id, opts),
      "resources" => resource_state(world, character, event_id, opts)
    }
  end

  @doc "A directed relationship-state view. `from` and `to` are not silently symmetric."
  def relationship_state(%StoryWorld{} = world, from, to, event_id, opts \\ []) do
    scope_id = scope(opts)
    subjects = relationship_subjects(from, to)

    attributes =
      world.state_transitions
      |> Map.values()
      |> Enum.filter(fn transition ->
        transition.scope_id == scope_id and
          String.starts_with?(transition.attribute, @relationship_prefix) and
          Enum.any?(subjects, &same_value?(&1, transition.subject))
      end)
      |> Enum.map(& &1.attribute)
      |> Enum.uniq()
      |> Enum.sort()

    states =
      Map.new(attributes, fn attribute ->
        {attribute, relationship_attribute(world, subjects, attribute, event_id, opts)}
      end)

    %{
      "semantics" => "diegetic_story_time_qualified",
      "direction" => "from_to",
      "scope_id" => scope_id,
      "event_id" => event_id,
      "from" => Model.plain(from),
      "to" => Model.plain(to),
      "attributes" => states
    }
  end

  defp relationship_attribute(world, subjects, attribute, event_id, opts) do
    result =
      Enum.find_value(subjects, :unknown, fn subject ->
        case StoryWorld.state_at(world, subject, attribute, event_id, opts) do
          :unknown -> nil
          value -> value
        end
      end)

    query_packet(world, result)
  end

  @doc "Partitions event-qualified assertions for one character into explicit epistemic stances."
  def knowledge_state(%StoryWorld{} = world, character, event_id, opts \\ []) do
    assertions = StoryWorld.knowledge_at(world, character, event_id, opts)

    grouped =
      assertions
      |> Enum.group_by(&epistemic_bucket/1)
      |> Map.new(fn {bucket, items} ->
        {bucket, items |> Enum.sort_by(& &1.id) |> Enum.map(&Model.plain/1)}
      end)

    %{
      "semantics" => "diegetic_story_time_qualified",
      "scope_id" => scope(opts),
      "event_id" => event_id,
      "owner" => Model.plain(character),
      "knows" => Map.get(grouped, "knows", []),
      "believes" => Map.get(grouped, "believes", []),
      "suspects" => Map.get(grouped, "suspects", []),
      "other" => Map.get(grouped, "other", [])
    }
  end

  @doc "Commitments involving a subject that are explicitly applicable at an event."
  def commitments_at(%StoryWorld{} = world, subject, event_id, opts \\ []) do
    scope_id = scope(opts)

    world.commitments
    |> Map.values()
    |> Enum.filter(fn commitment ->
      commitment.scope_id == scope_id and related?(commitment, subject) and
        commitment_applicable?(world, commitment, event_id)
    end)
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn commitment ->
      Model.plain(commitment)
      |> Map.put("temporal_qualification", commitment_qualification(commitment))
    end)
  end

  @doc "Event-qualified possession/access/resource state without a universal character-state scalar."
  def resource_state(%StoryWorld{} = world, subject, event_id, opts \\ []) do
    prefixes = Keyword.get(opts, :resource_prefixes, @resource_prefixes)
    scope_id = scope(opts)

    attributes =
      world.state_transitions
      |> Map.values()
      |> Enum.filter(fn transition ->
        transition.scope_id == scope_id and same_value?(transition.subject, subject) and
          Enum.any?(prefixes, &attribute_prefix?(transition.attribute, &1))
      end)
      |> Enum.map(& &1.attribute)
      |> Enum.uniq()
      |> Enum.sort()

    %{
      "semantics" => "diegetic_story_time_qualified",
      "event_id" => event_id,
      "subject" => Model.plain(subject),
      "attributes" => Map.new(attributes, &{&1, state_packet(world, subject, &1, event_id, opts)})
    }
  end

  @doc "A sparse state trajectory whose ordering semantics are always declared."
  def trajectory(%StoryWorld{} = world, subject, attribute, event_ids, opts \\ [])
      when is_list(event_ids) do
    ordering = Keyword.get(opts, :ordering, :story_time)

    points =
      Enum.map(event_ids, fn event_id ->
        %{
          "event_id" => event_id,
          "state" => state_packet(world, subject, attribute, event_id, opts)
        }
      end)

    ordered_points = order_trajectory(world, points, ordering)

    %{
      "semantics" => ordering_label(ordering),
      "subject" => Model.plain(subject),
      "attribute" => attribute,
      "points" => ordered_points
    }
    |> maybe_put_story_time_relations(world, event_ids, ordering)
  end

  @doc "Explicit sequence view in presentation order or partial diegetic story time."
  def sequence_view(%StoryWorld{} = world, event_ids, opts \\ []) when is_list(event_ids) do
    ids = event_ids |> Enum.uniq() |> Enum.filter(&Map.has_key?(world.events, &1))

    case Keyword.get(opts, :ordering, :presentation) do
      :presentation ->
        %{
          "semantics" => "presentation_relative",
          "events" =>
            ids
            |> Enum.map(&world.events[&1])
            |> Enum.sort_by(&presentation_key/1)
            |> Enum.map(&Model.plain/1),
          "state_transition_ids" => sequence_transition_ids(world, ids),
          "commitment_ids" => sequence_commitment_ids(world, ids)
        }

      :story_time ->
        %{
          "semantics" => "diegetic_story_time_partial",
          "events" => Enum.map(ids, fn id -> Model.plain(world.events[id]) end),
          "relations" => pairwise_relations(world, ids),
          "state_transition_ids" => sequence_transition_ids(world, ids),
          "commitment_ids" => sequence_commitment_ids(world, ids)
        }

      other ->
        {:error, {:invalid_temporal_ordering, other}}
    end
  end

  @doc "Explicit setup/payoff ledger from commitments and typed payoff causal edges."
  def setup_payoff_ledger(%StoryWorld{} = world, opts \\ []) do
    scope_id = scope(opts)

    payoff_edges =
      world.causal.edges
      |> Map.values()
      |> Enum.filter(&(&1.type in @payoff_types))
      |> Enum.group_by(& &1.from)

    setups =
      world.commitments
      |> Map.values()
      |> Enum.filter(&(&1.scope_id == scope_id))
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn commitment ->
        edges = Map.get(payoff_edges, commitment.id, []) |> Enum.sort_by(& &1.id)

        %{
          "setup_id" => commitment.id,
          "setup_kind" => commitment.kind,
          "terms" => Model.plain(commitment.terms),
          "setup_status" => commitment.status,
          "lifecycle" => if(edges == [], do: "open", else: payoff_lifecycle(edges)),
          "payoffs" => Enum.map(edges, &Model.plain/1),
          "evidence" => Model.plain(commitment.evidence),
          "dependencies" => Enum.sort(commitment.dependencies)
        }
      end)

    orphan_payoffs =
      payoff_edges
      |> Enum.reject(fn {from, _edges} -> Map.has_key?(world.commitments, from) end)
      |> Enum.flat_map(fn {from, edges} ->
        Enum.map(edges, fn edge ->
          %{
            "setup_id" => from,
            "setup_kind" => "explicit_causal_reference",
            "lifecycle" => payoff_lifecycle([edge]),
            "payoffs" => [Model.plain(edge)],
            "evidence" => Model.plain(edge.evidence),
            "dependencies" => Enum.sort(edge.dependencies)
          }
        end)
      end)
      |> Enum.sort_by(&{&1["setup_id"], &1["lifecycle"]})

    %{
      "semantics" => "diegetic_story_time_qualified",
      "scope_id" => scope_id,
      "entries" => setups ++ orphan_payoffs
    }
  end

  @doc "Dependency-driven story-time connected region; never a chronological suffix."
  def recomputation_region(%StoryWorld{} = world, changed_dependencies)
      when is_list(changed_dependencies) do
    affected_ids = StoryWorld.affected_by(world, changed_dependencies)

    seed_nodes =
      affected_ids
      |> Enum.flat_map(&story_time_nodes_for(world, &1))
      |> Enum.uniq()
      |> Enum.sort()

    nodes = StoryTime.connected_nodes(world.story_time, seed_nodes)
    objects = objects_touching_nodes(world, nodes)

    %{
      "semantics" => "story_time_connected_region",
      "changed_dependencies" =>
        changed_dependencies |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort(),
      "seed_object_ids" => affected_ids,
      "story_time_node_ids" => nodes,
      "object_ids" => objects
    }
  end

  defp state_packet(world, subject, attribute, event_id, opts),
    do: query_packet(world, StoryWorld.state_at(world, subject, attribute, event_id, opts))

  defp query_packet(_world, :unknown), do: %{"status" => "unknown", "dependencies" => []}

  defp query_packet(world, {:known, packet}) do
    packet
    |> Model.plain()
    |> Map.put("status", "known")
    |> Map.put("dependencies", transition_dependencies(world, packet.transition_ids))
  end

  defp query_packet(world, {:ambiguous, packet}) do
    ids = Enum.flat_map(packet.alternatives, & &1.transition_ids)

    packet
    |> Model.plain()
    |> Map.put("status", "ambiguous")
    |> Map.put("dependencies", transition_dependencies(world, ids))
  end

  defp transition_dependencies(world, ids) do
    ids
    |> Enum.flat_map(fn id ->
      case world.state_transitions[id] do
        nil -> []
        transition -> transition.dependencies
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp epistemic_bucket(assertion) do
    value =
      assertion.metadata["epistemic_kind"] || assertion.metadata[:epistemic_kind] ||
        assertion.stance

    case to_string(value || "") |> String.downcase() do
      value when value in ["know", "known", "knows", "knowledge", "established"] -> "knows"
      value when value in ["believe", "believes", "belief"] -> "believes"
      value when value in ["suspect", "suspects", "suspicion"] -> "suspects"
      _ -> "other"
    end
  end

  defp commitment_applicable?(_world, %{active_at: []}, _event_id), do: true

  defp commitment_applicable?(world, commitment, event_id) do
    Enum.any?(commitment.active_at, fn source_event ->
      source_event == event_id or
        applicable_relation?(StoryWorld.story_time_relation(world, source_event, event_id))
    end)
  end

  defp applicable_relation?(%{status: :known, relations: relations}),
    do: "before" in relations or "same_time" in relations or "meets" in relations

  defp applicable_relation?(_), do: false

  defp commitment_qualification(%{active_at: []}), do: "scope_qualified_not_time_limited"
  defp commitment_qualification(_), do: "event_or_story_time_qualified"

  defp related?(commitment, subject),
    do: same_value?(commitment.from, subject) or same_value?(commitment.to, subject)

  defp relationship_subjects(from, to),
    do: [
      %{"from" => Model.plain(from), "to" => Model.plain(to)},
      %{"left" => Model.plain(from), "right" => Model.plain(to)},
      [Model.plain(from), Model.plain(to)]
    ]

  defp attribute_prefix?(attribute, prefix),
    do: attribute == prefix or String.starts_with?(attribute, prefix <> ".")

  defp same_value?(left, right), do: value_key(left) == value_key(right)
  defp value_key(value), do: CanonicalJSON.hash(Model.plain(value))
  defp scope(opts), do: Keyword.get(opts, :scope_id, Keyword.get(opts, :scope, "base"))

  defp ordering_label(:presentation), do: "presentation_relative"
  defp ordering_label(:story_time), do: "diegetic_story_time_partial"
  defp ordering_label(other), do: "explicit:" <> to_string(other)

  defp order_trajectory(world, points, :presentation) do
    Enum.sort_by(points, fn point ->
      case world.events[point["event_id"]] do
        nil -> {9_999_999, 9_999_999, point["event_id"]}
        event -> presentation_key(event)
      end
    end)
  end

  defp order_trajectory(_world, points, :story_time), do: points
  defp order_trajectory(_world, points, _other), do: points

  defp maybe_put_story_time_relations(packet, world, event_ids, :story_time),
    do: Map.put(packet, "relations", pairwise_relations(world, event_ids))

  defp maybe_put_story_time_relations(packet, _world, _event_ids, _ordering), do: packet

  defp presentation_key(event) do
    case Enum.sort_by(event.presentation_points, &presentation_point_key/1) do
      [point | _] -> presentation_point_key(point)
      [] -> {9_999_999, 9_999_999, event.id}
    end
  end

  defp presentation_point_key(point),
    do:
      {point.scene_ordinal || 9_999_999, point.element_ordinal || 9_999_999,
       point.element_id || ""}

  defp pairwise_relations(world, ids) do
    for {left, index} <- Enum.with_index(ids),
        right <- Enum.drop(ids, index + 1) do
      %{
        "left" => left,
        "right" => right,
        "relation" => Model.plain(StoryWorld.story_time_relation(world, left, right))
      }
    end
  end

  defp sequence_transition_ids(world, ids) do
    id_set = MapSet.new(ids)

    world.state_transitions
    |> Map.values()
    |> Enum.filter(&MapSet.member?(id_set, &1.event_id))
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp sequence_commitment_ids(world, ids) do
    id_set = MapSet.new(ids)

    world.commitments
    |> Map.values()
    |> Enum.filter(fn commitment ->
      Enum.any?(commitment.active_at, &MapSet.member?(id_set, &1))
    end)
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp payoff_lifecycle(edges) do
    types = edges |> Enum.map(& &1.type) |> Enum.uniq() |> Enum.sort()

    cond do
      "pays_off" in types -> "paid_off"
      "resolves" in types -> "resolved"
      "complicates" in types -> "complicated"
      true -> "linked"
    end
  end

  defp story_time_nodes_for(world, id) do
    cond do
      Map.has_key?(world.story_time.nodes, id) ->
        [id]

      Map.has_key?(world.events, id) ->
        List.wrap(world.events[id].story_time_node_id)

      transition = world.state_transitions[id] ->
        List.wrap(event_node(world, transition.event_id))

      assertion = world.assertions[id] ->
        Enum.flat_map(assertion.story_time_refs, &List.wrap(event_node(world, &1)))

      commitment = world.commitments[id] ->
        Enum.flat_map(commitment.active_at, &List.wrap(event_node(world, &1)))

      constraint = world.story_time.constraints[id] ->
        [constraint.left, constraint.right]

      causal = world.causal.edges[id] ->
        Enum.flat_map([causal.from, causal.to], &story_time_nodes_for(world, &1))

      true ->
        []
    end
    |> Enum.reject(&is_nil/1)
  end

  defp event_node(world, event_id) do
    case world.events[event_id] do
      nil -> if(Map.has_key?(world.story_time.nodes, event_id), do: event_id, else: nil)
      event -> event.story_time_node_id || event.id
    end
  end

  defp objects_touching_nodes(world, nodes) do
    node_set = MapSet.new(nodes)

    ids =
      world.events
      |> Map.values()
      |> Enum.filter(&MapSet.member?(node_set, &1.story_time_node_id || &1.id))
      |> Enum.map(& &1.id)

    transition_ids =
      world.state_transitions
      |> Map.values()
      |> Enum.filter(&MapSet.member?(node_set, event_node(world, &1.event_id)))
      |> Enum.map(& &1.id)

    assertion_ids =
      world.assertions
      |> Map.values()
      |> Enum.filter(fn assertion ->
        Enum.any?(assertion.story_time_refs, &MapSet.member?(node_set, event_node(world, &1)))
      end)
      |> Enum.map(& &1.id)

    commitment_ids =
      world.commitments
      |> Map.values()
      |> Enum.filter(fn commitment ->
        Enum.any?(commitment.active_at, &MapSet.member?(node_set, event_node(world, &1)))
      end)
      |> Enum.map(& &1.id)

    constraint_ids =
      world.story_time.constraints
      |> Map.values()
      |> Enum.filter(fn constraint ->
        MapSet.member?(node_set, constraint.left) or MapSet.member?(node_set, constraint.right)
      end)
      |> Enum.map(& &1.id)

    (nodes ++ ids ++ transition_ids ++ assertion_ids ++ commitment_ids ++ constraint_ids)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
