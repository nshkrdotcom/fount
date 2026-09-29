defmodule FountWeb.Store do
  @moduledoc "Owner-scoped durable host metadata. Run and screenplay state remain owned by Fount/FountRun."
  alias Ecto.Adapters.SQL
  @uuid_columns ~w(id screenplay_id run_id project_id)

  def create_project(repo, attrs) do
    id = attrs[:id] || attrs["id"] || Fount.ID.v4()
    owner = fetch!(attrs, :owner_id)
    screenplay_id = fetch!(attrs, :screenplay_id)
    key = fetch!(attrs, :key)
    title = fetch!(attrs, :title)

    case SQL.query(
           repo,
           "INSERT INTO fount_web_projects(id,owner_id,screenplay_id,key,title,inserted_at,updated_at) VALUES($1::text::uuid,$2,$3::text::uuid,$4,$5,now(),now()) RETURNING *",
           [id, owner, screenplay_id, key, title],
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
  defp fetch!(attrs, key), do: Map.get(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  defp storage_reason(%Postgrex.Error{postgres: %{code: :unique_violation}}), do: :conflict
  defp storage_reason(_), do: :storage_error
end
