defmodule FountWeb.ProductionTools do
  @moduledoc "Phase 08 source-grounded search, production inspection, authored notes and human evidence host adapter."

  alias Fount.{Persistence, Query, Screenplay, Search, Target}
  alias Fount.Screenplay.Model
  alias Fount.Writing.{Approval, Authority, CanonicalJSON, Principal}
  alias FountWorkshop.{TableRead, Usefulness}
  alias FountWeb.{ProductionStore, ScreenplayIndex, ScreenplayViews, Store}

  @search_types ~w(action character dialogue parenthetical transition centered lyric section synopsis page_break note boneyard blank scene_heading)
  @completed_statuses ~w(completed_candidate completed_accepted)
  @usefulness_dimensions ~w(task_completion next_decision agency voice_retention alternative_diversity consequence_usefulness rejection_time_ms)

  def search_types, do: @search_types
  def usefulness_dimensions, do: @usefulness_dimensions

  def workspace(repo, owner, run_id, token \\ nil) do
    with {:ok, access} <- Store.run_access(repo, owner, run_id),
         {:ok, project} <- Store.project(repo, owner, access["project_id"]),
         {:ok, context} <- FountWeb.Actors.owner_context(owner, access["screenplay_id"]),
         {:ok, run} <- FountRun.get_run(repo, run_id, context),
         {:ok, progress} <- FountRun.progress(repo, run_id, context),
         {:ok, view} <- ScreenplayViews.load(repo, access, run, progress, token) do
      {:ok,
       %{
         owner: owner,
         access: access,
         project: project,
         context: context,
         run: run,
         progress: progress,
         selection: view.selection,
         screenplay: view.screenplay,
         options: view.options,
         editable?: editable_revision?(repo, project, view.screenplay)
       }}
    end
  end

  def search(%Screenplay{} = screenplay, query, attrs \\ %{}) when is_map(attrs) do
    with {:ok, opts} <- search_opts(screenplay, attrs),
         {:ok, result} <- Search.find(screenplay, query, opts) do
      scenes = Map.new(ScreenplayIndex.scene_index(screenplay), &{&1.id, &1})

      hits =
        Enum.map(result.hits, fn hit ->
          scene = scenes[hit.scene_id]

          Map.merge(hit, %{
            scene_ordinal: scene && scene.ordinal,
            scene_heading: scene && scene.heading,
            anchor: "node-#{hit.element_id}",
            excerpt: snippet(hit.excerpt, result.query)
          })
        end)

      {:ok, Map.merge(result, %{hits: hits, filters: search_filter_summary(attrs)})}
    end
  end

  def character_profiles(%Screenplay{} = screenplay) do
    scene_ordinals =
      screenplay.ir.scenes |> Enum.with_index(1) |> Map.new(fn {s, n} -> {s.id, n} end)

    screenplay.cast
    |> Map.values()
    |> Enum.map(fn character ->
      mentions = Query.character_mentions(screenplay, character.id)
      scenes = Query.scenes_with_character(screenplay, character.id)
      dialogue = Query.character_dialogue(screenplay, character.id)

      %{
        id: character.id,
        display_name: character.display_name,
        aliases: Enum.map(character.aliases || [], &alias_text/1),
        confirmed_mentions: length(mentions),
        appearance_scene_ids: Enum.map(scenes, & &1.id),
        appearance_ordinals: scenes |> Enum.map(&scene_ordinals[&1.id]) |> Enum.reject(&is_nil/1),
        appearance_count: length(scenes),
        dialogue_block_count: length(dialogue),
        dialogue_word_count: dialogue_word_count(screenplay, dialogue),
        relationship_evidence: relationship_evidence(screenplay, character.id)
      }
    end)
    |> Enum.sort_by(&{&1.display_name, &1.id})
  end

  def location_profiles(%Screenplay{} = screenplay) do
    scenes = ScreenplayIndex.scene_index(screenplay)
    by_id = Map.new(scenes, &{&1.id, &1})

    ScreenplayIndex.location_index(screenplay, scenes)
    |> Enum.map(fn location ->
      entries =
        Enum.map(location.entries, fn entry ->
          scene = by_id[entry.scene_id]

          Map.merge(entry, %{
            ordinal: scene && scene.ordinal,
            heading: scene && scene.heading,
            parsed_time: entry.time || "Unknown / unparsed",
            parsed_context: entry.context || "Unknown / unparsed"
          })
        end)

      Map.put(location, :entries, entries)
    end)
  end

  def notes(%Screenplay{} = screenplay, attrs \\ %{}) do
    query = attrs |> Map.get("query", "") |> String.trim() |> String.downcase()
    wanted_status = Map.get(attrs, "status", "")

    screenplay
    |> Query.authored_items(:note)
    |> Enum.map(&note_projection(screenplay, &1))
    |> Enum.filter(fn note ->
      text = String.downcase((note.title || "") <> " " <> (note.text || ""))

      (query == "" or String.contains?(text, query)) and
        (wanted_status in [nil, ""] or note.target_state == wanted_status)
    end)
  end

  def measured_annotations(%Screenplay{} = screenplay) do
    screenplay.annotations
    |> Map.values()
    |> Enum.map(fn annotation ->
      %{
        id: annotation.id,
        namespace: annotation.namespace,
        kind: annotation.kind,
        target: Model.plain(annotation.target),
        confidence: annotation.confidence,
        provenance: Model.plain(annotation.provenance),
        source_revision: annotation.provenance && annotation.provenance.source_revision
      }
    end)
    |> Enum.sort_by(&{to_string(&1.namespace || ""), to_string(&1.kind || ""), &1.id})
  end

  def target_options(%Screenplay{} = screenplay) do
    screenplay_option = [%{value: "screenplay:#{screenplay.id}", label: "Screenplay"}]

    scene_options =
      screenplay.ir.scenes
      |> Enum.with_index(1)
      |> Enum.map(fn {scene, ordinal} ->
        heading = Query.node(screenplay, scene.heading_id)
        %{value: "scene:#{scene.id}", label: "Scene #{ordinal} · #{heading && heading.text}"}
      end)

    element_options =
      screenplay.ir.elements
      |> Enum.reject(&(&1.type in [:blank]))
      |> Enum.take(250)
      |> Enum.map(fn element ->
        excerpt =
          element.text |> to_string() |> String.replace(~r/\s+/u, " ") |> String.slice(0, 80)

        %{value: "element:#{element.id}", label: "#{element.type} · #{excerpt}"}
      end)

    character_options =
      screenplay.cast
      |> Map.values()
      |> Enum.sort_by(& &1.display_name)
      |> Enum.map(&%{value: "character:#{&1.id}", label: "Character · #{&1.display_name}"})

    screenplay_option ++ scene_options ++ character_options ++ element_options
  end

  def save_note_candidate(repo, owner, project_id, base_revision_id, attrs) when is_map(attrs) do
    with {:ok, project} <- Store.project(repo, owner, project_id),
         {:ok, base} <- current_editable_base(repo, project, base_revision_id),
         {:ok, target} <- parse_target(base, note_target(attrs)),
         {:ok, operation} <- note_operation(base, owner, target, attrs),
         {:ok, candidate_screenplay, _changes} <-
           Screenplay.apply(base, [operation], actor: "writer:#{owner}"),
         note_id <- resulting_note_id(base, candidate_screenplay, attrs["id"]),
         {:ok, candidate} <-
           Persistence.save_edit_candidate(repo, project["key"], candidate_screenplay,
             expected_revision: base.revision.id,
             operations: [operation],
             label: "Authored note"
           ),
         {:ok, pointer} <-
           ProductionStore.register_candidate(repo, %{
             owner_id: owner,
             project_id: project_id,
             candidate_id: candidate.id,
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             kind: "note",
             resource_id: note_id,
             metadata: %{"action" => "put", "target" => target}
           }) do
      {:ok, %{candidate: candidate, pointer: pointer, note_id: note_id}}
    end
  end

  def delete_note_candidate(repo, owner, project_id, base_revision_id, note_id) do
    with {:ok, project} <- Store.project(repo, owner, project_id),
         {:ok, base} <- current_editable_base(repo, project, base_revision_id),
         %{} <- Map.get(base.authored_items, note_id) || {:error, :note_not_found},
         operation <- %{
           "kind" => "delete_authored_item",
           "target" => %{"kind" => "authored_item", "id" => note_id}
         },
         {:ok, candidate_screenplay, _changes} <-
           Screenplay.apply(base, [operation], actor: "writer:#{owner}"),
         {:ok, candidate} <-
           Persistence.save_edit_candidate(repo, project["key"], candidate_screenplay,
             expected_revision: base.revision.id,
             operations: [operation],
             label: "Delete authored note"
           ),
         {:ok, pointer} <-
           ProductionStore.register_candidate(repo, %{
             owner_id: owner,
             project_id: project_id,
             candidate_id: candidate.id,
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             kind: "note",
             resource_id: note_id,
             metadata: %{"action" => "delete"}
           }) do
      {:ok, %{candidate: candidate, pointer: pointer, note_id: note_id}}
    else
      {:error, _} = error -> error
    end
  end

  def save_cast_rename_candidate(
        repo,
        owner,
        project_id,
        base_revision_id,
        character_id,
        new_name
      ) do
    new_name = if is_binary(new_name), do: String.trim(new_name), else: ""

    with true <- new_name != "" or {:error, :character_name_required},
         {:ok, project} <- Store.project(repo, owner, project_id),
         {:ok, base} <- current_editable_base(repo, project, base_revision_id),
         {:ok, plan} <- Screenplay.plan_character_rename(base, character_id, new_name),
         operation <- %{
           "kind" => "rename_character",
           "target" => %{"kind" => "character", "id" => character_id},
           "value" => %{"name" => new_name, "mention_ids" => []}
         },
         {:ok, candidate_screenplay, _changes} <-
           Screenplay.apply(base, [operation], actor: "writer:#{owner}"),
         {:ok, candidate} <-
           Persistence.save_edit_candidate(repo, project["key"], candidate_screenplay,
             expected_revision: base.revision.id,
             operations: [operation],
             label: "Character rename"
           ),
         {:ok, pointer} <-
           ProductionStore.register_candidate(repo, %{
             owner_id: owner,
             project_id: project_id,
             candidate_id: candidate.id,
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             kind: "cast",
             resource_id: character_id,
             metadata: %{
               "new_name" => new_name,
               "confirmed_cue_count" => length(plan.cue_operations),
               "suggested_mentions_require_review" => length(plan.review)
             }
           }) do
      {:ok, %{candidate: candidate, pointer: pointer, plan: plan}}
    else
      false -> {:error, :character_name_required}
      {:error, _} = error -> error
    end
  end

  def accept_tool_candidate(repo, owner, candidate_id, approval_id)
      when is_binary(candidate_id) and is_binary(approval_id) do
    with {:ok, pointer} <- ProductionStore.candidate(repo, owner, candidate_id),
         {:ok, project} <- Store.project(repo, owner, pointer["project_id"]),
         {:ok, head} <- Persistence.load(repo, project["key"]),
         true <- head.id == pointer["screenplay_id"] or {:error, :candidate_screenplay_mismatch},
         true <-
           head.revision.id == pointer["base_revision_id"] or {:error, :candidate_base_stale},
         {:ok, candidate} <- Persistence.candidate(repo, candidate_id),
         true <-
           candidate["screenplay_id"] == pointer["screenplay_id"] or
             {:error, :candidate_screenplay_mismatch},
         true <-
           candidate["base_revision_id"] == pointer["base_revision_id"] or
             {:error, :candidate_base_mismatch},
         {:ok, principal} <- Principal.new(:human, owner),
         {:ok, authority} <- Authority.new(principal, pointer["screenplay_id"], [:approve]),
         {:ok, approval} <- Approval.direct(candidate, principal, approval_id),
         {:ok, accepted} <-
           Persistence.accept_candidate(repo, candidate_id,
             approval: approval,
             authority: authority
           ) do
      {:ok, accepted}
    else
      false -> {:error, :candidate_identity_mismatch}
      {:error, _} = error -> error
    end
  end

  def list_tool_candidates(repo, owner, project_id),
    do: ProductionStore.list_candidates(repo, owner, project_id, limit: 30)

  def create_table_read(repo, owner, workspace, selection)
      when is_map(workspace) and is_map(selection) do
    with {:ok, packet} <- TableRead.packet(workspace.screenplay, selection),
         {:ok, row} <-
           ProductionStore.create_table_read(repo, %{
             owner_id: owner,
             project_id: workspace.project["id"],
             run_id: workspace.run["id"],
             screenplay_id: workspace.screenplay.id,
             revision_id: workspace.screenplay.revision.id,
             packet_id: packet["id"],
             packet: packet
           }) do
      {:ok, row}
    end
  end

  def update_table_read(repo, owner, id, expected_version, attrs) when is_map(attrs) do
    bookmark = Map.get(attrs, :bookmark_index) || Map.get(attrs, "bookmark_index")

    with {:ok, row} <- ProductionStore.table_read(repo, owner, id),
         true <- row["version"] == expected_version or {:error, {:stale_table_read, row}},
         :ok <- validate_bookmark(row, bookmark) do
      ProductionStore.update_table_read(repo, owner, id, expected_version, attrs)
    else
      {:error, _} = error -> error
    end
  end

  def record_table_reaction(repo, owner, id, expected_version, attrs) do
    with {:ok, row} <- ProductionStore.table_read(repo, owner, id),
         true <- row["version"] == expected_version or {:error, {:stale_table_read, row}},
         {:ok, packet} <- TableRead.record_reaction(row["packet"], attrs) do
      ProductionStore.update_table_read(repo, owner, id, expected_version, %{
        packet: packet,
        bookmark_index: row["bookmark_index"],
        elapsed_ms: row["elapsed_ms"],
        scroll_mode: row["scroll_mode"]
      })
    else
      {:error, _} = error -> error
    end
  end

  def table_reads(repo, owner, project_id),
    do: ProductionStore.list_table_reads(repo, owner, project_id, limit: 30)

  def tts_status do
    enabled? = Application.get_env(:fount_web, :table_read_tts_enabled, false)
    executable = System.find_executable("espeak")

    cond do
      not enabled? ->
        %{available?: false, label: "Unavailable — optional TTS is not configured."}

      is_nil(executable) ->
        %{available?: false, label: "Unavailable — configured TTS executable was not found."}

      true ->
        %{available?: true, label: "Available — local espeak renderer configured."}
    end
  end

  def create_usefulness(repo, owner, workspace, attrs) when is_map(attrs) do
    record_attrs = %{
      "task_id" => String.trim(Map.get(attrs, "task_id", "")),
      "condition" => Map.get(attrs, "condition", "fount_assisted"),
      "outcome" => Map.get(attrs, "outcome", "neutral"),
      "kept_original" => truthy?(Map.get(attrs, "kept_original")),
      "preference" => blank_to_nil(Map.get(attrs, "preference")),
      "friction" => split_lines(Map.get(attrs, "friction")),
      "notes" => split_lines(Map.get(attrs, "notes")),
      "dimensions" => normalize_dimensions(Map.get(attrs, "dimensions", %{})),
      "output_refs" => split_lines(Map.get(attrs, "output_refs")),
      "engineering" => engineering_facts(workspace)
    }

    with {:ok, record} <- Usefulness.record(record_attrs),
         {:ok, row} <-
           ProductionStore.create_usefulness(repo, %{
             owner_id: owner,
             project_id: workspace.project["id"],
             run_id: workspace.run["id"],
             screenplay_id: workspace.screenplay.id,
             revision_id: workspace.screenplay.revision.id,
             task_id: record["task_id"],
             condition: record["condition"],
             record: record
           }) do
      {:ok, row}
    end
  end

  def usefulness_report(repo, owner, project_id) do
    rows = ProductionStore.list_usefulness(repo, owner, project_id, limit: 100)

    if is_list(rows) do
      records = Enum.map(rows, & &1["record"])

      with {:ok, report} <- Usefulness.report(records) do
        {:ok,
         Map.merge(report, %{
           "sample_size" => length(records),
           "sample_label" => sample_label(records),
           "missing_data_label" => missing_data_label(records)
         })}
      end
    else
      rows
    end
  end

  def delete_usefulness(repo, owner, id), do: ProductionStore.delete_usefulness(repo, owner, id)

  def project_cards(repo, owner, projects, runs) when is_list(projects) and is_list(runs) do
    Enum.map(projects, fn project ->
      head =
        case Persistence.load(repo, project["key"]) do
          {:ok, screenplay} -> screenplay
          _ -> nil
        end

      index = if head, do: ScreenplayIndex.build(head), else: nil
      latest_run = Enum.find(runs, &(get_in(&1, ["project", "project_id"]) == project["id"]))
      activity = ProductionStore.recent_activity(repo, owner, project["id"], limit: 6)

      %{
        project: project,
        revision_id: head && head.revision.id,
        scene_count: index && length(index.scenes),
        cast_count: head && map_size(head.cast),
        note_count: head && length(Query.authored_items(head, :note)),
        page_estimate: index && index.estimates.pages.label,
        latest_run: latest_run,
        recent_activity: if(is_list(activity), do: activity, else: []),
        import_fidelity: project["import_fidelity"] || %{}
      }
    end)
  end

  def filter_cards(cards, query, sort) do
    query = query |> to_string() |> String.trim() |> String.downcase()

    cards =
      Enum.filter(cards, fn card ->
        project = card.project

        query == "" or
          String.contains?(
            String.downcase(
              (project["title"] || "") <>
                " " <> (project["key"] || "") <> " " <> (project["synopsis"] || "")
            ),
            query
          )
      end)

    case sort do
      "title" -> Enum.sort_by(cards, &String.downcase(&1.project["title"] || ""))
      "scenes" -> Enum.sort_by(cards, &{-(&1.scene_count || 0), &1.project["title"] || ""})
      _ -> cards
    end
  end

  defp search_opts(screenplay, attrs) do
    with {:ok, scene_ids} <- search_scene_scope(screenplay, attrs),
         {:ok, element_types} <- type_filter(Map.get(attrs, "element_type", "")),
         {:ok, limit} <- integer_limit(Map.get(attrs, "limit", "50")) do
      {:ok,
       [
         scene_ids: scene_ids,
         element_types: element_types,
         include_omitted: truthy?(Map.get(attrs, "include_omitted")),
         include_notes: truthy?(Map.get(attrs, "include_notes")),
         include_boneyards: truthy?(Map.get(attrs, "include_boneyards")),
         limit: limit
       ]
       |> Enum.reject(fn {_key, value} -> is_nil(value) end)}
    end
  end

  defp search_scene_scope(screenplay, attrs) do
    with {:ok, explicit} <- scene_filter(screenplay, Map.get(attrs, "scene_id", "")),
         {:ok, character} <-
           character_scene_filter(screenplay, Map.get(attrs, "character_id", "")),
         {:ok, location} <- location_scene_filter(screenplay, Map.get(attrs, "location", "")) do
      scopes = Enum.reject([explicit, character, location], &is_nil/1)

      scene_ids =
        case scopes do
          [] -> nil
          [first | rest] -> Enum.reduce(rest, first, &Enum.filter(&2, fn id -> id in &1 end))
        end

      {:ok, scene_ids}
    end
  end

  defp scene_filter(_screenplay, value) when value in [nil, ""], do: {:ok, nil}

  defp scene_filter(screenplay, id) do
    if Query.scene(screenplay, id), do: {:ok, [id]}, else: {:error, :unknown_scene}
  end

  defp character_scene_filter(_screenplay, value) when value in [nil, ""], do: {:ok, nil}

  defp character_scene_filter(screenplay, id) do
    if Query.character(screenplay, id) do
      {:ok, screenplay |> Query.scenes_with_character(id) |> Enum.map(& &1.id)}
    else
      {:error, :unknown_character}
    end
  end

  defp location_scene_filter(_screenplay, value) when value in [nil, ""], do: {:ok, nil}

  defp location_scene_filter(screenplay, location) do
    case Enum.find(location_profiles(screenplay), &(&1.location == location)) do
      nil -> {:error, :unknown_location}
      group -> {:ok, group.scene_ids}
    end
  end

  defp type_filter(value) when value in [nil, ""], do: {:ok, nil}

  defp type_filter(value) when value in @search_types,
    do: {:ok, [String.to_existing_atom(value)]}

  defp type_filter(_), do: {:error, :invalid_element_types}

  defp integer_limit(value) when is_integer(value) and value in 1..200, do: {:ok, value}

  defp integer_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..200 -> {:ok, limit}
      _ -> {:error, :invalid_limit}
    end
  end

  defp integer_limit(_), do: {:error, :invalid_limit}

  defp search_filter_summary(attrs) do
    Map.take(
      attrs,
      ~w(scene_id character_id location element_type include_omitted include_notes include_boneyards limit)
    )
  end

  defp editable_revision?(repo, project, screenplay) do
    case Persistence.load(repo, project["key"]) do
      {:ok, head} -> head.id == screenplay.id and head.revision.id == screenplay.revision.id
      _ -> false
    end
  end

  defp current_editable_base(repo, project, expected_revision_id) do
    with {:ok, head} <- Persistence.load(repo, project["key"]),
         true <- head.id == project["screenplay_id"] or {:error, :project_screenplay_mismatch},
         true <-
           head.revision.id == expected_revision_id or
             {:error, {:stale_revision, head.revision.id}} do
      {:ok, head}
    else
      {:error, _} = error -> error
    end
  end

  defp note_operation(base, owner, target, attrs) do
    text = attrs |> Map.get("text", "") |> String.trim()
    title = attrs |> Map.get("title", "") |> String.trim()
    id = blank_to_nil(Map.get(attrs, "id"))

    cond do
      text == "" ->
        {:error, :note_text_required}

      byte_size(text) > 20_000 ->
        {:error, :note_too_large}

      is_binary(id) and is_nil(base.authored_items[id]) ->
        {:error, :note_not_found}

      true ->
        identity =
          if id,
            do: %{"id" => id},
            else: %{"local_id" => "new:note-#{String.slice(Fount.ID.v4(), 0, 8)}"}

        value = %{
          "title" => title,
          "text" => text,
          "target_sha256" => target_fingerprint(base, target),
          "bound_revision_id" => base.revision.id
        }

        item =
          Map.merge(identity, %{
            "namespace" => "fount.writer",
            "kind" => "note",
            "target" => target,
            "value" => value,
            "dependencies" => [target],
            "status" => "active",
            "provenance" => %{
              "producer" => "writer",
              "author_id" => owner,
              "source" => "fount_web.phase08"
            }
          })

        {:ok, %{"kind" => "put_authored_item", "value" => item}}
    end
  end

  defp resulting_note_id(_base, _candidate, id) when is_binary(id) and id != "", do: id

  defp resulting_note_id(base, candidate, _id) do
    (Map.keys(candidate.authored_items) -- Map.keys(base.authored_items)) |> List.first()
  end

  defp parse_target(model, raw) when is_binary(raw) do
    case String.split(raw, ":", parts: 2) do
      [kind, id]
      when kind in ~w(screenplay scene element character dialogue_block) and id != "" ->
        target = %{"kind" => kind, "id" => id}

        case Target.resolve(model, target) do
          {:ok, _} -> {:ok, target}
          {:error, _} -> {:error, :missing_target}
        end

      _ ->
        {:error, :invalid_target}
    end
  end

  defp parse_target(_, _), do: {:error, :invalid_target}

  defp note_projection(model, item) do
    target_state = note_target_state(model, item)

    %{
      id: item["id"],
      namespace: item["namespace"],
      target: item["target"],
      stored_status: item["status"],
      target_state: target_state,
      title: get_in(item, ["value", "title"]),
      text: get_in(item, ["value", "text"]),
      bound_revision_id: get_in(item, ["value", "bound_revision_id"]),
      target_sha256: get_in(item, ["value", "target_sha256"]),
      dependencies: item["dependencies"] || [],
      provenance: item["provenance"] || %{}
    }
  end

  defp note_target_state(_model, %{"status" => "unresolved"}), do: "unresolved"

  defp note_target_state(model, item) do
    with {:ok, _} <- Target.resolve(model, item["target"]) do
      expected = get_in(item, ["value", "target_sha256"])
      current = target_fingerprint(model, item["target"])

      cond do
        is_nil(expected) -> "active_untracked"
        expected == current -> "active"
        true -> "stale_changed"
      end
    else
      _ -> "unresolved"
    end
  end

  defp target_fingerprint(_model, %{"kind" => "screenplay", "id" => id}),
    do: CanonicalJSON.hash(%{"kind" => "screenplay", "id" => id})

  defp target_fingerprint(model, %{"kind" => "revision", "id" => id}),
    do:
      CanonicalJSON.hash(%{
        "kind" => "revision",
        "id" => id,
        "current" => model.revision.id == id
      })

  defp target_fingerprint(model, %{"kind" => "scene"} = target) do
    with {:ok, scene} <- Target.resolve(model, target) do
      elements = Enum.map(scene.element_ids, &Query.node(model, &1))
      CanonicalJSON.hash(%{"scene" => Model.plain(scene), "elements" => Model.plain(elements)})
    else
      _ -> nil
    end
  end

  defp target_fingerprint(model, target) do
    case Target.resolve(model, target) do
      {:ok, value} -> CanonicalJSON.hash(Model.plain(value))
      _ -> nil
    end
  end

  defp relationship_evidence(model, character_id) do
    model.annotations
    |> Map.values()
    |> Enum.filter(fn annotation ->
      kind = to_string(annotation.kind)

      kind in ["relationship", "character_relationship"] and
        Enum.any?(annotation.dependencies || [], fn dependency ->
          dependency == character_id or
            dependency == %{"kind" => "character", "id" => character_id}
        end)
    end)
    |> Enum.map(&Model.plain/1)
  end

  defp dialogue_word_count(model, blocks) do
    blocks
    |> Enum.flat_map(& &1.body_ids)
    |> Enum.map(&Query.node(model, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" ", &(&1.text || ""))
    |> String.split(~r/\s+/u, trim: true)
    |> length()
  end

  defp alias_text(%{alias: value}), do: value
  defp alias_text(%{"alias" => value}), do: value
  defp alias_text(value) when is_binary(value), do: value
  defp alias_text(value), do: inspect(value)

  defp engineering_facts(workspace) do
    usage = List.wrap(workspace.progress["usage"])

    %{
      "completed" => workspace.run["status"] in @completed_statuses,
      "elapsed_ms" => nil,
      "errors" => if(workspace.run["status"] == "failed", do: ["run_failed"], else: []),
      "retries" => Enum.count(usage, fn row -> (row["attempt_number"] || 1) > 1 end),
      "resource_usage" => %{
        "run_id" => workspace.run["id"],
        "run_status" => workspace.run["status"],
        "revision_id" => workspace.screenplay.revision.id,
        "resources" => workspace.progress["resources"] || %{},
        "usage" => usage
      }
    }
  end

  defp sample_label([]), do: "No human response records have been saved."
  defp sample_label([_]), do: "1 saved human response; no representativeness claim."

  defp sample_label(records),
    do: "#{length(records)} saved human responses; no representativeness claim."

  defp missing_data_label(records) do
    missing =
      Enum.count(records, fn record ->
        response = record["human_response"] || %{}

        is_nil(response["preference"]) and response["notes"] in [nil, []] and
          response["dimensions"] in [nil, %{}]
      end)

    "#{missing} of #{length(records)} records omit optional preference/notes/dimensions."
  end

  defp note_target(attrs) do
    case blank_to_nil(Map.get(attrs, "target_override")) do
      nil -> Map.get(attrs, "target", "")
      target -> target
    end
  end

  defp validate_bookmark(row, value) when is_integer(value) and value >= 0 do
    max_index = max(length(get_in(row, ["packet", "turns"]) || []) - 1, 0)
    if value <= max_index, do: :ok, else: {:error, :bookmark_out_of_range}
  end

  defp validate_bookmark(_row, _value), do: {:error, :invalid_bookmark}

  defp normalize_dimensions(value) when is_map(value) do
    value
    |> Map.take(@usefulness_dimensions)
    |> Enum.reduce(%{}, fn {key, item}, acc ->
      case normalize_dimension(key, item) do
        nil -> acc
        normalized -> Map.put(acc, key, normalized)
      end
    end)
  end

  defp normalize_dimensions(_), do: %{}

  defp normalize_dimension("rejection_time_ms", value) when is_integer(value) and value >= 0,
    do: value

  defp normalize_dimension("rejection_time_ms", value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number >= 0 -> number
      _ -> nil
    end
  end

  defp normalize_dimension(_key, value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_dimension(_key, value) when is_number(value) or is_boolean(value), do: value
  defp normalize_dimension(_key, _value), do: nil

  defp truthy?(value), do: value in [true, "true", "1", "on", 1]

  defp split_lines(nil), do: []

  defp split_lines(value) when is_binary(value) do
    value
    |> String.split(~r/[\r\n]+/u, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_lines(value) when is_list(value), do: value
  defp split_lines(value), do: [to_string(value)]

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(_), do: nil

  defp snippet(text, phrase) when is_binary(text) and is_binary(phrase) do
    max_chars = 240

    if String.length(text) <= max_chars do
      text
    else
      case Regex.run(Regex.compile!(Regex.escape(phrase), "iu"), text, return: :index) do
        [{byte_offset, byte_length}] ->
          prefix_chars = text |> binary_part(0, byte_offset) |> String.length()
          match_chars = text |> binary_part(byte_offset, byte_length) |> String.length()
          width = min(max(max_chars, match_chars + 40), 500)
          start_char = max(prefix_chars - div(max(width - match_chars, 0), 2), 0)
          body = String.slice(text, start_char, width)
          leading = if start_char > 0, do: "…", else: ""
          trailing = if start_char + String.length(body) < String.length(text), do: "…", else: ""
          leading <> body <> trailing

        _ ->
          String.slice(text, 0, max_chars) <> "…"
      end
    end
  end

  defp snippet(text, _phrase), do: to_string(text)
end
