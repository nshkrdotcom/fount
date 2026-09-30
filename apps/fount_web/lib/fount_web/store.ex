defmodule FountWeb.Store do
  @moduledoc "Owner-scoped durable host metadata. Run and screenplay state remain owned by Fount/FountRun."
  alias Ecto.Adapters.SQL
  @uuid_columns ~w(id screenplay_id run_id project_id base_revision_id)

  def create_project(repo, attrs) do
    id = attrs[:id] || attrs["id"] || Fount.ID.v4()
    owner = fetch!(attrs, :owner_id)
    screenplay_id = fetch!(attrs, :screenplay_id)
    key = fetch!(attrs, :key)
    title = fetch!(attrs, :title)

    synopsis = value(attrs, :synopsis)
    thumbnail_ref = value(attrs, :thumbnail_ref)
    import_format = value(attrs, :import_format)
    import_fidelity = value(attrs, :import_fidelity)

    case SQL.query(
           repo,
           """
           INSERT INTO fount_web_projects(
             id,owner_id,screenplay_id,key,title,synopsis,thumbnail_ref,import_format,import_fidelity,inserted_at,updated_at
           ) VALUES($1::text::uuid,$2,$3::text::uuid,$4,$5,$6,$7,$8,$9::jsonb,now(),now()) RETURNING *
           """,
           [id, owner, screenplay_id, key, title, synopsis, thumbnail_ref, import_format, import_fidelity],
           log: false
         ) do
      {:ok, result} -> {:ok, one(result)}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def list_projects(repo, owner) do
    query(
      repo,
      "SELECT * FROM fount_web_projects WHERE owner_id=$1 ORDER BY inserted_at DESC,id",
      [owner]
    )
  end

  def list_projects(repo, owner, opts) do
    limit = opts |> Keyword.get(:limit, 24) |> min(100) |> max(1)

    query(
      repo,
      "SELECT * FROM fount_web_projects WHERE owner_id=$1 ORDER BY inserted_at DESC,id LIMIT $2",
      [owner, limit]
    )
  end

  def project(repo, owner, id) do
    case query(repo, "SELECT * FROM fount_web_projects WHERE owner_id=$1 AND id=$2::text::uuid", [
           owner,
           id
         ]) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def project_by_key(repo, owner, key) do
    case query(repo, "SELECT * FROM fount_web_projects WHERE owner_id=$1 AND key=$2", [owner, key]) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def register_run(repo, attrs) do
    values = [
      fetch!(attrs, :run_id),
      fetch!(attrs, :project_id),
      fetch!(attrs, :owner_id),
      fetch!(attrs, :preset),
      fetch!(attrs, :journey)
    ]

    case SQL.query(
           repo,
           "INSERT INTO fount_web_runs(run_id,project_id,owner_id,preset,journey,inserted_at,updated_at) VALUES($1::text::uuid,$2::text::uuid,$3,$4,$5,now(),now()) RETURNING *",
           values,
           log: false
         ) do
      {:ok, result} ->
        {:ok, one(result)}

      {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} ->
        run_access(repo, fetch!(attrs, :owner_id), fetch!(attrs, :run_id))

      {:error, reason} ->
        {:error, storage_reason(reason)}
    end
  end

  def run_access(repo, owner, run_id) do
    rows =
      query(
        repo,
        """
        SELECT wr.*,p.screenplay_id::text,p.key,p.title
        FROM fount_web_runs wr
        JOIN fount_web_projects p ON p.id=wr.project_id
        WHERE wr.owner_id=$1 AND wr.run_id=$2::text::uuid AND p.owner_id=$1
        """,
        [owner, run_id]
      )

    case rows do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @run_statuses ~w(queued running paused waiting_for_decision waiting_for_approval partial completed_candidate completed_accepted stopped failed)

  def list_run_accesses(repo, owner, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 50) |> min(50) |> max(1)
    status = Keyword.get(opts, :status)

    cond do
      status in [nil, ""] ->
        query(
          repo,
          """
          SELECT wr.*,p.screenplay_id::text,p.key,p.title,r.status,r.stage,r.inserted_at AS run_inserted_at
          FROM fount_web_runs wr
          JOIN fount_web_projects p ON p.id=wr.project_id
          JOIN fount_runs r ON r.id=wr.run_id
          WHERE wr.owner_id=$1 AND p.owner_id=$1
          ORDER BY r.inserted_at DESC,wr.run_id
          LIMIT $2
          """,
          [owner, limit]
        )

      status in @run_statuses ->
        query(
          repo,
          """
          SELECT wr.*,p.screenplay_id::text,p.key,p.title,r.status,r.stage,r.inserted_at AS run_inserted_at
          FROM fount_web_runs wr
          JOIN fount_web_projects p ON p.id=wr.project_id
          JOIN fount_runs r ON r.id=wr.run_id
          WHERE wr.owner_id=$1 AND p.owner_id=$1 AND r.status=$2
          ORDER BY r.inserted_at DESC,wr.run_id
          LIMIT $3
          """,
          [owner, status, limit]
        )

      true ->
        {:error, :invalid_run_status}
    end
  end

  def mark_launched(repo, owner, run_id) do
    case SQL.query(
           repo,
           "UPDATE fount_web_runs SET launched_at=COALESCE(launched_at,now()),updated_at=now() WHERE owner_id=$1 AND run_id=$2::text::uuid RETURNING *",
           [owner, run_id],
           log: false
         ) do
      {:ok, %{num_rows: 1} = result} -> {:ok, one(result)}
      {:ok, _} -> {:error, :not_found}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def launched_runs(repo) do
    query(
      repo,
      """
      SELECT wr.*,p.screenplay_id::text,p.key,p.title
      FROM fount_web_runs wr
      JOIN fount_web_projects p ON p.id=wr.project_id
      JOIN fount_runs r ON r.id=wr.run_id
      WHERE wr.launched_at IS NOT NULL AND r.status NOT IN ('completed_candidate','completed_accepted','stopped','failed')
      ORDER BY wr.launched_at,wr.run_id
      """,
      []
    )
  end

  def save_policy_preset(repo, attrs) do
    owner = fetch!(attrs, :owner_id)
    name = fetch!(attrs, :name)
    policy = fetch!(attrs, :policy)
    fingerprint = fetch!(attrs, :policy_fingerprint)
    id = Map.get(attrs, :id) || Map.get(attrs, "id") || Fount.ID.v4()

    case repo.transaction(fn ->
           SQL.query!(repo, "SELECT pg_advisory_xact_lock(hashtext($1))", [owner <> ":" <> name],
             log: false
           )

           SQL.query!(
             repo,
             """
             INSERT INTO fount_web_policy_presets(id,owner_id,name,version,policy,policy_fingerprint,inserted_at,updated_at)
             SELECT $1::text::uuid,$2,$3,COALESCE(MAX(version),0)+1,$4::jsonb,$5,now(),now()
             FROM fount_web_policy_presets WHERE owner_id=$2 AND name=$3
             RETURNING *
             """,
             [id, owner, name, policy, fingerprint],
             log: false
           )
           |> one()
         end) do
      {:ok, row} -> {:ok, row}
      {:error, _} -> {:error, :storage_error}
    end
  end

  def list_policy_presets(repo, owner) do
    query(
      repo,
      "SELECT * FROM fount_web_policy_presets WHERE owner_id=$1 ORDER BY name,version DESC,id",
      [owner]
    )
  end

  def put_workflow_selection(repo, attrs) do
    values = [
      fetch!(attrs, :run_id),
      fetch!(attrs, :owner_id),
      fetch!(attrs, :screenplay_id),
      fetch!(attrs, :base_revision_id),
      fetch!(attrs, :selection),
      fetch!(attrs, :selection_fingerprint)
    ]

    case SQL.query(
           repo,
           """
           INSERT INTO fount_web_workflow_selections(run_id,owner_id,screenplay_id,base_revision_id,selection,selection_fingerprint,inserted_at,updated_at)
           VALUES($1::text::uuid,$2,$3::text::uuid,$4::text::uuid,$5::jsonb,$6,now(),now())
           ON CONFLICT(run_id) DO UPDATE SET
             base_revision_id=EXCLUDED.base_revision_id,selection=EXCLUDED.selection,
             selection_fingerprint=EXCLUDED.selection_fingerprint,updated_at=now()
           WHERE fount_web_workflow_selections.owner_id=EXCLUDED.owner_id
             AND fount_web_workflow_selections.screenplay_id=EXCLUDED.screenplay_id
           RETURNING *
           """,
           values,
           log: false
         ) do
      {:ok, %{num_rows: 1} = result} -> {:ok, one(result)}
      {:ok, _} -> {:error, :unauthorized}
      {:error, reason} -> {:error, storage_reason(reason)}
    end
  end

  def workflow_selection(repo, owner, run_id) do
    case query(
           repo,
           "SELECT * FROM fount_web_workflow_selections WHERE owner_id=$1 AND run_id=$2::text::uuid",
           [owner, run_id]
         ) do
      [row] -> {:ok, row}
      [] -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def delete_workflow_selection(repo, owner, run_id) do
    case SQL.query(
           repo,
           "DELETE FROM fount_web_workflow_selections WHERE owner_id=$1 AND run_id=$2::text::uuid",
           [owner, run_id],
           log: false
         ) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :storage_error}
    end
  end

  def delivery(repo, owner, run_id, delivery_id) do
    rows =
      query(
        repo,
        """
        SELECT d.*,p.screenplay_id::text
        FROM fount_run_deliveries d
        JOIN fount_web_runs wr ON wr.run_id=d.run_id
        JOIN fount_web_projects p ON p.id=wr.project_id
        WHERE wr.owner_id=$1 AND d.run_id=$2::text::uuid AND d.id=$3::text::uuid
        """,
        [owner, run_id, delivery_id]
      )

    case rows do
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

  defp decode_column({column, <<_::binary-size(16)>> = value}) when column in @uuid_columns do
    {:ok, uuid} = Ecto.UUID.load(value)
    {column, uuid}
  end

  defp decode_column(pair), do: pair
  defp one(result), do: result |> rows() |> List.first()
  defp fetch!(attrs, key), do: value(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp storage_reason(%Postgrex.Error{postgres: %{code: :unique_violation}}), do: :conflict
  defp storage_reason(_), do: :storage_error
end
