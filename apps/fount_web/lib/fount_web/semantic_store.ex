defmodule FountWeb.SemanticStore do
  @moduledoc "Source-bound semantic inventory, SI02 assessment history and human review persistence."

  alias Ecto.Adapters.SQL
  alias Fount.Intelligence.ImportAssessment
  alias Fount.Screenplay.Model
  alias Fount.Semantics.{SourceInventory, SourceReview}
  alias Fount.Writing.CanonicalJSON

  @manual_schema SourceInventory.schema_version()
  @model_schema ImportAssessment.schema_version()
  @uuid_columns ~w(id project_id screenplay_id revision_id source_artifact_id run_id assessment_id handle_id target_handle_id supersedes_assessment_id)

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

  @doc "Returns the newest model/fixture assessment row for an exact owned revision, including failed/running attempts."
  def latest_assessment_for_revision(repo, owner, project_id, revision_id) do
    case query(
           repo,
           """
           SELECT * FROM fount_web_semantic_assessments
           WHERE owner_id=$1 AND project_id=$2::text::uuid AND revision_id=$3::text::uuid
             AND schema_version=$4 AND origin IN ('model','deterministic_fixture')
           ORDER BY inserted_at DESC,id DESC LIMIT 1
           """,
           [owner, project_id, revision_id, @model_schema]
         ) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @doc "Returns the newest usable model/fixture result for a revision, otherwise its literal manual inventory."
  def resolved_assessment_for_revision(repo, owner, project_id, revision_id) do
    case query(
           repo,
           """
           SELECT * FROM fount_web_semantic_assessments
           WHERE owner_id=$1 AND project_id=$2::text::uuid AND revision_id=$3::text::uuid
             AND schema_version=$4 AND origin IN ('model','deterministic_fixture')
             AND status IN ('ready','partial')
           ORDER BY inserted_at DESC,id DESC LIMIT 1
           """,
           [owner, project_id, revision_id, @model_schema]
         ) do
      [row] -> {:ok, row}
      [] -> assessment_for_revision(repo, owner, project_id, revision_id)
      {:error, _} = error -> error
    end
  end

  def assessment_history(repo, owner, project_id, revision_id) do
    query(
      repo,
      """
      SELECT * FROM fount_web_semantic_assessments
      WHERE owner_id=$1 AND project_id=$2::text::uuid AND revision_id=$3::text::uuid
      ORDER BY inserted_at DESC,id DESC
      """,
      [owner, project_id, revision_id]
    )
  end

  @doc "Returns model/fixture assessment attempts across project revisions, newest first, for stale/history disclosure."
  def model_assessment_history(repo, owner, project_id) do
    query(
      repo,
      """
      SELECT * FROM fount_web_semantic_assessments
      WHERE owner_id=$1 AND project_id=$2::text::uuid
        AND schema_version=$3 AND origin IN ('model','deterministic_fixture')
      ORDER BY inserted_at DESC,id DESC
      """,
      [owner, project_id, @model_schema]
    )
  end

  @doc "Human interpretation decisions from every assessment of this exact revision, oldest first."
  def review_history_for_revision(repo, owner, project_id, revision_id) do
    query(
      repo,
      """
      SELECT re.* FROM fount_web_semantic_review_events re
      JOIN fount_web_semantic_assessments a ON a.id=re.assessment_id
      WHERE re.owner_id=$1 AND re.project_id=$2::text::uuid AND re.revision_id=$3::text::uuid
        AND a.owner_id=re.owner_id AND a.project_id=re.project_id
      ORDER BY re.new_version,re.inserted_at,re.id
      """,
      [owner, project_id, revision_id]
    )
  end

  @doc "Creates or replays one queued, source-bound SI02 assessment attempt before its Run is bound."
  def reserve_assessment(repo, owner, project, screenplay, attrs)
      when is_binary(owner) and is_map(project) and is_map(attrs) do
    command_id = attrs["command_id"]
    request_fingerprint = attrs["request_fingerprint"]
    origin = attrs["origin"] || "model"

    with :ok <-
           validate_assessment_reservation(
             project,
             screenplay,
             command_id,
             request_fingerprint,
             origin
           ) do
      transaction(repo, fn ->
        SQL.query!(
          repo,
          "SELECT pg_advisory_xact_lock(hashtext($1))",
          ["semantic-assessment:" <> owner <> ":" <> project["id"] <> ":" <> command_id],
          log: false
        )

        reserve_locked(
          repo,
          owner,
          project,
          screenplay,
          attrs,
          command_id,
          request_fingerprint,
          origin
        )
      end)
    end
  end

  defp validate_assessment_reservation(project, screenplay, command_id, fingerprint, origin) do
    cond do
      not (is_binary(command_id) and command_id != "") ->
        {:error, :invalid_command_id}

      not (is_binary(fingerprint) and byte_size(fingerprint) == 64) ->
        {:error, :invalid_request_fingerprint}

      origin not in ["model", "deterministic_fixture"] ->
        {:error, :invalid_assessment_origin}

      project["screenplay_id"] != screenplay.id ->
        {:error, :project_screenplay_mismatch}

      true ->
        :ok
    end
  end

  defp reserve_locked(
         repo,
         owner,
         project,
         screenplay,
         attrs,
         command_id,
         request_fingerprint,
         origin
       ) do
    case assessment_by_command(repo, owner, project["id"], command_id) do
      {:ok, row} ->
        replay_reservation(repo, row, request_fingerprint, screenplay.revision.id)

      {:error, :not_found} ->
        assessment_id =
          Fount.ID.v5(screenplay.id, [
            "semantic-model-assessment:",
            project["id"],
            ":",
            command_id
          ])

        supersedes =
          newest_usable_model_id(repo, owner, project["id"], screenplay.revision.id)

        SQL.query!(
          repo,
          """
          INSERT INTO fount_web_semantic_assessments(
            id,owner_id,project_id,screenplay_id,revision_id,source_artifact_id,source_sha256,render_sha256,
            request_fingerprint,schema_version,prompt_version,parser_version,model,reasoning_effort,provider_family,
            provider_returned_model,run_id,origin,status,coverage,result,usage,limits,provenance,command_id,
            supersedes_assessment_id,error,inserted_at,updated_at
          ) VALUES(
            $1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6::text::uuid,$7,$8,$9,$10,$11,$12,
            $13,$14,$15,NULL,NULL,$16,'queued','{}'::jsonb,'{}'::jsonb,'{}'::jsonb,$17::jsonb,$18::jsonb,$19,
            $20::text::uuid,'{}'::jsonb,now(),now()
          ) RETURNING *
          """,
          [
            assessment_id,
            owner,
            project["id"],
            screenplay.id,
            screenplay.revision.id,
            attrs["source_artifact_id"],
            attrs["source_sha256"],
            attrs["render_sha256"],
            request_fingerprint,
            @model_schema,
            attrs["prompt_version"],
            Fount.version(),
            attrs["model"],
            attrs["reasoning_effort"],
            attrs["provider_family"],
            origin,
            attrs["limits"] || %{},
            attrs["provenance"] || %{},
            command_id,
            supersedes
          ],
          log: false
        )
        |> one()

      {:error, reason} ->
        repo.rollback(reason)
    end
  end

  defp replay_reservation(repo, row, fingerprint, revision_id) do
    if row["request_fingerprint"] == fingerprint and row["revision_id"] == revision_id,
      do: row,
      else: repo.rollback(:command_id_conflict)
  end

  def bind_run(repo, owner, project_id, assessment_id, run_id) do
    case SQL.query(
           repo,
           """
           UPDATE fount_web_semantic_assessments
           SET run_id=$4::text::uuid,updated_at=now()
           WHERE owner_id=$1 AND project_id=$2::text::uuid AND id=$3::text::uuid
             AND (run_id IS NULL OR run_id=$4::text::uuid) AND status='queued'
             AND EXISTS(SELECT 1 FROM fount_runs r JOIN fount_run_plans p ON p.run_id=r.id AND p.version=r.current_plan_version WHERE r.id=$4::text::uuid AND r.screenplay_id=fount_web_semantic_assessments.screenplay_id AND p.base_revision_id=fount_web_semantic_assessments.revision_id)
           RETURNING id
           """,
           [owner, project_id, assessment_id, run_id],
           log: false
         ) do
      {:ok, %{rows: [[_]]}} -> :ok
      {:ok, %{rows: []}} -> {:error, :assessment_run_binding_conflict}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def update_assessment_status(repo, owner, assessment_id, status, error \\ nil, run_id \\ nil)
      when status in ~w(queued running failed cancelled) do
    error = if is_nil(error), do: %{}, else: %{"reason" => to_string(error)}

    case SQL.query(
           repo,
           """
           UPDATE fount_web_semantic_assessments
           SET status=$3,error=$4::jsonb,completed_at=CASE WHEN $3 IN ('failed','cancelled') THEN now() ELSE completed_at END,updated_at=now()
           WHERE owner_id=$1 AND id=$2::text::uuid AND status IN ('queued','running')
             AND ($5::text IS NULL OR run_id=$5::text::uuid)
           RETURNING id
           """,
           [owner, assessment_id, status, error, run_id],
           log: false
         ) do
      {:ok, %{rows: [[_]]}} -> :ok
      {:ok, %{rows: []}} -> {:error, :assessment_state_conflict}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  @doc "Persists source-coverage progress for an in-flight assessment without mutating an immutable result."
  def update_assessment_progress(repo, owner, assessment_id, coverage, run_id \\ nil)
      when is_binary(owner) and is_binary(assessment_id) and is_map(coverage) do
    case SQL.query(
           repo,
           """
           UPDATE fount_web_semantic_assessments
           SET coverage=COALESCE(coverage,'{}'::jsonb) || $3::jsonb,updated_at=now()
           WHERE owner_id=$1 AND id=$2::text::uuid AND status IN ('queued','running')
             AND ($4::text IS NULL OR run_id=$4::text::uuid)
           RETURNING id
           """,
           [owner, assessment_id, coverage, run_id],
           log: false
         ) do
      {:ok, %{rows: [[_]]}} -> :ok
      {:ok, %{rows: []}} -> {:error, :assessment_state_conflict}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  @doc "Atomically persists one validated immutable model result and its stable source-bound entity handles."
  def persist_assessment_result(repo, owner, payload) when is_binary(owner) and is_map(payload) do
    transaction(repo, fn ->
      assessment_id = payload["assessment_id"]

      SQL.query!(
        repo,
        "SELECT pg_advisory_xact_lock(hashtext($1))",
        ["semantic-result:" <> assessment_id],
        log: false
      )

      persist_locked_result(repo, owner, assessment_id, payload)
    end)
  end

  defp persist_locked_result(repo, owner, assessment_id, payload) do
    assessment =
      case query(
             repo,
             "SELECT * FROM fount_web_semantic_assessments WHERE owner_id=$1 AND id=$2::text::uuid FOR UPDATE",
             [owner, assessment_id]
           ) do
        [row] -> row
        [] -> repo.rollback(:assessment_not_found)
        {:error, reason} -> repo.rollback(reason)
      end

    run =
      case query(
             repo,
             "SELECT r.id::text,r.status,r.stop_requested_at,r.screenplay_id::text,p.base_revision_id::text FROM fount_runs r JOIN fount_run_plans p ON p.run_id=r.id AND p.version=r.current_plan_version WHERE r.id=$1::text::uuid FOR UPDATE OF r",
             [payload["run_id"]]
           ) do
        [row] -> row
        [] -> repo.rollback(:assessment_run_not_found)
        {:error, reason} -> repo.rollback(reason)
      end

    validate_result_binding!(repo, assessment, run, payload)
    persist_terminal_or_new(repo, owner, assessment, payload)
  end

  defp validate_result_binding!(repo, assessment, run, payload) do
    cond do
      assessment["run_id"] != payload["run_id"] ->
        repo.rollback(:assessment_run_binding_conflict)

      run["screenplay_id"] != assessment["screenplay_id"] or
          run["base_revision_id"] != assessment["revision_id"] ->
        repo.rollback(:assessment_run_binding_conflict)

      run["status"] in ["stopped", "failed"] or not is_nil(run["stop_requested_at"]) ->
        repo.rollback(:assessment_run_stopped)

      true ->
        :ok
    end
  end

  defp persist_terminal_or_new(repo, _owner, %{"status" => status} = assessment, payload)
       when status in ["ready", "partial"] do
    if CanonicalJSON.hash(assessment["result"] || %{}) ==
         CanonicalJSON.hash(payload["result"] || %{}),
       do: assessment,
       else: repo.rollback(:assessment_result_conflict)
  end

  defp persist_terminal_or_new(repo, owner, %{"status" => status} = assessment, payload)
       when status in ["queued", "running"] do
    assessment_id = assessment["id"]

    SQL.query!(
      repo,
      "DELETE FROM fount_web_semantic_assessment_entities WHERE assessment_id=$1::text::uuid",
      [assessment_id],
      log: false
    )

    insert_model_entities(repo, assessment, payload["result"] || %{})

    usage = %{"completion_trace" => sanitize_usage_trace(payload["usage_trace"] || [])}

    provenance =
      Map.merge(assessment["provenance"] || %{}, %{
        "partial_reason" => payload["partial_reason"],
        "immutable_result" => true
      })

    SQL.query!(
      repo,
      """
      UPDATE fount_web_semantic_assessments
      SET status=$3,coverage=$4::jsonb,result=$5::jsonb,usage=$6::jsonb,provider_returned_model=$7,
          provenance=$8::jsonb,error='{}'::jsonb,completed_at=now(),updated_at=now()
      WHERE owner_id=$1 AND id=$2::text::uuid
      RETURNING *
      """,
      [
        owner,
        assessment_id,
        payload["status"],
        payload["coverage"] || %{},
        payload["result"] || %{},
        usage,
        payload["provider_returned_model"],
        provenance
      ],
      log: false
    )
    |> one()
  end

  defp persist_terminal_or_new(repo, _owner, _assessment, _payload),
    do: repo.rollback(:assessment_state_conflict)

  def entities(repo, assessment_id) do
    query(
      repo,
      """
      SELECT ae.*,h.owner_id,h.project_id::text,h.screenplay_id::text,h.created_origin,sa.origin AS assessment_origin
      FROM fount_web_semantic_assessment_entities ae
      JOIN fount_web_semantic_entity_handles h ON h.id=ae.handle_id
      JOIN fount_web_semantic_assessments sa ON sa.id=ae.assessment_id
      WHERE ae.assessment_id=$1::text::uuid
      ORDER BY ae.local_id
      """,
      [assessment_id]
    )
  end

  @doc "Returns entity rows from every assessment of an exact owned revision, newest assessment first."
  def entity_rows_for_revision(repo, owner, project_id, revision_id) do
    query(
      repo,
      """
      SELECT ae.*,h.owner_id,h.project_id::text,h.screenplay_id::text,h.created_origin,
             sa.origin AS assessment_origin,sa.inserted_at AS assessment_inserted_at
      FROM fount_web_semantic_assessment_entities ae
      JOIN fount_web_semantic_entity_handles h ON h.id=ae.handle_id
      JOIN fount_web_semantic_assessments sa ON sa.id=ae.assessment_id
      WHERE sa.owner_id=$1 AND sa.project_id=$2::text::uuid AND sa.revision_id=$3::text::uuid
        AND h.owner_id=sa.owner_id AND h.project_id=sa.project_id AND h.screenplay_id=sa.screenplay_id
      ORDER BY sa.inserted_at DESC,sa.id DESC,ae.local_id
      """,
      [owner, project_id, revision_id]
    )
  end

  def review_history(repo, owner, project_id, assessment_id) do
    query(
      repo,
      """
      SELECT * FROM fount_web_semantic_review_events
      WHERE owner_id=$1 AND project_id=$2::text::uuid AND assessment_id=$3::text::uuid
      ORDER BY new_version,inserted_at,id
      """,
      [owner, project_id, assessment_id]
    )
  end

  def current_version(repo, owner, project_id, assessment_id) do
    case SQL.query(
           repo,
           """
           SELECT COALESCE(MAX(re.new_version),0)
           FROM fount_web_semantic_review_events re
           JOIN fount_web_semantic_assessments selected
             ON selected.id=$3::text::uuid AND selected.owner_id=$1 AND selected.project_id=$2::text::uuid
           WHERE re.owner_id=$1 AND re.project_id=$2::text::uuid
             AND re.screenplay_id=selected.screenplay_id AND re.revision_id=selected.revision_id
             AND re.outcome='applied'
           """,
           [owner, project_id, assessment_id],
           log: false
         ) do
      {:ok, %{rows: [[version]]}} -> {:ok, version}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def review(repo, owner, project_id, assessment_id, attrs)
      when is_binary(owner) and is_binary(project_id) and is_binary(assessment_id) and
             is_map(attrs) do
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
      SQL.query!(
        repo,
        "SELECT pg_advisory_xact_lock(hashtext($1))",
        ["semantic-inventory:" <> assessment_id],
        log: false
      )

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
        [
          assessment_id,
          item.local_id,
          handle_id,
          item.kind,
          label,
          Model.plain(item),
          Model.plain(item.evidence)
        ],
        log: false
      )
    end)
  end

  defp assessment_by_command(repo, owner, project_id, command_id) do
    case query(
           repo,
           "SELECT * FROM fount_web_semantic_assessments WHERE owner_id=$1 AND project_id=$2::text::uuid AND command_id=$3",
           [owner, project_id, command_id]
         ) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp newest_usable_model_id(repo, owner, project_id, revision_id) do
    case query(
           repo,
           "SELECT id FROM fount_web_semantic_assessments WHERE owner_id=$1 AND project_id=$2::text::uuid AND revision_id=$3::text::uuid AND schema_version=$4 AND status IN ('ready','partial') ORDER BY inserted_at DESC,id DESC LIMIT 1",
           [owner, project_id, revision_id, @model_schema]
         ) do
      [%{"id" => id}] -> id
      _ -> nil
    end
  end

  defp insert_model_entities(repo, assessment, result) do
    literal_index = literal_handle_index(repo, assessment)
    occurrences = result["occurrences"] || []
    headings = result["headings"] || []

    Enum.each(result["entities"] || [], fn entity ->
      entity_occurrences = Enum.filter(occurrences, &(&1["entity_id"] == entity["local_id"]))

      linked_literal =
        entity_occurrences
        |> Enum.map(& &1["literal_element_id"])
        |> Enum.reject(&is_nil/1)
        |> Enum.find(&Map.has_key?(literal_index, &1))

      handle_id =
        if linked_literal,
          do: literal_index[linked_literal].handle_id,
          else: model_handle_id(assessment, entity)

      SQL.query!(
        repo,
        """
        INSERT INTO fount_web_semantic_entity_handles(id,owner_id,project_id,screenplay_id,kind,created_origin,inserted_at,updated_at)
        VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5,$6,now(),now())
        ON CONFLICT(id) DO NOTHING
        """,
        [
          handle_id,
          assessment["owner_id"],
          assessment["project_id"],
          assessment["screenplay_id"],
          entity["kind"],
          assessment["origin"]
        ],
        log: false
      )

      hydrated =
        Enum.map(entity_occurrences, &hydrate_model_occurrence(&1, literal_index, headings))

      payload =
        entity
        |> Map.put("occurrences", hydrated)
        |> Map.put(
          "headings",
          Enum.filter(headings, &(&1["place_entity_id"] == entity["local_id"]))
        )

      SQL.query!(
        repo,
        """
        INSERT INTO fount_web_semantic_assessment_entities(assessment_id,local_id,handle_id,kind,label,payload,evidence,inserted_at,updated_at)
        VALUES($1::text::uuid,$2,$3::text::uuid,$4,$5,$6::jsonb,$7::jsonb,now(),now())
        """,
        [
          assessment["id"],
          entity["local_id"],
          handle_id,
          entity["kind"],
          entity["label"],
          payload,
          entity["evidence"] || []
        ],
        log: false
      )
    end)
  end

  defp index_literal_handle(row, acc) do
    payload = row["payload"] || %{}

    case payload["element_id"] || payload[:element_id] do
      id when is_binary(id) -> Map.put(acc, id, %{handle_id: row["handle_id"], payload: payload})
      _ -> acc
    end
  end

  defp literal_handle_index(repo, assessment) do
    case assessment_for_revision(
           repo,
           assessment["owner_id"],
           assessment["project_id"],
           assessment["revision_id"]
         ) do
      {:ok, manual} ->
        case entities(repo, manual["id"]) do
          rows when is_list(rows) ->
            Enum.reduce(rows, %{}, &index_literal_handle/2)

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp model_handle_id(assessment, entity) do
    first = entity["evidence"] |> List.wrap() |> List.first() || %{}

    Fount.ID.v5(assessment["screenplay_id"], [
      "semantic-model-handle:",
      assessment["project_id"],
      ":",
      assessment["source_sha256"],
      ":",
      entity["kind"],
      ":",
      first["span_id"] || "none",
      ":",
      to_string(first["byte_start"] || 0),
      ":",
      to_string(first["byte_end"] || 0)
    ])
  end

  defp hydrate_model_occurrence(occurrence, literal_index, headings) do
    literal_id = occurrence["literal_element_id"]
    manual = if is_binary(literal_id), do: literal_index[literal_id], else: nil
    base = if manual, do: manual.payload, else: %{}

    heading =
      Enum.find(headings, fn row -> evidence_overlap?(row["evidence"], occurrence["evidence"]) end)

    base
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put("local_id", occurrence["local_id"])
    |> Map.put("element_id", literal_id || map_value(base, "element_id"))
    |> Map.put("occurrence_role", occurrence["role"])
    |> Map.put("certainty", occurrence["certainty"])
    |> Map.put("evidence", occurrence["evidence"] || [])
    |> maybe_put_heading_parts(heading)
  end

  defp maybe_put_heading_parts(payload, nil), do: payload

  defp maybe_put_heading_parts(payload, heading) do
    parts = %{
      "parent_place" => heading["parent_place_label"],
      "subplace" => heading["subplace_label"],
      "geography" => heading["geography_label"],
      "time_of_day" => heading["time_of_day"],
      "date_or_era" => heading["date_or_era"],
      "relative_time" => heading["relative_time"],
      "unknown_modifiers" => heading["modifiers"] || []
    }

    Map.put(payload, "parts", parts)
  end

  defp evidence_overlap?(left, right) do
    left = List.wrap(left)
    right = List.wrap(right)

    Enum.any?(left, fn a ->
      Enum.any?(right, fn b -> a["span_id"] == b["span_id"] and a["quote"] == b["quote"] end)
    end)
  end

  defp sanitize_usage_trace(trace) do
    Enum.map(trace, fn row ->
      Map.take(row, [
        "mode",
        "model",
        "finish_reason",
        "response_id",
        "usage",
        "validation",
        "request_sha256",
        "response_sha256"
      ])
    end)
  end

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) ||
      Enum.find_value(map, fn {candidate, value} -> if to_string(candidate) == key, do: value end)
  end

  defp do_review(repo, owner, project_id, assessment_id, command, expected, command_id, actor) do
    transaction(repo, fn ->
      SQL.query!(
        repo,
        "SELECT pg_advisory_xact_lock(hashtext($1))",
        ["semantic-review:" <> owner <> ":" <> project_id],
        log: false
      )

      case existing_command(repo, owner, project_id, command_id) do
        {:ok, row} ->
          replay_review(repo, row, assessment_id, command, expected, actor)

        {:error, :not_found} ->
          apply_review(
            repo,
            owner,
            project_id,
            assessment_id,
            command,
            {expected, command_id, actor}
          )

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

  defp replay_review(repo, row, assessment_id, command, expected, actor) do
    if command_binding_matches?(row, assessment_id, command, expected, actor),
      do: row,
      else: repo.rollback(:command_id_conflict)
  end

  defp apply_review(
         repo,
         owner,
         project_id,
         assessment_id,
         command,
         {expected, command_id, actor}
       ) do
    with {:ok, assessment} <- assessment(repo, owner, project_id, assessment_id),
         :ok <- ensure_current_revision(repo, assessment),
         :ok <- validate_review_references(repo, assessment, command),
         {:ok, version} <- current_version(repo, owner, project_id, assessment_id) do
      {payload, next_version, outcome} =
        if expected == version do
          {maybe_allocate_split_handle(repo, assessment, command), version + 1, "applied"}
        else
          {command["payload"], version, "conflict"}
        end

      insert_review_event(
        repo,
        assessment,
        command,
        payload,
        expected,
        next_version,
        outcome,
        {command_id, actor}
      )
    else
      {:error, reason} -> repo.rollback(reason)
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
           %{} = entity <-
             Enum.find(projection, &(&1.handle_id == target)) || {:error, :invalid_review_target},
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
           """
           SELECT id FROM fount_web_semantic_review_events
           WHERE id=$1::text::uuid AND owner_id=$2 AND project_id=$3::text::uuid
             AND revision_id=$4::text::uuid AND outcome='applied'
           """,
           [id, assessment["owner_id"], assessment["project_id"], assessment["revision_id"]]
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

  defp validate_projected_action(
         "resolve_occurrence",
         entity,
         %{"local_id" => local_id},
         _projection
       ) do
    if Enum.any?(entity.occurrences, &(&1.local_id == local_id)),
      do: :ok,
      else: {:error, :invalid_occurrence}
  end

  defp validate_projected_action(
         "set_location_parent",
         %{kind: "location"} = entity,
         %{"parent_handle_id" => id},
         projection
       ) do
    case Enum.find(projection, &(&1.handle_id == id)) do
      %{kind: "location"} when id != entity.handle_id ->
        if location_parent_cycle?(projection, entity.handle_id, id),
          do: {:error, :location_parent_cycle},
          else: :ok

      _ ->
        {:error, :invalid_location_parent}
    end
  end

  defp validate_projected_action("set_location_parent", _entity, _payload, _projection),
    do: {:error, :invalid_location_parent}

  defp validate_projected_action("set_time", %{kind: "location"}, _payload, _projection), do: :ok

  defp validate_projected_action("set_time", _entity, _payload, _projection),
    do: {:error, :invalid_time_target}

  defp validate_projected_action(_action, _entity, _payload, _projection), do: :ok

  defp location_parent_cycle?(projection, child_id, candidate_parent_id) do
    by_id = Map.new(projection, &{&1.handle_id, &1})
    parent_chain_reaches?(by_id, candidate_parent_id, child_id, %{})
  end

  defp parent_chain_reaches?(_by_id, nil, _wanted, _seen), do: false
  defp parent_chain_reaches?(_by_id, current, wanted, _seen) when current == wanted, do: true

  defp parent_chain_reaches?(by_id, current, wanted, seen) do
    cond do
      Map.has_key?(seen, current) ->
        true

      is_nil(by_id[current]) ->
        false

      true ->
        parent_chain_reaches?(
          by_id,
          by_id[current].parent_handle_id,
          wanted,
          Map.put(seen, current, true)
        )
    end
  end

  defp review_projection(repo, assessment) do
    current = entities(repo, assessment["id"])

    entities =
      entity_rows_for_revision(
        repo,
        assessment["owner_id"],
        assessment["project_id"],
        assessment["revision_id"]
      )

    history =
      review_history_for_revision(
        repo,
        assessment["owner_id"],
        assessment["project_id"],
        assessment["revision_id"]
      )

    cond do
      not is_list(current) ->
        current

      not is_list(entities) ->
        entities

      not is_list(history) ->
        history

      true ->
        selected =
          current
          |> FountWeb.SemanticContext.include_partial_literals(entities, assessment)
          |> FountWeb.SemanticContext.select_entity_rows(entities, history)

        {:ok, FountWeb.SemanticContext.project_entities(selected, history)}
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
                 JOIN fount_web_semantic_assessments sa ON sa.id=ae.assessment_id
                 WHERE ae.handle_id=h.id AND sa.owner_id=$2 AND sa.project_id=$3::text::uuid
                   AND sa.screenplay_id=$4::text::uuid AND sa.revision_id=$5::text::uuid
               )
               OR EXISTS(
                 SELECT 1 FROM fount_web_semantic_review_events re
                 WHERE re.owner_id=$2 AND re.project_id=$3::text::uuid AND re.screenplay_id=$4::text::uuid
                   AND re.revision_id=$5::text::uuid AND re.outcome='applied'
                   AND re.action='split' AND re.payload->>'new_handle_id'=h.id::text
               )
             )
           """,
           [
             handle_id,
             assessment["owner_id"],
             assessment["project_id"],
             assessment["screenplay_id"],
             assessment["revision_id"]
           ]
         ) do
      [_] -> :ok
      _ -> {:error, :invalid_review_target}
    end
  end

  defp maybe_allocate_split_handle(repo, assessment, %{
         "action" => "split",
         "target_handle_id" => target,
         "payload" => payload
       }) do
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
      [
        new_handle_id,
        assessment["owner_id"],
        assessment["project_id"],
        assessment["screenplay_id"],
        kind
      ],
      log: false
    )

    Map.put(payload, "new_handle_id", new_handle_id)
  end

  defp maybe_allocate_split_handle(_repo, _assessment, %{"payload" => payload}), do: payload

  defp insert_review_event(
         repo,
         assessment,
         command,
         payload,
         expected,
         new_version,
         outcome,
         {command_id, actor}
       ) do
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

    binding = %{
      "assessment_id" => assessment_id,
      "action" => command["action"],
      "target_handle_id" => command["target_handle_id"],
      "expected_version" => expected,
      "actor" => actor
    }

    Map.take(row, Map.keys(binding)) == binding and stored_payload == command["payload"]
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
      [
        "semantic-source-inventory:",
        project["id"],
        ":",
        screenplay.revision.id,
        ":",
        source_sha256
      ]
    )
  end

  defp source_binding(screenplay) do
    {:ok, descriptor} = ImportAssessment.source_descriptor(screenplay)

    %{
      source_artifact_id: descriptor["source_artifact_id"],
      source_sha256: descriptor["source_sha256"]
    }
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
    Enum.map(rows, fn values ->
      columns
      |> Enum.zip(values)
      |> Map.new(fn {column, value} -> {column, normalize_column(column, value)} end)
    end)
  end

  defp normalize_column(column, value)
       when column in @uuid_columns and is_binary(value) and byte_size(value) == 16 do
    {:ok, uuid} = Ecto.UUID.load(value)
    uuid
  end

  defp normalize_column(_column, value), do: value

  defp storage_reason(%Postgrex.Error{postgres: %{code: code}})
       when code in [:undefined_table, :undefined_column],
       do: :semantic_schema_missing

  defp storage_reason(%Postgrex.Error{postgres: %{code: :foreign_key_violation}}),
    do: :source_binding_conflict

  defp storage_reason(%Postgrex.Error{postgres: %{code: :unique_violation}}), do: :conflict
  defp storage_reason(_), do: :storage_error
end
