defmodule Fount.Intelligence.StoryWorld.Compiler do
  @moduledoc false

  alias Fount.Intelligence.StoryWorld
  alias Fount.Intelligence.StoryWorld.{
    Assertion,
    Beat,
    Causal,
    CausalRelation,
    Commitment,
    Consistency,
    DependencyIndex,
    Entity,
    Event,
    Evidence,
    Goal,
    Interaction,
    Mention,
    Motif,
    NarrativeScope,
    PresentationPoint,
    StateTransition,
    StoryTime,
    StoryTimeConstraint,
    StoryTimeNode
  }

  alias Fount.Observe.{EvidenceRef, MeasurementResult, Observation, TargetRef}
  alias Fount.Screenplay.Model

  @record_types ~w(entity event interaction assertion goal commitment state_transition beat motif story_time_node story_time_constraint causal_relation scope)
  @legacy_types %{
    "events" => "event",
    "propositions" => "assertion",
    "goals" => "goal",
    "knowledge_access" => "assertion",
    "props" => "assertion",
    "commitments" => "commitment",
    "relationships" => "assertion",
    "timeline" => "assertion"
  }

  def compile(%Fount.Screenplay{} = screenplay, observations, opts) when is_list(observations) and is_list(opts) do
    with {:ok, observation_state} <- normalize_observations(screenplay, observations),
         {:ok, supplied_evidence} <- normalize_supplied_evidence(screenplay, Keyword.get(opts, :evidence_registry, [])),
         record_sources <- collect_record_sources(observations, Keyword.get(opts, :records, [])),
         {:ok, scopes} <- collect_scopes(screenplay, record_sources, observation_state, supplied_evidence),
         {:ok, state} <- scaffold(screenplay, scopes, observation_state, supplied_evidence),
         {:ok, state} <- ingest_observation_assertions(state, observations),
         {:ok, state} <- ingest_records(state, record_sources),
         :ok <- validate_references(state),
         {:ok, world} <- finish(state) do
      {:ok, world}
    end
  end

  def compile(_screenplay, _observations, _opts), do: {:error, :invalid_story_world_input}

  defp normalize_observations(screenplay, observations) do
    Enum.reduce_while(observations, {:ok, %{by_id: %{}, evidence: %{}}}, fn observation, {:ok, acc} ->
      case validate_observation(screenplay, observation) do
        :ok ->
          evidence = Enum.map(observation.evidence, &Evidence.from_observe/1)
          evidence_map = Map.new(evidence, &{&1.id, &1})

          if Map.has_key?(acc.by_id, observation.id) do
            {:halt, {:error, {:duplicate_observation_id, observation.id}}}
          else
            {:cont,
             {:ok,
              %{
                by_id: Map.put(acc.by_id, observation.id, observation),
                evidence: Map.merge(acc.evidence, evidence_map)
              }}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_observation(
         screenplay,
         %Observation{
           id: id,
           target: %TargetRef{} = target,
           result: %MeasurementResult{},
           evidence: evidence
         }
       )
       when is_binary(id) and id != "" and is_list(evidence) do
    target_current? = target.screenplay_id == screenplay.id and target.revision_id == screenplay.revision.id

    target_exists? =
      target.kind == "semantic_subject" or
        match?({:ok, _}, Fount.Target.resolve(screenplay, TargetRef.to_map(target)))

    evidence_current? =
      Enum.all?(evidence, fn
        %EvidenceRef{screenplay_id: sid, revision_id: rid} = ref ->
          sid == screenplay.id and rid == screenplay.revision.id and
            match?({:ok, %Evidence{}}, Evidence.from_source_map(screenplay, EvidenceRef.to_map(ref)))

        _ ->
          false
      end)

    if target_current? and target_exists? and evidence_current?,
      do: :ok,
      else: {:error, {:stale_or_invalid_observation, id}}
  end

  defp validate_observation(_screenplay, observation) do
    id = if is_map(observation), do: Map.get(observation, :id), else: nil
    {:error, {:invalid_observation, id}}
  end

  defp normalize_supplied_evidence(screenplay, entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, acc} ->
      case normalize_evidence_item(screenplay, entry) do
        {:ok, evidence} ->
          case Map.get(acc, evidence.id) do
            nil -> {:cont, {:ok, Map.put(acc, evidence.id, evidence)}}
            ^evidence -> {:cont, {:ok, acc}}
            _other -> {:halt, {:error, {:conflicting_evidence_id, evidence.id}}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_supplied_evidence(_screenplay, _entries), do: {:error, :invalid_evidence_registry}

  defp collect_record_sources(observations, explicit_records) do
    embedded =
      Enum.flat_map(observations, fn observation ->
        observation_records(observation)
        |> Enum.map(&{&1, observation.id})
      end)

    explicit = Enum.map(List.wrap(explicit_records), &{&1, nil})
    embedded ++ explicit
  end

  defp observation_records(%Observation{} = observation) do
    metadata_records =
      Map.get(observation.metadata, "story_world_records") ||
        Map.get(observation.metadata, :story_world_records) || []

    value_records =
      case observation.result.value do
        %{} = value -> Map.get(value, "story_world_records") || Map.get(value, :story_world_records) || []
        _ -> []
      end

    List.wrap(metadata_records) ++ List.wrap(value_records)
  end

  defp collect_scopes(screenplay, record_sources, observation_state, supplied_evidence) do
    base = NarrativeScope.base()
    initial = %{base.id => base}
    registry = Map.merge(supplied_evidence, observation_state.evidence)

    result =
      Enum.reduce_while(record_sources, {:ok, initial}, fn {raw, observation_id}, {:ok, scopes} ->
        record = normalize_legacy(raw)

        candidates =
          case record_type(record) do
            "scope" -> [record]
            _ -> if(is_map(field(record, "scope")), do: [field(record, "scope")], else: [])
          end

        Enum.reduce_while(candidates, {:ok, scopes}, fn candidate, {:ok, inner} ->
          case build_scope(screenplay, candidate, observation_id, observation_state, registry) do
            {:ok, scope} ->
              case Map.get(inner, scope.id) do
                nil -> {:cont, {:ok, Map.put(inner, scope.id, scope)}}
                ^scope -> {:cont, {:ok, inner}}
                _other -> {:halt, {:error, {:conflicting_scope_definition, scope.id}}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, scopes} -> {:cont, {:ok, scopes}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with {:ok, scopes} <- result,
         :ok <- validate_scope_parents(scopes) do
      {:ok, scopes}
    end
  end

  defp build_scope(screenplay, candidate, observation_id, observation_state, registry) when is_map(candidate) do
    id = field(candidate, "id")
    kind = scalar_string(field(candidate, "scope_kind") || field(candidate, "kind"))

    with true <- is_binary(id) and id != "",
         true <- kind in NarrativeScope.kinds(),
         {:ok, evidence} <- record_evidence(screenplay, candidate, observation_id, observation_state, registry, false) do
      parent = field(candidate, "parent_id") || if(kind == "base", do: nil, else: "base")

      {:ok,
       %NarrativeScope{
         id: id,
         kind: kind,
         parent_id: parent,
         claim_status: field(candidate, "claim_status") || if(kind == "base", do: "established", else: "claimed"),
         evidence: evidence,
         metadata: plain_map(field(candidate, "metadata") || %{})
       }}
    else
      _ -> {:error, {:invalid_narrative_scope, id}}
    end
  end

  defp build_scope(_screenplay, candidate, _observation_id, _observation_state, _registry),
    do: {:error, {:invalid_narrative_scope, inspect(candidate)}}

  defp validate_scope_parents(scopes) do
    invalid =
      scopes
      |> Map.values()
      |> Enum.filter(&(&1.parent_id && not Map.has_key?(scopes, &1.parent_id)))
      |> Enum.map(& &1.id)

    if invalid == [], do: :ok, else: {:error, {:unknown_scope_parent, Enum.sort(invalid)}}
  end

  defp scaffold(screenplay, scopes, observation_state, supplied_evidence) do
    world = %StoryWorld{
      id: Fount.ID.v5(screenplay.id, ["story-world:", screenplay.revision.id]),
      screenplay_id: screenplay.id,
      revision_id: screenplay.revision.id,
      scopes: scopes,
      observation_ids: observation_state.by_id |> Map.keys() |> Enum.sort()
    }

    state = %{
      screenplay: screenplay,
      world: world,
      observation_state: observation_state,
      evidence_registry: Map.merge(supplied_evidence, observation_state.evidence),
      nodes: %{},
      constraints: %{},
      causal_edges: %{}
    }

    with {:ok, state} <- scaffold_characters(state),
         {:ok, state} <- scaffold_scenes(state) do
      {:ok, state}
    end
  end

  defp scaffold_characters(state) do
    screenplay = state.screenplay

    screenplay.cast
    |> Map.values()
    |> Enum.sort_by(&{&1.display_name, &1.id})
    |> Enum.reduce_while({:ok, state}, fn character, {:ok, acc} ->
      cast_mentions =
        screenplay.mentions
        |> Map.values()
        |> Enum.filter(&(&1.character_id == character.id))
        |> Enum.sort_by(&mention_sort_key(screenplay, &1))

      mentions = Enum.map(cast_mentions, &canonical_mention(screenplay, character.id, &1))
      evidence = mentions |> Enum.flat_map(& &1.evidence) |> uniq_evidence()

      entity = %Entity{
        id: character.id,
        kind: "character",
        name: character.display_name,
        canonical_ref: %{"kind" => "character", "id" => character.id},
        aliases: Enum.map(character.aliases || [], &Model.plain/1),
        mentions: Enum.map(mentions, & &1.id),
        evidence: evidence,
        dependencies: Enum.map(mentions, &"canonical:#{&1.target["id"]}")
      }

      world = %{
        acc.world
        | entities: Map.put(acc.world.entities, entity.id, entity),
          mentions: Enum.reduce(mentions, acc.world.mentions, &Map.put(&2, &1.id, &1))
      }

      {:cont, {:ok, %{acc | world: world}}}
    end)
  end

  defp canonical_mention(screenplay, entity_id, mention) do
    element = Fount.Query.node(screenplay, mention.element_id)
    evidence = if element, do: [Evidence.canonical_element(screenplay, element, "canonical_mention")], else: []

    %Mention{
      id: mention.id,
      entity_id: entity_id,
      target: %{
        "kind" => "element",
        "id" => mention.element_id,
        "span" => %{"byte_start" => mention.byte_start, "byte_end" => mention.byte_end}
      },
      surface: mention.surface,
      role: to_string(mention.role),
      status: to_string(mention.status),
      evidence: evidence,
      dependencies: ["canonical:#{mention.element_id}"]
    }
  end

  defp mention_sort_key(screenplay, mention), do: {element_ordinal(screenplay, mention.element_id), mention.byte_start, mention.id}

  defp scaffold_scenes(state) do
    screenplay = state.screenplay

    screenplay.ir.scenes
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, state}, fn {scene, scene_ordinal}, {:ok, acc} ->
      heading = Fount.Query.node(screenplay, scene.heading_id)
      event_id = "scene:" <> scene.id
      evidence = if heading, do: [Evidence.canonical_element(screenplay, heading, "scene_heading")], else: []
      point = presentation_point(screenplay, scene.heading_id, scene_ordinal)

      participant_ids =
        screenplay.mentions
        |> Map.values()
        |> Enum.filter(&(&1.element_id in scene.element_ids and is_binary(&1.character_id)))
        |> Enum.map(& &1.character_id)
        |> Enum.uniq()
        |> Enum.sort()

      event = %Event{
        id: event_id,
        kind: "scene",
        label: if(heading, do: heading.text, else: "Scene #{scene_ordinal}"),
        scope_id: "base",
        story_time_node_id: event_id,
        participants: %{"characters" => participant_ids},
        presentation_points: [point],
        evidence: evidence,
        dependencies: ["canonical:#{scene.id}", "canonical:#{scene.heading_id}"],
        metadata: %{"canonical_scene_id" => scene.id, "omitted" => scene.omitted?}
      }

      node = %StoryTimeNode{
        id: event_id,
        event_id: event_id,
        kind: "event",
        scope_id: "base",
        evidence: evidence,
        dependencies: ["story:#{event_id}"]
      }

      world = %{acc.world | events: Map.put(acc.world.events, event_id, event)}
      {:cont, {:ok, %{acc | world: world, nodes: Map.put(acc.nodes, node.id, node)}}}
    end)
  end

  defp ingest_observation_assertions(state, observations) do
    Enum.reduce_while(observations, {:ok, state}, fn observation, {:ok, acc} ->
      id = "observation:" <> observation.id
      evidence = Enum.map(observation.evidence, &Evidence.from_observe/1)
      point = presentation_from_target(acc.screenplay, observation.target)

      assertion = %Assertion{
        id: id,
        subject: Model.plain(observation.target),
        predicate: to_string(observation.kind),
        object: Model.plain(observation.result.value),
        stance: "measured",
        scope_id: "base",
        lifecycle: "supported",
        story_time_refs: plain_list(observation.story_time_refs),
        presentation_points: List.wrap(point),
        evidence: evidence,
        confidence: distribution_confidence(observation.result.distribution),
        dependencies:
          (["observation:#{observation.id}", "measurement:#{observation.result.id}"] ++
             Enum.map(evidence, &"evidence:#{&1.id}"))
          |> Enum.uniq()
          |> Enum.sort(),
        metadata: %{
          "measurement_result_id" => observation.result.id,
          "output_contract_id" => observation.result.output_contract_id,
          "lens_id" => observation.lens_id,
          "projection_id" => observation.projection_id
        }
      }

      if Map.has_key?(acc.world.assertions, id) do
        {:halt, {:error, {:duplicate_story_world_id, id}}}
      else
        {:cont, {:ok, %{acc | world: %{acc.world | assertions: Map.put(acc.world.assertions, id, assertion)}}}}
      end
    end)
  end

  defp ingest_records(state, record_sources) do
    record_sources
    |> Enum.map(fn {raw, observation_id} -> {normalize_legacy(raw), observation_id} end)
    |> Enum.reject(fn {record, _observation_id} -> record_type(record) == "scope" end)
    |> Enum.reduce_while({:ok, state}, fn source, {:ok, acc} ->
      case ingest_record(acc, source) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ingest_record(state, {record, observation_id}) when is_map(record) do
    case record_type(record) do
      "entity" -> build_entity(state, record, observation_id)
      "event" -> build_event(state, record, observation_id)
      "interaction" -> build_interaction(state, record, observation_id)
      "assertion" -> build_assertion(state, record, observation_id)
      "goal" -> build_goal(state, record, observation_id)
      "commitment" -> build_commitment(state, record, observation_id)
      "state_transition" -> build_state_transition(state, record, observation_id)
      "beat" -> build_beat(state, record, observation_id)
      "motif" -> build_motif(state, record, observation_id)
      "story_time_node" -> build_story_time_node(state, record, observation_id)
      "story_time_constraint" -> build_story_time_constraint(state, record, observation_id)
      "causal_relation" -> build_causal_relation(state, record, observation_id)
      nil -> {:error, {:unknown_story_world_record_type, field(record, "kind")}}
      other -> {:error, {:unknown_story_world_record_type, other}}
    end
  end

  defp ingest_record(_state, {record, _observation_id}), do: {:error, {:invalid_story_world_record, inspect(record)}}

  defp build_entity(state, record, observation_id) do
    id = record_id(state.screenplay, record, "entity")
    name = field(record, "name") || field(record, "claim")

    with true <- is_binary(name) and name != "",
         {:ok, scope_id} <- record_scope(record, state.world.scopes),
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      entity = %Entity{
        id: id,
        kind: semantic_kind(record, "entity"),
        name: name,
        canonical_ref: plain_map(field(record, "canonical_ref")),
        aliases: plain_list(field(record, "aliases")),
        evidence: evidence,
        confidence: confidence(record),
        alternatives: plain_list(field(record, "alternatives")),
        dependencies: dependencies(record, observation_id, evidence),
        metadata: Map.put(plain_map(field(record, "metadata") || %{}), "scope_id", scope_id)
      }

      put_world(state, :entities, entity)
    else
      _ -> {:error, {:invalid_story_world_entity, id}}
    end
  end

  defp build_event(state, record, observation_id) do
    id = record_id(state.screenplay, record, "event")

    with {:ok, scope_id} <- record_scope(record, state.world.scopes),
         {:ok, evidence} <- record_evidence(state, record, observation_id, true),
         {:ok, event} <- event_value(state, record, observation_id, id, scope_id, evidence) do
      node = %StoryTimeNode{
        id: id,
        event_id: id,
        kind: field(record, "time_kind") || "event",
        scope_id: scope_id,
        exact: field(record, "exact_time"),
        anchor: field(record, "time_anchor"),
        duration: field(record, "duration"),
        evidence: evidence,
        dependencies: ["story:#{id}"] ++ dependencies(record, observation_id, evidence)
      }

      with {:ok, state} <- put_world(state, :events, event) do
        {:ok, %{state | nodes: Map.put(state.nodes, id, node)}}
      end
    end
  end

  defp event_value(state, record, observation_id, id, scope_id, evidence) do
    {:ok,
     %Event{
       id: id,
       kind: semantic_kind(record, "event"),
       label: field(record, "label") || field(record, "claim"),
       scope_id: scope_id,
       story_time_node_id: id,
       participants: plain_map(field(record, "participants") || subjects_as_participants(record)),
       presentation_points: record_presentation_points(state.screenplay, record, evidence),
       evidence: evidence,
       preconditions: plain_list(field(record, "preconditions")),
       postconditions: plain_list(field(record, "postconditions")),
       certainty: confidence(record),
       alternatives: plain_list(field(record, "alternatives")),
       dependencies: dependencies(record, observation_id, evidence),
       metadata: plain_map(field(record, "metadata") || %{})
     }}
  end

  defp build_interaction(state, record, observation_id) do
    id = record_id(state.screenplay, record, "interaction")
    event_id = field(record, "event_id") || id

    with {:ok, scope_id} <- record_scope(record, state.world.scopes),
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      interaction = %Interaction{
        id: id,
        scope_id: scope_id,
        event_id: event_id,
        participants: plain_list(field(record, "participants") || field(record, "subjects")),
        objectives: plain_list(field(record, "objectives")),
        tactics: plain_list(field(record, "tactics")),
        changes: plain_map(field(record, "changes") || %{}),
        presentation_points: record_presentation_points(state.screenplay, record, evidence),
        evidence: evidence,
        confidence: confidence(record),
        alternatives: plain_list(field(record, "alternatives")),
        dependencies: dependencies(record, observation_id, evidence) ++ ["story:#{event_id}"],
        metadata: plain_map(field(record, "metadata") || %{})
      }

      with {:ok, state} <- put_world(state, :interactions, interaction) do
        if Map.has_key?(state.world.events, event_id) do
          {:ok, state}
        else
          event = %Event{
            id: event_id,
            kind: "interaction",
            label: field(record, "label") || field(record, "claim"),
            scope_id: scope_id,
            story_time_node_id: event_id,
            participants: %{"characters" => interaction.participants},
            presentation_points: interaction.presentation_points,
            evidence: evidence,
            certainty: interaction.confidence,
            alternatives: interaction.alternatives,
            dependencies: interaction.dependencies,
            metadata: %{"interaction_id" => id}
          }

          node = %StoryTimeNode{
            id: event_id,
            event_id: event_id,
            kind: "event",
            scope_id: scope_id,
            evidence: evidence,
            dependencies: ["story:#{event_id}"] ++ interaction.dependencies
          }

          with {:ok, state} <- put_world(state, :events, event) do
            {:ok, %{state | nodes: Map.put(state.nodes, event_id, node)}}
          end
        end
      end
    end
  end

  defp build_assertion(state, record, observation_id) do
    id = record_id(state.screenplay, record, "assertion")
    predicate = scalar_string(field(record, "predicate") || legacy_predicate(record))

    with true <- is_binary(predicate) and predicate != "",
         {:ok, scope_id} <- record_scope(record, state.world.scopes),
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      assertion = %Assertion{
        id: id,
        subject: Model.plain(field(record, "subject") || field(record, "subjects")),
        predicate: predicate,
        object: Model.plain(field(record, "object") || field(record, "claim")),
        stance: field(record, "stance") || "asserted",
        epistemic_owner: field(record, "epistemic_owner"),
        scope_id: scope_id,
        lifecycle: field(record, "lifecycle") || "supported",
        story_time_refs: plain_list(field(record, "story_time_refs") || field(record, "active_at")),
        presentation_points: record_presentation_points(state.screenplay, record, evidence),
        evidence: evidence,
        confidence: confidence(record),
        alternatives: plain_list(field(record, "alternatives")),
        dependencies: dependencies(record, observation_id, evidence),
        metadata: plain_map(field(record, "metadata") || %{})
      }

      put_world(state, :assertions, assertion)
    else
      _ -> {:error, {:invalid_story_world_assertion, id}}
    end
  end

  defp build_goal(state, record, observation_id) do
    id = record_id(state.screenplay, record, "goal")
    owner = field(record, "owner") || List.first(plain_list(field(record, "subjects")))
    description = field(record, "description") || field(record, "claim")

    with true <- not is_nil(owner),
         true <- is_binary(description) and description != "",
         {:ok, scope_id} <- record_scope(record, state.world.scopes),
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      goal = %Goal{
        id: id,
        owner: Model.plain(owner),
        description: description,
        scope_id: scope_id,
        level: field(record, "level") || "unspecified",
        status: field(record, "status") || "active",
        active_at: Model.plain(field(record, "active_at")),
        evidence: evidence,
        confidence: confidence(record),
        alternatives: plain_list(field(record, "alternatives")),
        dependencies: dependencies(record, observation_id, evidence),
        metadata: plain_map(field(record, "metadata") || %{})
      }

      put_world(state, :goals, goal)
    else
      _ -> {:error, {:invalid_story_world_goal, id}}
    end
  end

  defp build_commitment(state, record, observation_id) do
    id = record_id(state.screenplay, record, "commitment")

    with {:ok, scope_id} <- record_scope(record, state.world.scopes),
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      commitment = %Commitment{
        id: id,
        kind: semantic_kind(record, "commitment"),
        scope_id: scope_id,
        from: Model.plain(field(record, "from") || List.first(plain_list(field(record, "subjects")))),
        to: Model.plain(field(record, "to")),
        terms: field(record, "terms") || field(record, "claim"),
        status: field(record, "status") || "active",
        deadline: Model.plain(field(record, "deadline")),
        conditions: plain_list(field(record, "conditions")),
        active_at: plain_list(field(record, "active_at")),
        evidence: evidence,
        confidence: confidence(record),
        alternatives: plain_list(field(record, "alternatives")),
        dependencies: dependencies(record, observation_id, evidence),
        metadata: plain_map(field(record, "metadata") || %{})
      }

      put_world(state, :commitments, commitment)
    end
  end

  defp build_state_transition(state, record, observation_id) do
    id = record_id(state.screenplay, record, "state_transition")
    subject = field(record, "subject")
    attribute = field(record, "attribute")
    event_id = field(record, "event_id")

    with true <- not is_nil(subject),
         true <- is_binary(attribute) and attribute != "",
         true <- is_binary(event_id) and event_id != "",
         {:ok, scope_id} <- record_scope(record, state.world.scopes),
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      transition = %StateTransition{
        id: id,
        subject: Model.plain(subject),
        attribute: attribute,
        from: Model.plain(field(record, "from")),
        to: Model.plain(field(record, "to")),
        event_id: event_id,
        scope_id: scope_id,
        preconditions: plain_list(field(record, "preconditions")),
        postconditions: plain_list(field(record, "postconditions")),
        evidence: evidence,
        certainty: confidence(record),
        alternatives: plain_list(field(record, "alternatives")),
        dependencies: dependencies(record, observation_id, evidence) ++ ["story:#{event_id}"],
        metadata: plain_map(field(record, "metadata") || %{})
      }

      put_world(state, :state_transitions, transition)
    else
      _ -> {:error, {:invalid_story_world_state_transition, id}}
    end
  end

  defp build_beat(state, record, observation_id) do
    id = record_id(state.screenplay, record, "beat")

    with {:ok, scope_id} <- record_scope(record, state.world.scopes),
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      beat = %Beat{
        id: id,
        scope_id: scope_id,
        scene_id: field(record, "scene_id"),
        element_ids: plain_list(field(record, "element_ids")),
        summary: field(record, "summary") || field(record, "claim"),
        objective: Model.plain(field(record, "objective")),
        tactic: Model.plain(field(record, "tactic")),
        information_change: Model.plain(field(record, "information_change")),
        relationship_delta: Model.plain(field(record, "relationship_delta")),
        value_delta: Model.plain(field(record, "value_delta")),
        outcome: Model.plain(field(record, "outcome")),
        transition_reason: Model.plain(field(record, "transition_reason")),
        presentation_points: record_presentation_points(state.screenplay, record, evidence),
        evidence: evidence,
        confidence: confidence(record),
        alternatives: plain_list(field(record, "alternatives")),
        dependencies: dependencies(record, observation_id, evidence),
        metadata: plain_map(field(record, "metadata") || %{})
      }

      put_world(state, :beats, beat)
    end
  end

  defp build_motif(state, record, observation_id) do
    id = record_id(state.screenplay, record, "motif")
    label = field(record, "label") || field(record, "claim")

    with true <- is_binary(label) and label != "",
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      motif = %Motif{
        id: id,
        label: label,
        kind: semantic_kind(record, "motif"),
        occurrences: plain_list(field(record, "occurrences")),
        evidence: evidence,
        confidence: confidence(record),
        dependencies: dependencies(record, observation_id, evidence),
        metadata: plain_map(field(record, "metadata") || %{})
      }

      put_world(state, :motifs, motif)
    else
      _ -> {:error, {:invalid_story_world_motif, id}}
    end
  end

  defp build_story_time_node(state, record, observation_id) do
    id = record_id(state.screenplay, record, "story_time_node")

    with {:ok, scope_id} <- record_scope(record, state.world.scopes),
         {:ok, evidence} <- record_evidence(state, record, observation_id, false) do
      node = %StoryTimeNode{
        id: id,
        event_id: field(record, "event_id"),
        kind: field(record, "node_kind") || "interval",
        scope_id: scope_id,
        exact: Model.plain(field(record, "exact")),
        anchor: Model.plain(field(record, "anchor")),
        duration: Model.plain(field(record, "duration")),
        evidence: evidence,
        dependencies: dependencies(record, observation_id, evidence),
        metadata: plain_map(field(record, "metadata") || %{})
      }

      if Map.has_key?(state.nodes, id),
        do: {:error, {:duplicate_story_world_id, id}},
        else: {:ok, %{state | nodes: Map.put(state.nodes, id, node)}}
    end
  end

  defp build_story_time_constraint(state, record, observation_id) do
    id = record_id(state.screenplay, record, "story_time_constraint")
    left = field(record, "left")
    right = field(record, "right")
    relations =
      record
      |> field("relations")
      |> then(&(&1 || field(record, "relation")))
      |> plain_list()
      |> Enum.map(&scalar_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    with true <- is_binary(left) and left != "",
         true <- is_binary(right) and right != "",
         true <- relations != [] and Enum.all?(relations, &(&1 in StoryTime.relations())),
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      constraint = %StoryTimeConstraint{
        id: id,
        left: left,
        right: right,
        relations: relations,
        evidence: evidence,
        confidence: confidence(record),
        alternatives: plain_list(field(record, "alternatives")),
        dependencies: dependencies(record, observation_id, evidence) ++ ["story:#{left}", "story:#{right}"],
        metadata: plain_map(field(record, "metadata") || %{})
      }

      if Map.has_key?(state.constraints, id),
        do: {:error, {:duplicate_story_world_id, id}},
        else: {:ok, %{state | constraints: Map.put(state.constraints, id, constraint)}}
    else
      _ -> {:error, {:invalid_story_time_constraint, id}}
    end
  end

  defp build_causal_relation(state, record, observation_id) do
    id = record_id(state.screenplay, record, "causal_relation")
    type = semantic_kind(record, "causal_relation")
    from = field(record, "from")
    to = field(record, "to")

    with true <- type in Causal.types(),
         true <- is_binary(from) and from != "",
         true <- is_binary(to) and to != "",
         {:ok, evidence} <- record_evidence(state, record, observation_id, true) do
      relation = %CausalRelation{
        id: id,
        type: type,
        from: from,
        to: to,
        evidence: evidence,
        confidence: confidence(record),
        alternatives: plain_list(field(record, "alternatives")),
        dependencies: dependencies(record, observation_id, evidence) ++ ["story:#{from}", "story:#{to}"],
        metadata: plain_map(field(record, "metadata") || %{})
      }

      if Map.has_key?(state.causal_edges, id),
        do: {:error, {:duplicate_story_world_id, id}},
        else: {:ok, %{state | causal_edges: Map.put(state.causal_edges, id, relation)}}
    else
      _ -> {:error, {:invalid_causal_relation, id}}
    end
  end

  defp put_world(state, field_name, value) do
    collection = Map.fetch!(state.world, field_name)

    if Map.has_key?(collection, value.id) do
      {:error, {:duplicate_story_world_id, value.id}}
    else
      {:ok, %{state | world: Map.put(state.world, field_name, Map.put(collection, value.id, value))}}
    end
  end

  defp validate_references(state) do
    unknown_constraints =
      state.constraints
      |> Map.values()
      |> Enum.flat_map(fn constraint ->
        Enum.reject([constraint.left, constraint.right], &Map.has_key?(state.nodes, &1))
      end)
      |> Enum.uniq()
      |> Enum.sort()

    unknown_transitions =
      state.world.state_transitions
      |> Map.values()
      |> Enum.reject(&Map.has_key?(state.world.events, &1.event_id))
      |> Enum.map(& &1.event_id)
      |> Enum.uniq()
      |> Enum.sort()

    known_objects = story_object_ids(state)

    unknown_causal =
      state.causal_edges
      |> Map.values()
      |> Enum.flat_map(fn edge -> Enum.reject([edge.from, edge.to], &MapSet.member?(known_objects, &1)) end)
      |> Enum.uniq()
      |> Enum.sort()

    cond do
      unknown_constraints != [] -> {:error, {:unknown_story_time_node, unknown_constraints}}
      unknown_transitions != [] -> {:error, {:unknown_transition_event, unknown_transitions}}
      unknown_causal != [] -> {:error, {:unknown_causal_endpoint, unknown_causal}}
      true -> :ok
    end
  end

  defp story_object_ids(state) do
    fields = ~w(entities events interactions assertions goals commitments state_transitions beats motifs)a

    fields
    |> Enum.flat_map(&(state.world |> Map.fetch!(&1) |> Map.keys()))
    |> Kernel.++(Map.keys(state.nodes))
    |> MapSet.new()
  end

  defp finish(state) do
    story_time = StoryTime.build(Map.values(state.nodes), Map.values(state.constraints))
    causal = Causal.build(Map.values(state.causal_edges))
    world = %{state.world | story_time: story_time, causal: causal, conflicts: story_time.conflicts}
    conflicts = world.conflicts ++ Consistency.check(world)
    world = %{world | conflicts: Enum.uniq_by(conflicts, & &1.id) |> Enum.sort_by(& &1.id)}
    index = DependencyIndex.build(world)
    {:ok, %{world | dependency_index: index}}
  end

  defp record_evidence(state, record, observation_id, required?) do
    record_evidence(
      state.screenplay,
      record,
      observation_id,
      state.observation_state,
      state.evidence_registry,
      required?
    )
  end

  defp record_evidence(screenplay, record, observation_id, observation_state, registry, required?) do
    explicit = List.wrap(field(record, "evidence"))
    ids = List.wrap(field(record, "evidence_ids")) |> Enum.map(&to_string/1)

    result =
      cond do
        explicit != [] ->
          normalize_evidence_list(screenplay, explicit)

        ids != [] ->
          missing = Enum.reject(ids, &Map.has_key?(registry, &1))
          if missing == [], do: {:ok, Enum.map(ids, &Map.fetch!(registry, &1))}, else: {:error, {:unknown_evidence_ids, missing}}

        is_binary(observation_id) ->
          observation = Map.fetch!(observation_state.by_id, observation_id)
          {:ok, Enum.map(observation.evidence, &Evidence.from_observe/1)}

        true ->
          {:ok, []}
      end

    with {:ok, evidence} <- result do
      evidence = uniq_evidence(evidence)
      if required? and evidence == [], do: {:error, :missing_story_world_evidence}, else: {:ok, evidence}
    end
  end

  defp normalize_evidence_list(screenplay, entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case normalize_evidence_item(screenplay, entry) do
        {:ok, evidence} -> {:cont, {:ok, [evidence | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, evidence} -> {:ok, Enum.reverse(evidence)}
      error -> error
    end
  end

  defp normalize_evidence_item(screenplay, %Evidence{} = evidence) do
    Evidence.from_source_map(screenplay, %{
      "evidence_id" => evidence.id,
      "screenplay_id" => evidence.screenplay_id,
      "revision_id" => evidence.revision_id,
      "target" => evidence.target,
      "excerpt" => evidence.excerpt,
      "role" => evidence.role
    })
  end

  defp normalize_evidence_item(screenplay, %EvidenceRef{} = evidence),
    do: Evidence.from_source_map(screenplay, EvidenceRef.to_map(evidence))

  defp normalize_evidence_item(screenplay, %{} = entry) do
    cond do
      field(entry, "element_id") ->
        case Fount.Query.node(screenplay, field(entry, "element_id")) do
          nil -> {:error, :invalid_story_world_evidence}
          element -> {:ok, Evidence.canonical_element(screenplay, element)}
        end

      field(entry, "evidence_id") ->
        Evidence.from_source_map(screenplay, stringify_keys(entry))

      true ->
        {:error, :invalid_story_world_evidence}
    end
  end

  defp normalize_evidence_item(_screenplay, _entry), do: {:error, :invalid_story_world_evidence}

  defp record_scope(record, scopes) do
    case field(record, "scope") || field(record, "scope_id") || "base" do
      %{} = scope ->
        record_scope(%{"scope_id" => field(scope, "id")}, scopes)

      id when is_binary(id) ->
        if Map.has_key?(scopes, id), do: {:ok, id}, else: {:error, {:unknown_narrative_scope, id}}

      id ->
        {:error, {:unknown_narrative_scope, id}}
    end
  end

  defp record_presentation_points(screenplay, record, evidence) do
    explicit = List.wrap(field(record, "presentation_points"))

    if explicit == [] do
      evidence
      |> Enum.map(&presentation_from_evidence(screenplay, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&{&1.scene_ordinal, &1.element_ordinal, &1.boundary})
      |> Enum.sort_by(&{&1.scene_ordinal, &1.element_ordinal || -1, &1.boundary})
    else
      explicit
      |> Enum.map(&presentation_from_map/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&{&1.scene_ordinal, &1.element_ordinal || -1, &1.boundary})
    end
  end

  defp presentation_from_evidence(screenplay, %Evidence{target: %{"kind" => "element", "id" => id}}),
    do: presentation_from_element(screenplay, id)

  defp presentation_from_evidence(_screenplay, _evidence), do: nil

  defp presentation_from_target(screenplay, %TargetRef{kind: "element", id: id}),
    do: presentation_from_element(screenplay, id)

  defp presentation_from_target(_screenplay, _target), do: nil

  defp presentation_from_element(screenplay, element_id) do
    scene = Fount.Query.scene_for(screenplay, element_id)
    scene_ordinal = if scene, do: scene_ordinal(screenplay, scene.id), else: 0

    %PresentationPoint{
      scene_id: scene && scene.id,
      scene_ordinal: scene_ordinal,
      element_id: element_id,
      element_ordinal: element_ordinal(screenplay, element_id),
      boundary: "at"
    }
  end

  defp presentation_point(screenplay, element_id, scene_ordinal) do
    scene = Fount.Query.scene_for(screenplay, element_id)

    %PresentationPoint{
      scene_id: if(scene, do: scene.id, else: nil),
      scene_ordinal: scene_ordinal,
      element_id: element_id,
      element_ordinal: element_ordinal(screenplay, element_id),
      boundary: "at"
    }
  end

  defp presentation_from_map(%{} = map) do
    ordinal = field(map, "scene_ordinal")

    if is_integer(ordinal) and ordinal >= 0 do
      %PresentationPoint{
        scene_id: field(map, "scene_id"),
        scene_ordinal: ordinal,
        element_id: field(map, "element_id"),
        element_ordinal: field(map, "element_ordinal"),
        boundary: field(map, "boundary") || "at"
      }
    end
  end

  defp presentation_from_map(_), do: nil

  defp scene_ordinal(screenplay, scene_id),
    do: (Enum.find_index(screenplay.ir.scenes, &(&1.id == scene_id)) || -1) + 1

  defp element_ordinal(screenplay, element_id),
    do: (Enum.find_index(screenplay.ir.elements, &(&1.id == element_id)) || -1) + 1

  defp record_type(record) when is_map(record) do
    explicit = scalar_string(field(record, "record_type") || field(record, "type"))
    kind = scalar_string(field(record, "kind"))

    cond do
      explicit in @record_types -> explicit
      is_binary(kind) and Map.has_key?(@legacy_types, kind) -> Map.get(@legacy_types, kind)
      kind in @record_types -> kind
      true -> nil
    end
  end

  defp normalize_legacy(record) when is_map(record) do
    legacy = scalar_string(field(record, "kind"))

    case Map.get(@legacy_types, legacy) do
      nil -> record
      type ->
        record
        |> Map.put("record_type", type)
        |> Map.put_new("legacy_kind", legacy)
    end
  end

  defp normalize_legacy(other), do: other

  defp legacy_predicate(record) do
    case field(record, "legacy_kind") do
      nil -> field(record, "kind") || "assertion"
      kind -> "extracted_" <> kind
    end
  end

  defp semantic_kind(record, default) do
    explicit =
      field(record, "event_type") || field(record, "commitment_type") || field(record, "causal_type") ||
        field(record, "semantic_kind") || field(record, "subtype")

    kind =
      cond do
        explicit -> explicit
        field(record, "record_type") -> field(record, "kind")
        true -> nil
      end

    kind = scalar_string(kind)
    kind = if kind in @record_types or (is_binary(kind) and Map.has_key?(@legacy_types, kind)), do: nil, else: kind
    if is_nil(kind), do: default, else: kind
  end

  defp record_id(screenplay, record, type) do
    case field(record, "id") do
      id when is_binary(id) and id != "" -> id
      _ ->
        digest = record |> Model.plain() |> Fount.Writing.CanonicalJSON.hash()
        "sw_#{type}_" <> String.slice(digest, 0, 24)
    end
  end

  defp dependencies(record, observation_id, evidence) do
    explicit =
      record
      |> field("dependencies")
      |> plain_list()
      |> Enum.map(&scalar_string/1)
      |> Enum.reject(&is_nil/1)
    observation = if is_binary(observation_id), do: ["observation:#{observation_id}"], else: []
    evidence_deps = Enum.map(evidence, &"evidence:#{&1.id}")
    Enum.sort(Enum.uniq(explicit ++ observation ++ evidence_deps))
  end

  defp distribution_confidence(%{confidence: confidence}) when is_number(confidence), do: confidence
  defp distribution_confidence(_distribution), do: nil

  defp confidence(record) do
    value = field(record, "confidence") || field(record, "certainty")
    if is_number(value), do: value, else: nil
  end

  defp subjects_as_participants(record) do
    case plain_list(field(record, "subjects")) do
      [] -> %{}
      subjects -> %{"subjects" => subjects}
    end
  end

  defp uniq_evidence(evidence), do: evidence |> Enum.uniq_by(& &1.id) |> Enum.sort_by(& &1.id)

  defp field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.reduce_while(map, nil, fn
          {atom_key, value}, _acc when is_atom(atom_key) ->
            if Atom.to_string(atom_key) == key, do: {:halt, value}, else: {:cont, nil}

          _entry, _acc ->
            {:cont, nil}
        end)
    end
  end

  defp field(_map, _key), do: nil

  defp scalar_string(value) when is_binary(value), do: value
  defp scalar_string(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp scalar_string(value) when is_integer(value), do: Integer.to_string(value)
  defp scalar_string(_value), do: nil

  defp plain_map(nil), do: %{}
  defp plain_map(value) when is_map(value), do: Model.plain(value)
  defp plain_map(_value), do: %{}

  defp plain_list(nil), do: []
  defp plain_list(value) when is_list(value), do: Enum.map(value, &Model.plain/1)
  defp plain_list(value), do: [Model.plain(value)]

  defp stringify_keys(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), stringify_keys(item)} end)

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
