defmodule FountWeb.ProductionStore do
  @moduledoc "Owner-scoped host persistence for Phase 08 human records and candidate bindings."

  alias Ecto.Adapters.SQL

  @uuid_columns ~w(id project_id run_id screenplay_id revision_id base_revision_id candidate_id)

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

  def create_table_read(repo, attrs) do
    id = value(attrs, :id) || Fount.ID.v4()

    params = [
      id,
      fetch!(attrs, :owner_id),
      fetch!(attrs, :project_id),
      fetch!(attrs, :run_id),
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
    one_query(repo, "SELECT * FROM fount_web_table_reads WHERE owner_id=$1 AND id=$2::text::uuid", [owner, id])
  end

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

    if mode not in ~w(manual auto paused) do
      {:error, :invalid_scroll_mode}
    else
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
