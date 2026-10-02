defmodule FountWeb.SemanticStore do
  @moduledoc "Source-bound semantic inventory and manual review persistence for SI01."

  alias Ecto.Adapters.SQL
  alias Fount.Semantics.{SourceInventory, SourceReview}
  alias Fount.Screenplay.Model

  @manual_schema SourceInventory.schema_version()

  def ensure_inventory(repo, owner, project, screenplay)
      when is_binary(owner) and is_map(project) do
    binding = source_binding(screenplay)
    inventory = SourceInventory.build(screenplay)
    assessment_id = assessment_id(project, screenplay, binding.source_sha256)

    case assessment(repo, owner, project["id"], assessment_id) do
      {:ok, row} ->
        {:ok, row}

      {:error, :not_found} ->
        create_inventory(repo, owner, project, screenplay, binding, inventory, assessment_id)

      {:error, _} = error ->
        error
    end
  end

  def assessment(repo, owner, project_id, assessment_id) do
    case query(
           repo,
           "SELECT * FROM fount_web_semantic_assessments WHERE owner_id=$1 AND project_id=$2::text::uuid AND id=$3::text::uuid",
           [owner, project_id, assessment_id]
         ) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def assessment_for_revision(repo, owner, project_id, revision_id) do
    case query(
           repo,
           """
           SELECT * FROM fount_web_semantic_assessments
           WHERE owner_id=$1 AND project_id=$2::text::uuid AND revision_id=$3::text::uuid
             AND schema_version=$4 AND origin='manual'
           ORDER BY inserted_at DESC,id LIMIT 1
           """,
           [owner, project_id, revision_id, @manual_schema]
         ) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def entities(repo, assessment_id) do
    query(
      repo,
      """
      SELECT ae.*,h.owner_id,h.project_id::text,h.screenplay_id::text,h.created_origin
      FROM fount_web_semantic_assessment_entities ae
      JOIN fount_web_semantic_entity_handles h ON h.id=ae.handle_id
      WHERE ae.assessment_id=$1::text::uuid
      ORDER BY ae.local_id
      """,
      [assessment_id]
    )
  end

  def review_history(repo, owner, project_id, assessment_id) do
    query(
      repo,
      """
      SELECT * FROM fount_web_semantic_review_events
      WHERE owner_id=$1 AND project_id=$2::text::uuid AND assessment_id=$3::text::uuid
      ORDER BY inserted_at,id
      """,
      [owner, project_id, assessment_id]
    )
  end

  def current_version(repo, owner, project_id, assessment_id) do
    case SQL.query(
           repo,
           """
           SELECT COALESCE(MAX(new_version),0)
           FROM fount_web_semantic_review_events
           WHERE owner_id=$1 AND project_id=$2::text::uuid AND assessment_id=$3::text::uuid
             AND outcome='applied'
           """,
           [owner, project_id, assessment_id],
           log: false
         ) do
      {:ok, %{rows: [[version]]}} -> {:ok, version}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def review(repo, owner, project_id, assessment_id, attrs)
      when is_binary(owner) and is_binary(project_id) and is_binary(assessment_id) and is_map(attrs) do
    command = %{
      "action" => attrs["action"],
      "target_handle_id" => attrs["target_handle_id"],
      "payload" => attrs["payload"] || %{}
    }

    with :ok <- SourceReview.validate_command(command),
         expected when is_integer(expected) and expected >= 0 <- attrs["expected_version"],
         command_id when is_binary(command_id) and command_id != "" <- attrs["command_id"],
         actor when is_binary(actor) and actor != "" <- attrs["actor"] do
      do_review(repo, owner, project_id, assessment_id, command, expected, command_id, actor)
    else
      false -> {:error, :invalid_review_command}
      nil -> {:error, :invalid_review_command}
      {:error, _} = error -> error
      _ -> {:error, :invalid_review_command}
    end
  end

  def review(_, _, _, _, _), do: {:error, :invalid_review_command}

  defp create_inventory(repo, owner, project, screenplay, binding, inventory, assessment_id) do
    result = Model.plain(inventory)
    request_fingerprint =
      Fount.ID.hash([
        owner,
        project["id"],
        screenplay.id,
        screenplay.revision.id,
        binding.source_sha256,
        @manual_schema
      ])

    coverage = %{
      "literal_character_cues" => length(inventory.character_cues),
      "literal_scene_headings" => length(inventory.scene_headings),
      "complete" => true
    }

    transaction(repo, fn ->
      SQL.query!(repo, "SELECT pg_advisory_xact_lock(hashtext($1))", ["semantic-inventory:" <> assessment_id], log: false)

      case assessment(repo, owner, project["id"], assessment_id) do
        {:ok, row} ->
          row

        {:error, :not_found} ->
          row =
            SQL.query!(
              repo,
              """
              INSERT INTO fount_web_semantic_assessments(
                id,owner_id,project_id,screenplay_id,revision_id,source_artifact_id,source_sha256,render_sha256,
                request_fingerprint,schema_version,prompt_version,parser_version,model,reasoning_effort,provider_family,
                provider_returned_model,run_id,origin,status,coverage,result,usage,limits,provenance,inserted_at,updated_at
              ) VALUES(
                $1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6::text::uuid,$7,$8,$9,$10,NULL,$11,
                NULL,NULL,NULL,NULL,NULL,'manual','ready',$12::jsonb,$13::jsonb,'{}'::jsonb,'{}'::jsonb,$14::jsonb,now(),now()
              ) RETURNING *
              """,
              [
                assessment_id,
                owner,
                project["id"],
                screenplay.id,
                screenplay.revision.id,
                binding.source_artifact_id,
                binding.source_sha256,
                screenplay.revision.render_hash,
                request_fingerprint,
                @manual_schema,
                Fount.version(),
                coverage,
                result,
                %{
                  "origin" => "manual",
                  "representation" => "source_inventory",
                  "source_name" => project["source_name"]
                }
              ],
              log: false
            )
            |> one()

          insert_inventory_entities(repo, owner, project, screenplay, assessment_id, inventory)
          row

        {:error, reason} ->
          repo.rollback(reason)
      end
    end)
  end

  defp insert_inventory_entities(repo, owner, project, screenplay, assessment_id, inventory) do
    items = inventory.character_cues ++ inventory.scene_headings

    Enum.each(items, fn item ->
      handle_id = Fount.ID.v5(assessment_id, ["source-handle:", item.local_id])

      SQL.query!(
        repo,
        """
        INSERT INTO fount_web_semantic_entity_handles(id,owner_id,project_id,screenplay_id,kind,created_origin,inserted_at,updated_at)
        VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5,'manual',now(),now())
        ON CONFLICT(id) DO NOTHING
        """,
        [handle_id, owner, project["id"], screenplay.id, item.kind],
        log: false
      )

      label =
        case item.kind do
          "location" -> get_in(item, [:parts, :location]) || item.literal
          _ -> item.literal
        end

      SQL.query!(
        repo,
        """
        INSERT INTO fount_web_semantic_assessment_entities(
          assessment_id,local_id,handle_id,kind,label,payload,evidence,inserted_at,updated_at
        ) VALUES($1::text::uuid,$2,$3::text::uuid,$4,$5,$6::jsonb,$7::jsonb,now(),now())
        ON CONFLICT(assessment_id,local_id) DO NOTHING
        """,
        [assessment_id, item.local_id, handle_id, item.kind, label, Model.plain(item), Model.plain(item.evidence)],
        log: false
      )
    end)
  end

  defp do_review(repo, owner, project_id, assessment_id, command, expected, command_id, actor) do
    transaction(repo, fn ->
      SQL.query!(
        repo,
        "SELECT pg_advisory_xact_lock(hashtext($1))",
        ["semantic-review:" <> owner <> ":" <> project_id <> ":" <> assessment_id],
        log: false
      )

      case existing_command(repo, owner, project_id, command_id) do
        {:ok, row} ->
          if command_binding_matches?(row, assessment_id, command, expected, actor),
            do: row,
            else: repo.rollback(:command_id_conflict)

        {:error, :not_found} ->
          with {:ok, assessment} <- assessment(repo, owner, project_id, assessment_id),
               :ok <- ensure_current_revision(repo, assessment),
               :ok <- validate_review_references(repo, assessment, command),
               {:ok, version} <- current_version(repo, owner, project_id, assessment_id) do
            if expected == version do
              payload = maybe_allocate_split_handle(repo, assessment, command)
              insert_review_event(repo, assessment, command, payload, expected, version + 1, "applied", command_id, actor)
            else
              insert_review_event(repo, assessment, command, command["payload"], expected, version, "conflict", command_id, actor)
            end
          else
            {:error, reason} -> repo.rollback(reason)
          end

        {:error, reason} ->
          repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, %{"outcome" => "conflict"} = row} -> {:error, {:stale_review, row}}
      {:ok, row} -> {:ok, row}
      {:error, _} = error -> error
    end
  end

  defp ensure_current_revision(repo, assessment) do
    case query(
           repo,
           "SELECT 1 AS current FROM screenplays WHERE id=$1::text::uuid AND head_revision_id=$2::text::uuid",
           [assessment["screenplay_id"], assessment["revision_id"]]
         ) do
      [_] -> :ok
      [] -> {:error, :semantic_revision_stale}
      {:error, _} = error -> error
    end
  end

  defp validate_review_references(repo, assessment, command) do
    action = command["action"]
    target = command["target_handle_id"]
    payload = command["payload"]

    if action == "undo" do
      validate_undo(repo, assessment, payload)
    else
      with :ok <- ensure_handle(repo, assessment, target),
           {:ok, projection} <- review_projection(repo, assessment),
           %{} = entity <- Enum.find(projection, &(&1.handle_id == target)) || {:error, :invalid_review_target},
           :ok <- validate_projected_action(action, entity, payload, projection) do
        :ok
      else
        {:error, _} = error -> error
        _ -> {:error, :invalid_review_target}
      end
    end
  end

  defp validate_undo(repo, assessment, %{"event_id" => id}) do
    case query(
           repo,
           "SELECT id FROM fount_web_semantic_review_events WHERE id=$1::text::uuid AND assessment_id=$2::text::uuid AND outcome='applied'",
           [id, assessment["id"]]
         ) do
      [_] -> :ok
      _ -> {:error, :invalid_undo_event}
    end
  end

  defp validate_projected_action("merge", entity, %{"into_handle_id" => id}, projection) do
    case Enum.find(projection, &(&1.handle_id == id)) do
      %{kind: kind} when kind == entity.kind and id != entity.handle_id -> :ok
      _ -> {:error, :invalid_merge_target}
    end
  end

  defp validate_projected_action("split", entity, %{"local_ids" => local_ids}, _projection) do
    available = MapSet.new(Enum.map(entity.occurrences, & &1.local_id))
    requested = MapSet.new(local_ids)

    if MapSet.size(requested) > 0 and MapSet.subset?(requested, available),
      do: :ok,
      else: {:error, :invalid_split_occurrences}
  end

  defp validate_projected_action("resolve_occurrence", entity, %{"local_id" => local_id}, _projection) do
    if Enum.any?(entity.occurrences, &(&1.local_id == local_id)),
      do: :ok,
      else: {:error, :invalid_occurrence}
  end

  defp validate_projected_action("set_location_parent", %{kind: "location"} = entity, %{"parent_handle_id" => id}, projection) do
    case Enum.find(projection, &(&1.handle_id == id)) do
      %{kind: "location"} when id != entity.handle_id ->
        if location_parent_cycle?(projection, entity.handle_id, id),
          do: {:error, :location_parent_cycle},
          else: :ok

      _ ->
        {:error, :invalid_location_parent}
    end
  end

  defp location_parent_cycle?(projection, child_id, candidate_parent_id) do
    by_id = Map.new(projection, &{&1.handle_id, &1})
    parent_chain_reaches?(by_id, candidate_parent_id, child_id, MapSet.new())
  end

  defp parent_chain_reaches?(_by_id, nil, _wanted, _seen), do: false
  defp parent_chain_reaches?(_by_id, current, wanted, _seen) when current == wanted, do: true

  defp parent_chain_reaches?(by_id, current, wanted, seen) do
    cond do
      MapSet.member?(seen, current) -> true
      is_nil(by_id[current]) -> false
      true -> parent_chain_reaches?(by_id, by_id[current].parent_handle_id, wanted, MapSet.put(seen, current))
    end
  end

  defp validate_projected_action("set_location_parent", _entity, _payload, _projection),
    do: {:error, :invalid_location_parent}

  defp validate_projected_action("set_time", %{kind: "location"}, _payload, _projection), do: :ok
  defp validate_projected_action("set_time", _entity, _payload, _projection), do: {:error, :invalid_time_target}
  defp validate_projected_action(_action, _entity, _payload, _projection), do: :ok

  defp review_projection(repo, assessment) do
    entities = entities(repo, assessment["id"])
    history = review_history(repo, assessment["owner_id"], assessment["project_id"], assessment["id"])

    cond do
      not is_list(entities) -> entities
      not is_list(history) -> history
      true -> {:ok, FountWeb.SemanticContext.project_entities(entities, history)}
    end
  end

  defp ensure_handle(repo, assessment, handle_id) do
    case query(
           repo,
           """
           SELECT h.id FROM fount_web_semantic_entity_handles h
           WHERE h.id=$1::text::uuid AND h.owner_id=$2 AND h.project_id=$3::text::uuid AND h.screenplay_id=$4::text::uuid
             AND (
               EXISTS(
                 SELECT 1 FROM fount_web_semantic_assessment_entities ae
                 WHERE ae.assessment_id=$5::text::uuid AND ae.handle_id=h.id
               )
               OR EXISTS(
                 SELECT 1 FROM fount_web_semantic_review_events re
                 WHERE re.assessment_id=$5::text::uuid AND re.outcome='applied'
                   AND re.action='split' AND re.payload->>'new_handle_id'=h.id::text
               )
             )
           """,
           [handle_id, assessment["owner_id"], assessment["project_id"], assessment["screenplay_id"], assessment["id"]]
         ) do
      [_] -> :ok
      _ -> {:error, :invalid_review_target}
    end
  end

  defp maybe_allocate_split_handle(repo, assessment, %{"action" => "split", "target_handle_id" => target, "payload" => payload}) do
    new_handle_id = Fount.ID.v4()

    kind =
      case query(
             repo,
             "SELECT kind FROM fount_web_semantic_entity_handles WHERE id=$1::text::uuid",
             [target]
           ) do
        [%{"kind" => kind}] -> kind
        _ -> repo.rollback(:invalid_review_target)
      end

    SQL.query!(
      repo,
      """
      INSERT INTO fount_web_semantic_entity_handles(id,owner_id,project_id,screenplay_id,kind,created_origin,inserted_at,updated_at)
      VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5,'manual',now(),now())
      """,
      [new_handle_id, assessment["owner_id"], assessment["project_id"], assessment["screenplay_id"], kind],
      log: false
    )

    Map.put(payload, "new_handle_id", new_handle_id)
  end

  defp maybe_allocate_split_handle(_repo, _assessment, %{"payload" => payload}), do: payload

  defp insert_review_event(repo, assessment, command, payload, expected, new_version, outcome, command_id, actor) do
    SQL.query!(
      repo,
      """
      INSERT INTO fount_web_semantic_review_events(
        id,owner_id,project_id,screenplay_id,revision_id,assessment_id,target_handle_id,action,payload,
        expected_version,new_version,outcome,command_id,actor,provenance,inserted_at,updated_at
      ) VALUES(
        $1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6::text::uuid,$7::text::uuid,$8,$9::jsonb,
        $10,$11,$12,$13,$14,$15::jsonb,now(),now()
      ) RETURNING *
      """,
      [
        Fount.ID.v4(),
        assessment["owner_id"],
        assessment["project_id"],
        assessment["screenplay_id"],
        assessment["revision_id"],
        assessment["id"],
        command["target_handle_id"],
        command["action"],
        payload,
        expected,
        new_version,
        outcome,
        command_id,
        actor,
        %{"source_sha256" => assessment["source_sha256"], "origin" => "manual"}
      ],
      log: false
    )
    |> one()
  end


  defp command_binding_matches?(row, assessment_id, command, expected, actor) do
    stored_payload =
      case command["action"] do
        "split" -> Map.drop(row["payload"] || %{}, ["new_handle_id"])
        _ -> row["payload"] || %{}
      end

    row["assessment_id"] == assessment_id and
      row["action"] == command["action"] and
      row["target_handle_id"] == command["target_handle_id"] and
      stored_payload == command["payload"] and
      row["expected_version"] == expected and
      row["actor"] == actor
  end

  defp existing_command(repo, owner, project_id, command_id) do
    case query(
           repo,
           "SELECT * FROM fount_web_semantic_review_events WHERE owner_id=$1 AND project_id=$2::text::uuid AND command_id=$3",
           [owner, project_id, command_id]
         ) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp assessment_id(project, screenplay, source_sha256) do
    Fount.ID.v5(
      screenplay.id,
      ["semantic-source-inventory:", project["id"], ":", screenplay.revision.id, ":", source_sha256]
    )
  end

  defp source_binding(screenplay) do
    case screenplay.import do
      %{bytes: bytes} = import when is_binary(bytes) ->
        %{source_artifact_id: Map.get(import, :id), source_sha256: Fount.ID.hash(bytes)}

      _ ->
        %{source_artifact_id: nil, source_sha256: screenplay.revision.content_hash}
    end
  end

  defp transaction(repo, fun) do
    case repo.transaction(fun) do
      {:ok, value} -> {:ok, value}
      {:error, %Postgrex.Error{} = error} -> {:error, storage_reason(error)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp query(repo, statement, params) do
    case SQL.query(repo, statement, params, log: false) do
      {:ok, result} -> rows(result)
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  defp one(result), do: result |> rows() |> List.first()

  defp rows(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn values -> columns |> Enum.zip(values) |> Map.new() end)
  end

  defp storage_reason(%Postgrex.Error{postgres: %{code: :undefined_table}}), do: :semantic_schema_missing
  defp storage_reason(%Postgrex.Error{postgres: %{code: :foreign_key_violation}}), do: :source_binding_conflict
  defp storage_reason(%Postgrex.Error{postgres: %{code: :unique_violation}}), do: :conflict
  defp storage_reason(_), do: :storage_error
end
