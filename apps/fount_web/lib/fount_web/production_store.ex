defmodule FountWeb.ProductionStore do
  @moduledoc "Owner-scoped host persistence for production records and candidate bindings."

  alias Ecto.Adapters.SQL

  @uuid_columns ~w(id project_id run_id screenplay_id revision_id base_revision_id candidate_id source_revision_id reviewed_revision_id proposal_candidate_id result_revision_id)

  def register_candidate(repo, attrs) do
    id = value(attrs, :id) || Fount.ID.v4()

    params = [
      id,
      fetch!(attrs, :owner_id),
      fetch!(attrs, :project_id),
      fetch!(attrs, :candidate_id),
      fetch!(attrs, :screenplay_id),
      fetch!(attrs, :base_revision_id),
      fetch!(attrs, :kind),
      value(attrs, :resource_id),
      value(attrs, :metadata) || %{}
    ]

    case SQL.query(
           repo,
           """
           INSERT INTO fount_web_tool_candidates(
             id,owner_id,project_id,candidate_id,screenplay_id,base_revision_id,kind,resource_id,metadata,inserted_at,updated_at
           ) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6::text::uuid,$7,$8,$9::jsonb,now(),now())
           ON CONFLICT(owner_id,candidate_id) DO UPDATE SET metadata=EXCLUDED.metadata,updated_at=now()
           RETURNING *
           """,
           params,
           log: false
         ) do
      {:ok, result} -> {:ok, one(result)}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def candidate(repo, owner, candidate_id) do
    one_query(
      repo,
      "SELECT * FROM fount_web_tool_candidates WHERE owner_id=$1 AND candidate_id=$2::text::uuid",
      [owner, candidate_id]
    )
  end

  def list_candidates(repo, owner, project_id, opts \\ []) do
    limit = bounded_limit(opts, 30)

    query(
      repo,
      """
      SELECT tc.*,wc.decision,wc.result_revision_id::text
      FROM fount_web_tool_candidates tc
      JOIN writing_candidates wc ON wc.id=tc.candidate_id
      WHERE tc.owner_id=$1 AND tc.project_id=$2::text::uuid
      ORDER BY tc.inserted_at DESC,tc.id
      LIMIT $3
      """,
      [owner, project_id, limit]
    )
  end

  def link_note_work(repo, attrs) do
    id = value(attrs, :id) || Fount.ID.v4()

    params = [
      id,
      fetch!(attrs, :owner_id),
      fetch!(attrs, :project_id),
      fetch!(attrs, :screenplay_id),
      fetch!(attrs, :note_id),
      fetch!(attrs, :source_revision_id),
      fetch!(attrs, :source_fingerprint),
      fetch!(attrs, :run_id)
    ]

    case SQL.query(
           repo,
           """
           INSERT INTO fount_web_note_work_links(
             id,owner_id,project_id,screenplay_id,note_id,source_revision_id,source_fingerprint,run_id,inserted_at,updated_at
           ) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5,$6::text::uuid,$7,$8::text::uuid,now(),now())
           ON CONFLICT(owner_id,note_id,run_id) DO UPDATE SET updated_at=now()
           RETURNING *
           """,
           params,
           log: false
         ) do
      {:ok, result} -> {:ok, one(result)}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def list_note_work_links(repo, owner, project_id, note_id \\ nil) do
    {statement, params} =
      if is_binary(note_id) do
        {"""
         SELECT l.*,wr.display_key,wr.display_label,r.status
         FROM fount_web_note_work_links l
         JOIN fount_web_runs wr ON wr.owner_id=l.owner_id AND wr.run_id=l.run_id
         JOIN fount_runs r ON r.id=l.run_id
         WHERE l.owner_id=$1 AND l.project_id=$2::text::uuid AND l.note_id=$3
         ORDER BY l.inserted_at DESC,l.id
         LIMIT 100
         """, [owner, project_id, note_id]}
      else
        {"""
         SELECT l.*,wr.display_key,wr.display_label,r.status
         FROM fount_web_note_work_links l
         JOIN fount_web_runs wr ON wr.owner_id=l.owner_id AND wr.run_id=l.run_id
         JOIN fount_runs r ON r.id=l.run_id
         WHERE l.owner_id=$1 AND l.project_id=$2::text::uuid
         ORDER BY l.inserted_at DESC,l.id
         LIMIT 100
         """, [owner, project_id]}
      end

    query(repo, statement, params)
  end

  def attach_note_work_result(repo, owner, run_id, candidate_id, result_revision_id) do
    case SQL.query(
           repo,
           """
           UPDATE fount_web_note_work_links
           SET proposal_candidate_id=$3::text::uuid,result_revision_id=$4::text::uuid,updated_at=now()
           WHERE owner_id=$1 AND run_id=$2::text::uuid
           RETURNING *
           """,
           [owner, run_id, candidate_id, result_revision_id],
           log: false
         ) do
      {:ok, result} -> {:ok, rows(result)}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def create_table_read(repo, attrs) do
    id = value(attrs, :id) || Fount.ID.v4()

    params = [
      id,
      fetch!(attrs, :owner_id),
      fetch!(attrs, :project_id),
      value(attrs, :run_id),
      fetch!(attrs, :screenplay_id),
      fetch!(attrs, :revision_id),
      fetch!(attrs, :packet_id),
      fetch!(attrs, :packet)
    ]

    case SQL.query(
           repo,
           """
           INSERT INTO fount_web_table_reads(
             id,owner_id,project_id,run_id,screenplay_id,revision_id,packet_id,packet,bookmark_index,elapsed_ms,scroll_mode,version,inserted_at,updated_at
           ) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6::text::uuid,$7,$8::jsonb,0,0,'manual',1,now(),now())
           RETURNING *
           """,
           params,
           log: false
         ) do
      {:ok, result} -> {:ok, one(result)}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def table_read(repo, owner, id) do
    one_query(
      repo,
      "SELECT * FROM fount_web_table_reads WHERE owner_id=$1 AND id=$2::text::uuid",
      [owner, id]
    )
  end

  @doc "Resolves a saved table read by its owner/project/task display ordinal."
  def table_read_by_ref(repo, owner, project_id, run_id, "read-" <> ordinal_text) do
    with {ordinal, ""} when ordinal > 0 <- Integer.parse(ordinal_text),
         rows when is_list(rows) <- list_table_reads(repo, owner, project_id, limit: 100),
         row when is_map(row) <-
           rows |> Enum.filter(&(&1["run_id"] == run_id)) |> Enum.at(ordinal - 1) do
      {:ok, row}
    else
      _ -> {:error, :not_found}
    end
  end

  def table_read_by_ref(_repo, _owner, _project_id, _run_id, _ref), do: {:error, :not_found}

  def list_table_reads(repo, owner, project_id, opts \\ []) do
    limit = bounded_limit(opts, 30)

    query(
      repo,
      "SELECT * FROM fount_web_table_reads WHERE owner_id=$1 AND project_id=$2::text::uuid ORDER BY updated_at DESC,id LIMIT $3",
      [owner, project_id, limit]
    )
  end

  def update_table_read(repo, owner, id, expected_version, attrs) do
    bookmark = nonnegative(value(attrs, :bookmark_index), 0)
    elapsed = nonnegative(value(attrs, :elapsed_ms), 0)
    mode = value(attrs, :scroll_mode) || "manual"
    packet = value(attrs, :packet)

    if mode in ~w(manual auto paused) do
      statement =
        if is_map(packet) do
          """
          UPDATE fount_web_table_reads
          SET bookmark_index=$4,elapsed_ms=$5,scroll_mode=$6,packet=$7::jsonb,version=version+1,updated_at=now()
          WHERE owner_id=$1 AND id=$2::text::uuid AND version=$3
          RETURNING *
          """
        else
          """
          UPDATE fount_web_table_reads
          SET bookmark_index=$4,elapsed_ms=$5,scroll_mode=$6,version=version+1,updated_at=now()
          WHERE owner_id=$1 AND id=$2::text::uuid AND version=$3
          RETURNING *
          """
        end

      params =
        if is_map(packet),
          do: [owner, id, expected_version, bookmark, elapsed, mode, packet],
          else: [owner, id, expected_version, bookmark, elapsed, mode]

      case SQL.query(repo, statement, params, log: false) do
        {:ok, %{num_rows: 1} = result} -> {:ok, one(result)}
        {:ok, _} -> stale_or_missing_read(repo, owner, id)
        {:error, reason} -> {:error, storage_reason(reason)}
      end
    else
      {:error, :invalid_scroll_mode}
    end
  end

  @doc "Resolves a saved table read by its project-level stable display ordinal, including manual run-free reads."
  def project_table_read_by_ref(repo, owner, project_id, "read-" <> ordinal_text) do
    with {ordinal, ""} when ordinal > 0 <- Integer.parse(ordinal_text),
         rows when is_list(rows) <- list_table_reads(repo, owner, project_id, limit: 100),
         row when is_map(row) <- Enum.at(rows, ordinal - 1) do
      {:ok, row}
    else
      _ -> {:error, :not_found}
    end
  end

  def project_table_read_by_ref(_repo, _owner, _project_id, _ref), do: {:error, :not_found}

  def save_note_review(repo, attrs, expected_version \\ 0) do
    id = value(attrs, :id) || Fount.ID.v4()
    owner = fetch!(attrs, :owner_id)
    project_id = fetch!(attrs, :project_id)
    note_id = fetch!(attrs, :note_id)
    reviewed_revision_id = fetch!(attrs, :reviewed_revision_id)
    response = fetch!(attrs, :response)

    params = [
      id,
      owner,
      project_id,
      fetch!(attrs, :screenplay_id),
      note_id,
      fetch!(attrs, :source_revision_id),
      reviewed_revision_id,
      response,
      value(attrs, :comment),
      fetch!(attrs, :actor_label),
      expected_version
    ]

    statement =
      if expected_version == 0 do
        """
        INSERT INTO fount_web_note_review_responses(
          id,owner_id,project_id,screenplay_id,note_id,source_revision_id,reviewed_revision_id,response,comment,actor_label,version,inserted_at,updated_at
        ) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5,$6::text::uuid,$7::text::uuid,$8,$9,$10,1,now(),now())
        ON CONFLICT(owner_id,project_id,note_id,reviewed_revision_id) DO NOTHING
        RETURNING *
        """
      else
        """
        UPDATE fount_web_note_review_responses
        SET response=$8,comment=$9,actor_label=$10,version=version+1,updated_at=now()
        WHERE owner_id=$2 AND project_id=$3::text::uuid AND note_id=$5
          AND reviewed_revision_id=$7::text::uuid AND version=$11
        RETURNING *
        """
      end

    case SQL.query(repo, statement, params, log: false) do
      {:ok, %{num_rows: 1} = result} -> {:ok, one(result)}
      {:ok, _} -> stale_or_missing_note_review(repo, owner, project_id, note_id, reviewed_revision_id)
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def clear_note_review(repo, owner, project_id, note_id, reviewed_revision_id, expected_version)
      when is_integer(expected_version) and expected_version >= 0 do
    if expected_version == 0 do
      case note_review(repo, owner, project_id, note_id, reviewed_revision_id) do
        {:error, :not_found} -> :ok
        {:ok, row} -> {:error, {:stale_note_review, row}}
        {:error, _} = error -> error
      end
    else
      case SQL.query(
             repo,
             """
             DELETE FROM fount_web_note_review_responses
             WHERE owner_id=$1 AND project_id=$2::text::uuid AND note_id=$3
               AND reviewed_revision_id=$4::text::uuid AND version=$5
             RETURNING id::text
             """,
             [owner, project_id, note_id, reviewed_revision_id, expected_version],
             log: false
           ) do
        {:ok, %{num_rows: 1}} -> :ok
        {:ok, _} -> stale_or_missing_note_review(repo, owner, project_id, note_id, reviewed_revision_id)
        {:error, reason} -> {:error, storage_reason(reason)}
      end
    end
  end

  def note_reviews(repo, owner, project_id, note_id \\ nil) do
    {statement, params} =
      if is_binary(note_id) do
        {"""
         SELECT * FROM fount_web_note_review_responses
         WHERE owner_id=$1 AND project_id=$2::text::uuid AND note_id=$3
         ORDER BY updated_at DESC,id
         LIMIT 100
         """, [owner, project_id, note_id]}
      else
        {"""
         SELECT * FROM fount_web_note_review_responses
         WHERE owner_id=$1 AND project_id=$2::text::uuid
         ORDER BY updated_at DESC,id
         LIMIT 200
         """, [owner, project_id]}
      end

    query(repo, statement, params)
  end

  def note_review(repo, owner, project_id, note_id, reviewed_revision_id) do
    one_query(
      repo,
      """
      SELECT * FROM fount_web_note_review_responses
      WHERE owner_id=$1 AND project_id=$2::text::uuid AND note_id=$3 AND reviewed_revision_id=$4::text::uuid
      """,
      [owner, project_id, note_id, reviewed_revision_id]
    )
  end

  def create_project_artifact(repo, attrs) do
    id = value(attrs, :id) || Fount.ID.v4()
    params = [
      id,
      fetch!(attrs, :owner_id),
      fetch!(attrs, :project_id),
      fetch!(attrs, :screenplay_id),
      fetch!(attrs, :revision_id),
      fetch!(attrs, :kind),
      fetch!(attrs, :source_label),
      fetch!(attrs, :filename),
      value(attrs, :state) || "building",
      value(attrs, :metadata) || %{}
    ]

    case SQL.query(
           repo,
           """
           INSERT INTO fount_web_project_artifacts(
             id,owner_id,project_id,screenplay_id,revision_id,kind,source_label,filename,state,metadata,inserted_at,updated_at
           ) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6,$7,$8,$9,$10::jsonb,now(),now())
           RETURNING *
           """,
           params,
           log: false
         ) do
      {:ok, result} -> {:ok, one(result)}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def complete_project_artifact(repo, owner, id, output_location, output_checksum, metadata) do
    case SQL.query(
           repo,
           """
           UPDATE fount_web_project_artifacts
           SET state='ready',output_location=$3,output_checksum=$4,error=NULL,metadata=$5::jsonb,updated_at=now()
           WHERE owner_id=$1 AND id=$2::text::uuid
           RETURNING *
           """,
           [owner, id, output_location, output_checksum, metadata || %{}],
           log: false
         ) do
      {:ok, %{num_rows: 1} = result} -> {:ok, one(result)}
      {:ok, _} -> {:error, :not_found}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def fail_project_artifact(repo, owner, id, error, metadata \\ %{}) do
    case SQL.query(
           repo,
           """
           UPDATE fount_web_project_artifacts
           SET state='failed',output_location=NULL,output_checksum=NULL,error=$3,metadata=$4::jsonb,updated_at=now()
           WHERE owner_id=$1 AND id=$2::text::uuid
           RETURNING *
           """,
           [owner, id, to_string(error), metadata || %{}],
           log: false
         ) do
      {:ok, %{num_rows: 1} = result} -> {:ok, one(result)}
      {:ok, _} -> {:error, :not_found}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def project_artifacts(repo, owner, project_id, opts \\ []) do
    limit = bounded_limit(opts, 100)

    query(
      repo,
      """
      SELECT * FROM fount_web_project_artifacts
      WHERE owner_id=$1 AND project_id=$2::text::uuid
      ORDER BY inserted_at DESC,id
      LIMIT $3
      """,
      [owner, project_id, limit]
    )
  end

  def project_artifact_by_ref(repo, owner, project_id, "artifact-" <> ordinal_text) do
    with {ordinal, ""} when ordinal > 0 <- Integer.parse(ordinal_text),
         rows when is_list(rows) <- project_artifacts(repo, owner, project_id, limit: 100),
         row when is_map(row) <- Enum.at(rows, ordinal - 1) do
      {:ok, row}
    else
      _ -> {:error, :not_found}
    end
  end

  def project_artifact_by_ref(_repo, _owner, _project_id, _ref), do: {:error, :not_found}

  def latest_ready_project_artifact(repo, owner, project_id, revision_id, kind) do
    case query(
           repo,
           """
           SELECT * FROM fount_web_project_artifacts
           WHERE owner_id=$1 AND project_id=$2::text::uuid AND revision_id=$3::text::uuid
             AND kind=$4 AND state='ready'
           ORDER BY inserted_at DESC,id
           LIMIT 1
           """,
           [owner, project_id, revision_id, kind]
         ) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def create_usefulness(repo, attrs) do
    id = value(attrs, :id) || Fount.ID.v4()

    params = [
      id,
      fetch!(attrs, :owner_id),
      fetch!(attrs, :project_id),
      fetch!(attrs, :run_id),
      fetch!(attrs, :screenplay_id),
      fetch!(attrs, :revision_id),
      fetch!(attrs, :task_id),
      fetch!(attrs, :condition),
      fetch!(attrs, :record)
    ]

    case SQL.query(
           repo,
           """
           INSERT INTO fount_web_usefulness_records(
             id,owner_id,project_id,run_id,screenplay_id,revision_id,task_id,condition,record,inserted_at,updated_at
           ) VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::text::uuid,$6::text::uuid,$7,$8,$9::jsonb,now(),now())
           RETURNING *
           """,
           params,
           log: false
         ) do
      {:ok, result} -> {:ok, one(result)}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def usefulness(repo, owner, id) do
    one_query(
      repo,
      "SELECT * FROM fount_web_usefulness_records WHERE owner_id=$1 AND id=$2::text::uuid",
      [owner, id]
    )
  end

  def update_usefulness(repo, owner, id, project_id, run_id, attrs) when is_map(attrs) do
    case SQL.query(
           repo,
           """
           UPDATE fount_web_usefulness_records
           SET task_id=$6,condition=$7,record=$8::jsonb,screenplay_id=$4::text::uuid,revision_id=$5::text::uuid,updated_at=now()
           WHERE owner_id=$1 AND id=$2::text::uuid AND project_id=$3::text::uuid AND run_id=$9::text::uuid
           RETURNING *
           """,
           [
             owner,
             id,
             project_id,
             fetch!(attrs, :screenplay_id),
             fetch!(attrs, :revision_id),
             fetch!(attrs, :task_id),
             fetch!(attrs, :condition),
             fetch!(attrs, :record),
             run_id
           ],
           log: false
         ) do
      {:ok, %{num_rows: 1} = result} -> {:ok, one(result)}
      {:ok, _} -> {:error, :not_found}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def list_usefulness(repo, owner, project_id, opts \\ []) do
    limit = bounded_limit(opts, 100)

    query(
      repo,
      "SELECT * FROM fount_web_usefulness_records WHERE owner_id=$1 AND project_id=$2::text::uuid ORDER BY inserted_at DESC,id LIMIT $3",
      [owner, project_id, limit]
    )
  end

  def delete_usefulness(repo, owner, id) do
    case SQL.query(
           repo,
           "DELETE FROM fount_web_usefulness_records WHERE owner_id=$1 AND id=$2::text::uuid RETURNING id::text",
           [owner, id],
           log: false
         ) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, _} -> {:error, :not_found}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def recent_activity(repo, owner, project_id, opts \\ []) do
    limit = bounded_limit(opts, 20)

    query(
      repo,
      """
      SELECT * FROM (
        SELECT 'run' AS kind,wr.run_id::text AS resource_id,r.status AS detail,r.updated_at AS occurred_at
        FROM fount_web_runs wr JOIN fount_runs r ON r.id=wr.run_id
        WHERE wr.owner_id=$1 AND wr.project_id=$2::text::uuid
        UNION ALL
        SELECT 'candidate',candidate_id::text,kind,updated_at FROM fount_web_tool_candidates
        WHERE owner_id=$1 AND project_id=$2::text::uuid
        UNION ALL
        SELECT 'table_read',id::text,packet_id,updated_at FROM fount_web_table_reads
        WHERE owner_id=$1 AND project_id=$2::text::uuid
        UNION ALL
        SELECT 'usefulness',id::text,condition,updated_at FROM fount_web_usefulness_records
        WHERE owner_id=$1 AND project_id=$2::text::uuid
      ) activity
      ORDER BY occurred_at DESC,resource_id
      LIMIT $3
      """,
      [owner, project_id, limit]
    )
  end

  defp stale_or_missing_note_review(repo, owner, project_id, note_id, reviewed_revision_id) do
    case note_review(repo, owner, project_id, note_id, reviewed_revision_id) do
      {:ok, row} -> {:error, {:stale_note_review, row}}
      {:error, :not_found} -> {:error, :conflict}
      {:error, _} = error -> error
    end
  end

  defp stale_or_missing_read(repo, owner, id) do
    case table_read(repo, owner, id) do
      {:ok, row} -> {:error, {:stale_table_read, row}}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp one_query(repo, statement, params) do
    case query(repo, statement, params) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp query(repo, statement, params) do
    case SQL.query(repo, statement, params, log: false) do
      {:ok, result} -> rows(result)
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  defp rows(%{columns: columns, rows: rows}), do: Enum.map(rows, &row_map(columns, &1))
  defp row_map(columns, row), do: Map.new(Enum.zip(columns, row), &decode_column/1)

  defp decode_column({column, <<_::binary-size(16)>> = raw}) when column in @uuid_columns do
    case Ecto.UUID.load(raw) do
      {:ok, value} -> {column, value}
      :error -> {column, raw}
    end
  end

  defp decode_column(pair), do: pair
  defp one(result), do: result |> rows() |> List.first()

  defp bounded_limit(opts, default) do
    case Keyword.get(opts, :limit, default) do
      value when is_integer(value) -> value |> min(default) |> max(1)
      _ -> default
    end
  end

  defp nonnegative(value, _default) when is_integer(value) and value >= 0, do: value
  defp nonnegative(_, default), do: default

  defp fetch!(attrs, key), do: value(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp storage_reason(%Postgrex.Error{postgres: %{code: :unique_violation}}), do: :conflict
  defp storage_reason(%Postgrex.Error{postgres: %{code: :check_violation}}), do: :invalid_record
  defp storage_reason(_), do: :storage_error
end
