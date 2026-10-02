defmodule FountWeb.SemanticContext do
  @moduledoc "Source-bound literal inventory, SI02 assessment projection, manual review precedence, and Core-promotion adapter."

  alias Fount.{Persistence, Query, Screenplay}
  alias FountWeb.{ProductionStore, SemanticStore, Store}

  @doc "Loads the literal inventory plus the newest usable source-bound interpretation for one owned revision."
  def load(repo, owner, project, %Screenplay{} = screenplay)
      when is_binary(owner) and is_map(project) do
    with {:ok, stored} <- Store.project(repo, owner, project["id"]),
         true <-
           stored["screenplay_id"] == screenplay.id or {:error, :project_screenplay_mismatch},
         {:ok, persisted} <-
           Persistence.load_revision(repo, screenplay.id, screenplay.revision.id),
         true <-
           persisted.revision.content_hash == screenplay.revision.content_hash or
             {:error, :source_content_mismatch},
         {:ok, head} <- Persistence.load(repo, stored["key"]),
         {:ok, manual} <- SemanticStore.ensure_inventory(repo, owner, stored, persisted),
         {:ok, assessment} <-
           SemanticStore.resolved_assessment_for_revision(
             repo,
             owner,
             stored["id"],
             persisted.revision.id
           ),
         current_entities when is_list(current_entities) <- SemanticStore.entities(repo, assessment["id"]),
         revision_entities when is_list(revision_entities) <-
           SemanticStore.entity_rows_for_revision(repo, owner, stored["id"], persisted.revision.id),
         history when is_list(history) <-
           SemanticStore.review_history_for_revision(repo, owner, stored["id"], persisted.revision.id),
         {:ok, version} <-
           SemanticStore.current_version(repo, owner, stored["id"], assessment["id"]),
         assessment_history when is_list(assessment_history) <-
           SemanticStore.assessment_history(repo, owner, stored["id"], persisted.revision.id),
         model_history when is_list(model_history) <-
           SemanticStore.model_assessment_history(repo, owner, stored["id"]) do
      entities = select_entity_rows(current_entities, revision_entities, history)
      projection = project_entities(entities, history)
      inventory = manual["result"] || %{}
      latest_current = latest_model(assessment_history)
      latest = latest_current || List.first(model_history)

      {:ok,
       %{
         assessment: assessment,
         assessment_id: assessment["id"],
         assessment_result: assessment["result"] || %{},
         assessment_history: assessment_history,
         model_assessment_history: model_history,
         latest_assessment: latest,
         version: version,
         source_sha256: assessment["source_sha256"],
         revision_id: assessment["revision_id"],
         inventory: inventory,
         entities: projection,
         characters: character_profiles(projection, persisted, inventory),
         locations: location_profiles(projection),
         canonical_cast: canonical_cast(inventory),
         review_history: history,
         assessment_state: assessment_state(head, persisted, latest_current, latest),
         coverage: if(latest, do: latest["coverage"] || %{}, else: %{}),
         usage: if(latest, do: latest["usage"] || %{}, else: %{}),
         assessment_error: if(latest, do: latest["error"] || %{}, else: %{})
       }}
    else
      {:error, _} = error -> error
    end
  end

  @doc "Carries human-reviewed handles across reassessments without reviving unreviewed historical suggestions."
  def select_entity_rows(current_rows, revision_rows, history)
      when is_list(current_rows) and is_list(revision_rows) and is_list(history) do
    active_handles =
      history
      |> active_review_events()
      |> Enum.flat_map(&event_handle_ids/1)
      |> MapSet.new()

    current_handles = MapSet.new(Enum.map(current_rows, & &1["handle_id"]))

    carried =
      revision_rows
      |> Enum.filter(fn row ->
        MapSet.member?(active_handles, row["handle_id"]) and
          not MapSet.member?(current_handles, row["handle_id"])
      end)
      |> Enum.uniq_by(& &1["handle_id"])

    current_rows ++ carried
  end

  defp latest_model(rows) do
    Enum.find(rows, &(&1["schema_version"] == "semantic_import_v1" and &1["origin"] in ["model", "deterministic_fixture"]))
  end

  defp assessment_state(head, persisted, _latest_current, _latest_any)
       when head.revision.id != persisted.revision.id,
       do: :historical

  defp assessment_state(_head, persisted, nil, %{"revision_id" => revision_id})
       when revision_id != persisted.revision.id,
       do: :stale

  defp assessment_state(_head, _persisted, nil, nil), do: :not_assessed
  defp assessment_state(_head, _persisted, %{"status" => "queued"}, _), do: :queued
  defp assessment_state(_head, _persisted, %{"status" => "running"}, _), do: :running
  defp assessment_state(_head, _persisted, %{"status" => "partial"}, _), do: :partial
  defp assessment_state(_head, _persisted, %{"status" => "ready"}, _), do: :ready
  defp assessment_state(_head, _persisted, %{"status" => "failed"}, _), do: :failed
  defp assessment_state(_head, _persisted, %{"status" => "cancelled"}, _), do: :cancelled
  defp assessment_state(_head, _persisted, _latest_current, _latest_any), do: :unknown

  def project_entities(rows, history) when is_list(rows) and is_list(history) do
    base =
      Map.new(rows, fn row ->
        payload = row["payload"] || %{}
        handle_id = row["handle_id"]

        {handle_id,
         %{
           handle_id: handle_id,
           kind: row["kind"],
           label: row["label"],
           review_state: suggested_state(row["assessment_origin"] || row["created_origin"]),
           aliases: model_aliases(payload),
           parent_handle_id: nil,
           time: nil,
           merged_into: nil,
           occurrences: occurrences(payload, row["local_id"]),
           certainty: value(payload, "certainty"),
           evidence: value(payload, "evidence") || row["evidence"] || [],
           source_origin: row["assessment_origin"] || row["created_origin"] || "manual"
         }}
      end)

    active = active_review_events(history)

    projected =
      Enum.reduce(active, base, fn event, state ->
        event
        |> apply_event(state)
        |> consolidate_merges()
        |> Map.new(&{&1.handle_id, &1})
      end)

    consolidate_merges(projected)
  end

  def active_review_events(history) do
    applied = Enum.filter(history, &(&1["outcome"] == "applied"))

    {active_rev, _disabled} =
      applied
      |> Enum.reverse()
      |> Enum.reduce({[], MapSet.new()}, fn event, {keep, disabled} ->
        cond do
          MapSet.member?(disabled, event["id"]) ->
            {keep, disabled}

          event["action"] == "undo" ->
            target = get_in(event, ["payload", "event_id"])
            {keep, if(is_binary(target), do: MapSet.put(disabled, target), else: disabled)}

          true ->
            {[event | keep], disabled}
        end
      end)

    active_rev
  end

  defp event_handle_ids(event) do
    payload = event["payload"] || %{}

    [
      event["target_handle_id"],
      payload["into_handle_id"],
      payload["parent_handle_id"],
      payload["new_handle_id"]
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp apply_event(%{"action" => "confirm", "target_handle_id" => id}, state),
    do: update_entity(state, id, &Map.put(&1, :review_state, "confirmed"))

  defp apply_event(%{"action" => "reject", "target_handle_id" => id}, state),
    do: update_entity(state, id, &Map.put(&1, :review_state, "rejected"))

  defp apply_event(
         %{"action" => "change_type", "target_handle_id" => id, "payload" => %{"kind" => kind}},
         state
       ),
       do: update_entity(state, id, &Map.put(&1, :kind, kind))

  defp apply_event(
         %{
           "action" => "merge",
           "target_handle_id" => id,
           "payload" => %{"into_handle_id" => into}
         },
         state
       ),
       do: update_entity(state, id, &Map.put(&1, :merged_into, into))

  defp apply_event(
         %{"action" => "set_alias", "target_handle_id" => id, "payload" => %{"alias" => value}},
         state
       ) do
    update_entity(state, id, fn entity ->
      aliases = [String.trim(value) | entity.aliases] |> Enum.reject(&(&1 == "")) |> Enum.uniq()
      %{entity | aliases: aliases}
    end)
  end

  defp apply_event(
         %{
           "action" => "set_location_parent",
           "target_handle_id" => id,
           "payload" => %{"parent_handle_id" => parent}
         },
         state
       ),
       do: update_entity(state, id, &Map.put(&1, :parent_handle_id, parent))

  defp apply_event(
         %{"action" => "set_time", "target_handle_id" => id, "payload" => %{"value" => value}},
         state
       ),
       do: update_entity(state, id, &Map.put(&1, :time, String.trim(value)))

  defp apply_event(
         %{
           "action" => "resolve_occurrence",
           "target_handle_id" => id,
           "payload" => %{"local_id" => local_id, "role" => role}
         },
         state
       ) do
    update_entity(state, id, fn entity ->
      occurrences = Enum.map(entity.occurrences, &set_occurrence_role(&1, local_id, role))

      %{entity | occurrences: occurrences}
    end)
  end

  defp apply_event(
         %{
           "action" => "split",
           "target_handle_id" => id,
           "payload" => %{"local_ids" => local_ids, "new_handle_id" => new_id}
         },
         state
       ) do
    case Map.get(state, id) do
      nil ->
        state

      entity ->
        {moved, kept} = Enum.split_with(entity.occurrences, &(&1.local_id in local_ids))

        split_entity(state, entity, id, new_id, moved, kept)
    end
  end

  defp apply_event(_event, state), do: state

  defp set_occurrence_role(%{local_id: id} = occurrence, id, role), do: %{occurrence | role: role}
  defp set_occurrence_role(occurrence, _id, _role), do: occurrence

  defp split_entity(state, _entity, _id, _new_id, [], _kept), do: state

  defp split_entity(state, entity, id, new_id, moved, kept) do
    new_entity = %{
      entity
      | handle_id: new_id,
        label: List.first(moved).literal || entity.label,
        occurrences: moved,
        merged_into: nil,
        review_state: entity.review_state,
        aliases: []
    }

    state |> Map.put(id, %{entity | occurrences: kept}) |> Map.put(new_id, new_entity)
  end

  defp consolidate_merges(state) do
    state
    |> Enum.reduce(state, fn {id, entity}, acc ->
      case merge_root(state, entity.merged_into, MapSet.new([id])) do
        nil ->
          acc

        root when root == id ->
          acc

        root ->
          merge_entities(acc, id, root)
      end
    end)
    |> Map.values()
    |> Enum.filter(&(&1.occurrences != []))
    |> Enum.sort_by(&{&1.kind, String.downcase(&1.label || ""), &1.handle_id})
  end

  defp merge_entities(state, id, root) do
    case {Map.get(state, id), Map.get(state, root)} do
      {%{} = child, %{} = parent} ->
        parent = %{
          parent
          | occurrences: parent.occurrences ++ child.occurrences,
            aliases:
              (parent.aliases ++ child.aliases ++ [child.label])
              |> Enum.reject(&(&1 in [nil, "", parent.label]))
              |> Enum.uniq(),
            review_state: merged_review_state(parent.review_state, child.review_state)
        }

        state |> Map.put(root, parent) |> Map.delete(id)

      _ ->
        state
    end
  end

  defp merge_root(_state, nil, _seen), do: nil

  defp merge_root(state, id, seen) do
    cond do
      MapSet.member?(seen, id) -> id
      is_nil(state[id]) -> id
      is_nil(state[id].merged_into) -> id
      true -> merge_root(state, state[id].merged_into, MapSet.put(seen, id))
    end
  end

  defp merged_review_state("confirmed", _), do: "confirmed"
  defp merged_review_state(_, "confirmed"), do: "confirmed"
  defp merged_review_state("rejected", "rejected"), do: "rejected"
  defp merged_review_state("suggested", _), do: "suggested"
  defp merged_review_state(_, "suggested"), do: "suggested"
  defp merged_review_state(_, _), do: "unreviewed"

  defp suggested_state(origin) when origin in ["model", "deterministic_fixture"], do: "suggested"
  defp suggested_state(_), do: "unreviewed"

  defp update_entity(state, id, fun) do
    case Map.fetch(state, id) do
      {:ok, entity} -> Map.put(state, id, fun.(entity))
      :error -> state
    end
  end

  defp occurrences(payload, local_id) do
    case value(payload, "occurrences") do
      rows when is_list(rows) and rows != [] -> Enum.map(rows, &occurrence(&1, local_id))
      _ -> [occurrence(payload, local_id)]
    end
  end

  defp occurrence(payload, fallback_local_id) do
    parts = value(payload, "parts") || %{}

    %{
      local_id: value(payload, "local_id") || fallback_local_id,
      element_id: value(payload, "element_id") || value(payload, "literal_element_id"),
      dialogue_block_id: value(payload, "dialogue_block_id"),
      literal: value(payload, "literal") || value(payload, "raw") || evidence_quote(payload),
      raw: value(payload, "raw"),
      role: value(payload, "occurrence_role") || value(payload, "role") || "unknown",
      scene_id: value(payload, "scene_id"),
      scene_ordinal: value(payload, "scene_ordinal"),
      source_span: value(payload, "source_span"),
      evidence: value(payload, "evidence") || [],
      parts: parts
    }
  end

  defp evidence_quote(payload) do
    payload
    |> value("evidence")
    |> List.wrap()
    |> List.first()
    |> case do
      %{} = row -> row["quote"] || ""
      _ -> ""
    end
  end

  defp model_aliases(payload) do
    payload
    |> value("aliases")
    |> List.wrap()
    |> Enum.map(fn
      %{} = row -> row["label"] || row[:label]
      value when is_binary(value) -> value
      _ -> nil
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  def character_profiles(entities, screenplay, inventory) do
    confirmed_ids =
      canonical_cast(inventory)
      |> Enum.filter(&(&1["review_state"] == "confirmed"))
      |> Enum.map(& &1["core_character_id"])

    semantic =
      entities
      |> Enum.filter(&(&1.kind == "character" and &1.review_state != "rejected"))
      |> Enum.map(&character_profile(&1, screenplay, confirmed_ids))

    legacy =
      canonical_cast(inventory)
      |> Enum.map(fn row ->
        %{
          id: row["core_character_id"],
          semantic_handle_id: nil,
          core_character_id: row["core_character_id"],
          display_name: row["display_name"],
          aliases: Enum.map(row["aliases"] || [], &(&1["alias"] || &1[:alias])),
          review_state: row["review_state"] || "confirmed",
          representation: row["origin"] || "canonical",
          speaking_occurrences: length(row["cue_element_ids"] || []),
          presence_occurrences: 0,
          mention_occurrences: 0,
          appearance_ordinals: [],
          appearance_count: 0,
          dialogue_block_count: length(row["cue_element_ids"] || []),
          occurrences: []
        }
      end)

    linked_core_ids =
      semantic |> Enum.map(& &1.core_character_id) |> Enum.reject(&is_nil/1) |> MapSet.new()

    legacy = Enum.reject(legacy, &MapSet.member?(linked_core_ids, &1.core_character_id))

    (semantic ++ legacy)
    |> Enum.sort_by(&{String.downcase(&1.display_name || ""), &1.id})
  end

  defp character_profile(entity, screenplay, confirmed_ids) do
    dialogue_blocks =
      entity.occurrences
      |> Enum.map(& &1.dialogue_block_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    scene_ordinals =
      entity.occurrences
      |> Enum.map(& &1.scene_ordinal)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    core_character_id = matching_core_character(screenplay, entity, confirmed_ids)

    %{
      id: entity.handle_id,
      semantic_handle_id: entity.handle_id,
      core_character_id: core_character_id,
      display_name: entity.label,
      aliases: entity.aliases,
      review_state: if(core_character_id, do: "confirmed", else: entity.review_state),
      representation:
        if(core_character_id, do: "canonical_linked_source", else: "source_interpretation"),
      speaking_occurrences: Enum.count(entity.occurrences, &(&1.role == "speaker")),
      presence_occurrences: Enum.count(entity.occurrences, &(&1.role == "physical_presence")),
      mention_occurrences: Enum.count(entity.occurrences, &(&1.role == "mentioned")),
      appearance_ordinals: scene_ordinals,
      appearance_count: length(scene_ordinals),
      dialogue_block_count: length(dialogue_blocks),
      occurrences: entity.occurrences
    }
  end

  def location_profiles(entities) do
    entities
    |> Enum.filter(&(&1.kind == "location" and &1.review_state != "rejected"))
    |> Enum.map(fn entity ->
      entries =
        Enum.map(entity.occurrences, &location_entry(&1, entity.time))

      %{
        id: entity.handle_id,
        handle_id: entity.handle_id,
        location: entity.label,
        aliases: entity.aliases,
        review_state: entity.review_state,
        parent_handle_id: entity.parent_handle_id,
        entries: entries
      }
    end)
    |> Enum.sort_by(&{String.downcase(&1.location || ""), &1.id})
  end

  defp location_entry(occurrence, reviewed_time) do
    parts = occurrence.parts || %{}

    %{
      local_id: occurrence.local_id,
      element_id: occurrence.element_id,
      ordinal: occurrence.scene_ordinal,
      heading: occurrence.literal,
      parsed_context: value(parts, "context") || "Unknown / unparsed",
      parsed_time:
        reviewed_time || value(parts, "time") || value(parts, "relative_time") ||
          "Unknown / unparsed",
      place: value(parts, "parent_place") || "Unknown / unparsed",
      time_of_day: value(parts, "time_of_day") || "Unknown / unparsed",
      relative_time: value(parts, "relative_time"),
      date_or_era: value(parts, "date_or_era"),
      subplace: value(parts, "subplace"),
      unknown_modifiers: value(parts, "unknown_modifiers") || []
    }
  end

  @doc "Annotates a human table-read packet with source-bound semantic speaker identities without changing source cues or dialogue."
  def annotate_table_read(packet, characters) when is_map(packet) and is_list(characters) do
    by_block =
      Enum.reduce(characters, %{}, fn profile, acc ->
        identity = %{
          "handle_id" => profile.semantic_handle_id,
          "display_name" => profile.display_name,
          "review_state" => profile.review_state,
          "representation" => profile.representation
        }

        profile.occurrences
        |> Enum.filter(&(&1.role == "speaker" and is_binary(&1.dialogue_block_id)))
        |> Enum.reduce(acc, fn occurrence, index ->
          Map.update(index, occurrence.dialogue_block_id, [identity], fn rows ->
            [identity | rows] |> Enum.uniq_by(& &1["handle_id"])
          end)
        end)
      end)

    turns =
      Enum.map(packet["turns"] || [], fn turn ->
        case Map.get(by_block, turn["id"], []) do
          [identity] -> Map.put(turn, "semantic_identity", identity)
          [] -> turn
          identities -> Map.put(turn, "semantic_identity_candidates", Enum.sort_by(identities, & &1["display_name"]))
        end
      end)

    roster =
      turns
      |> Enum.flat_map(fn turn ->
        case turn["semantic_identity"] do
          %{} = identity -> [Map.put(identity, "source_cue", turn["cue"])]
          _ -> []
        end
      end)
      |> Enum.uniq_by(& &1["handle_id"])
      |> Enum.sort_by(&{String.downcase(&1["display_name"] || ""), &1["handle_id"] || ""})

    packet
    |> Map.put("turns", turns)
    |> Map.put("semantic_roster", roster)
    |> Map.put("semantic_roster_claim", "Interpretation metadata only; source cue/dialogue text is unchanged.")
  end

  def character_dialogue(%Screenplay{} = screenplay, profile) when is_map(profile) do
    blocks =
      profile.occurrences
      |> Enum.map(& &1.dialogue_block_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&Query.dialogue_block(screenplay, &1))
      |> Enum.reject(&is_nil/1)

    rows = Enum.map(blocks, &dialogue_row(screenplay, &1))

    {:ok,
     %{character: profile, rows: rows, total: length(rows), representation: "literal_source"}}
  end

  def character_dialogue(%Screenplay{} = screenplay, character_id) when is_binary(character_id) do
    case Query.character(screenplay, character_id) do
      nil -> {:error, :character_not_found}
      character -> FountWeb.CreativeWorkspace.character_dialogue(screenplay, character.id)
    end
  end

  @doc "Builds a saved Core candidate from a reviewed semantic character without accepting it."
  def save_character_promotion_candidate(
        repo,
        owner,
        project_id,
        base_revision_id,
        semantic,
        handle_id
      )
      when is_map(semantic) and is_binary(handle_id) do
    with {:ok, project} <- Store.project(repo, owner, project_id),
         true <- semantic.revision_id == base_revision_id or {:error, :semantic_revision_stale},
         profile when is_map(profile) <-
           Enum.find(semantic.characters, &(&1.semantic_handle_id == handle_id)),
         true <- profile.review_state == "confirmed" or {:error, :semantic_identity_unconfirmed},
         true <-
           is_nil(profile.core_character_id) or {:error, :semantic_identity_already_canonical},
         {:ok, base} <-
           Persistence.load_revision(repo, project["screenplay_id"], base_revision_id),
         operations <- promotion_operations(profile),
         {:ok, candidate_screenplay, _changes} <-
           Screenplay.apply(base, operations, actor: "writer:#{owner}"),
         {:ok, candidate} <-
           Persistence.save_edit_candidate(repo, project["key"], candidate_screenplay,
             expected_revision: base.revision.id,
             operations: operations,
             label: "Reviewed source identity promotion"
           ),
         {:ok, pointer} <-
           ProductionStore.register_candidate(repo, %{
             owner_id: owner,
             project_id: project_id,
             candidate_id: candidate.id,
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             kind: "cast",
             resource_id: handle_id,
             metadata: %{
               "action" => "semantic_identity_promotion",
               "semantic_handle_id" => handle_id,
               "display_name" => profile.display_name,
               "source_revision_id" => base_revision_id
             }
           }) do
      {:ok, %{candidate: candidate, pointer: pointer, operations: operations}}
    else
      nil -> {:error, :semantic_identity_not_found}
      false -> {:error, :semantic_identity_invalid}
      {:error, _} = error -> error
    end
  end

  defp promotion_operations(profile) do
    local = "new:reviewed-character"

    put = %{
      "kind" => "put_character",
      "value" => %{
        "local_id" => local,
        "display_name" => profile.display_name,
        "notes" => nil,
        "aliases" => Enum.map(profile.aliases, &%{"alias" => &1, "kind" => "aka"}),
        "attributes" => %{"semantic_handle_id" => profile.semantic_handle_id}
      }
    }

    links =
      profile.occurrences
      |> Enum.map(& &1.dialogue_block_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(fn block_id ->
        %{
          "kind" => "link_speaker",
          "target" => %{"kind" => "dialogue_block", "id" => block_id},
          "value" => %{"character_id" => local}
        }
      end)

    [put | links]
  end

  defp matching_core_character(screenplay, entity, confirmed_ids) do
    cue_ids =
      entity.occurrences |> Enum.map(& &1.element_id) |> Enum.reject(&is_nil/1) |> MapSet.new()

    screenplay.cast
    |> Map.values()
    |> Enum.filter(&(&1.id in confirmed_ids))
    |> Enum.find_value(fn character ->
      linked =
        Query.character_mentions(screenplay, character.id)
        |> Enum.filter(&(&1.role == :speaker_cue and &1.status == :confirmed))
        |> Enum.map(& &1.element_id)
        |> MapSet.new()

      if MapSet.size(cue_ids) > 0 and MapSet.subset?(cue_ids, linked), do: character.id
    end)
  end

  defp canonical_cast(inventory),
    do: inventory["canonical_cast"] || inventory[:canonical_cast] || []

  defp dialogue_row(screenplay, block) do
    scene = Query.scene_for(screenplay, block.cue_id)
    heading = if scene, do: Query.node(screenplay, scene.heading_id)
    cue = Query.node(screenplay, block.cue_id)

    %{
      block_id: block.id,
      cue_id: block.cue_id,
      scene_id: scene && scene.id,
      scene_heading: heading && heading.text,
      character: cue && (cue.raw_text || cue.text),
      lines:
        block.body_ids
        |> Enum.map(&Query.node(screenplay, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&%{id: &1.id, type: &1.type, text: &1.text})
    }
  end

  defp value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(map, &matching_value(&1, key))
    end
  end

  defp value(_, _), do: nil

  defp matching_value({candidate, value}, key) do
    if to_string(candidate) == key, do: value
  end
end
