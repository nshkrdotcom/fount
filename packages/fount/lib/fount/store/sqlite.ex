defmodule Fount.Store.SQLite do
  @moduledoc """
  Transactional SQLite document/revision store using Exqlite directly.

  `:exqlite` is an optional dependency. Filesystem-only users do not need a NIF;
  applications selecting this store should add/enable Exqlite in their dependency graph.
  """
  @behaviour Fount.Store

  # Exqlite is optional for downstream applications. Compile the adapter even
  # when its API is absent; available?/0 guards every entry point.
  @compile {:no_warn_undefined, Exqlite.Sqlite3}

  alias Exqlite.Sqlite3
  alias Fount.Store.Snapshot

  defstruct [:path, :conn, busy_timeout: 5_000]

  @type t :: %__MODULE__{path: Path.t() | nil, conn: reference() | nil, busy_timeout: non_neg_integer()}

  @schema """
  PRAGMA journal_mode=WAL;
  PRAGMA foreign_keys=ON;
  CREATE TABLE IF NOT EXISTS documents (
    key TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    revision_id TEXT NOT NULL,
    source BLOB NOT NULL,
    snapshot_json TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS revisions (
    key TEXT NOT NULL,
    revision_id TEXT NOT NULL,
    parent_revision_id TEXT,
    source BLOB NOT NULL,
    snapshot_json TEXT NOT NULL,
    inserted_at TEXT NOT NULL,
    PRIMARY KEY (key, revision_id)
  );
  CREATE INDEX IF NOT EXISTS revisions_key_idx ON revisions(key, inserted_at);
  PRAGMA user_version=1;
  """

  @spec new(Path.t() | keyword(), keyword()) :: %__MODULE__{}
  def new(path_or_opts, opts \\ [])

  def new([conn: conn], []) when is_reference(conn), do: %__MODULE__{conn: conn}

  def new(path, opts) when is_binary(path) do
    %__MODULE__{path: Path.expand(path), busy_timeout: Keyword.get(opts, :busy_timeout, 5_000)}
  end

  @doc "Initializes or migrates a file-backed store before long-lived handle use."
  @spec init(%__MODULE__{}) :: :ok | {:error, term()}
  def init(%__MODULE__{path: path} = store) when is_binary(path) do
    with_connection(store, fn _conn -> :ok end)
  end

  def init(%__MODULE__{conn: conn}) when is_reference(conn) do
    if available?(), do: ensure_schema(conn), else: {:error, :exqlite_not_available}
  end

  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Sqlite3)

  @impl true
  def save(%__MODULE__{} = store, key, doc, opts) do
    snapshot = Snapshot.encode!(doc)
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    expected = Keyword.get(opts, :expected_revision, :any)

    with_connection(store, fn conn ->
      transaction(conn, fn -> save_if_current(conn, key, doc, snapshot, now, expected) end)
    end)
  end

  defp save_if_current(conn, key, doc, snapshot, now, expected) do
    with :ok <- check_revision(conn, key, expected) do
      save_document(conn, key, doc, snapshot, now)
    end
  end

  defp check_revision(_conn, _key, :any), do: :ok

  defp check_revision(conn, key, expected) do
    case one(conn, "SELECT revision_id FROM documents WHERE key = ?", [key]) do
      {:ok, [^expected]} -> :ok
      {:ok, nil} when expected == :new -> :ok
      {:ok, [actual]} -> {:error, {:conflict, actual}}
      {:ok, nil} -> {:error, {:conflict, :missing}}
      error -> error
    end
  end

  defp save_document(conn, key, doc, snapshot, now) do
    with :ok <-
           exec(
             conn,
             """
             INSERT OR IGNORE INTO revisions
               (key, revision_id, parent_revision_id, source, snapshot_json, inserted_at)
             VALUES (?, ?, ?, ?, ?, ?)
             """,
             [key, doc.revision.id, doc.revision.parent_id, {:blob, doc.source.raw}, snapshot, now]
           ) do
      exec(
        conn,
        """
        INSERT INTO documents (key, document_id, revision_id, source, snapshot_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
          document_id=excluded.document_id,
          revision_id=excluded.revision_id,
          source=excluded.source,
          snapshot_json=excluded.snapshot_json,
          updated_at=excluded.updated_at
        """,
        [key, doc.id, doc.revision.id, {:blob, doc.source.raw}, snapshot, now]
      )
    end
  end

  @impl true
  def load(%__MODULE__{} = store, key, _opts) do
    with_connection(store, fn conn ->
      load_document(conn, key)
    end)
  end

  defp load_document(conn, key) do
    case one(conn, "SELECT source, snapshot_json FROM documents WHERE key = ?", [key]) do
      {:ok, [source, snapshot_json]} -> parse_saved_document(source, snapshot_json)
      {:ok, nil} -> {:error, :not_found}
      error -> error
    end
  end

  defp parse_saved_document(source, snapshot_json) do
    with {:ok, snapshot} <- Snapshot.decode(snapshot_json),
         :ok <- Snapshot.validate(snapshot) do
      Fount.parse(source, Snapshot.parse_options(snapshot))
    end
  end

  @impl true
  def list(%__MODULE__{} = store, _opts) do
    with_connection(store, fn conn ->
      with {:ok, rows} <-
             all(
               conn,
               "SELECT key, document_id, revision_id, length(source), updated_at FROM documents ORDER BY key",
               []
             ) do
        {:ok,
         Enum.map(rows, fn [key, document_id, revision_id, bytes, updated_at] ->
           %{
             key: key,
             document_id: document_id,
             revision_id: revision_id,
             bytes: bytes,
             updated_at: updated_at
           }
         end)}
      end
    end)
  end

  @impl true
  def delete(%__MODULE__{} = store, key, _opts) do
    with_connection(store, fn conn ->
      transaction(conn, fn -> delete_document(conn, key) end)
    end)
  end

  defp delete_document(conn, key) do
    with :ok <- exec(conn, "DELETE FROM documents WHERE key = ?", [key]) do
      exec(conn, "DELETE FROM revisions WHERE key = ?", [key])
    end
  end

  @spec history(%__MODULE__{}, String.t()) :: {:ok, [map()]} | {:error, term()}
  def history(%__MODULE__{} = store, key) do
    with_connection(store, fn conn ->
      with {:ok, rows} <-
             all(
               conn,
               "SELECT revision_id, parent_revision_id, inserted_at, length(source) FROM revisions WHERE key = ? ORDER BY inserted_at",
               [key]
             ) do
        {:ok,
         Enum.map(rows, fn [id, parent, at, bytes] ->
           %{revision_id: id, parent_revision_id: parent, inserted_at: at, bytes: bytes}
         end)}
      end
    end)
  end

  @doc "Loads one immutable v1 Fountain revision for explicit canonical import."
  @spec load_revision(%__MODULE__{}, String.t(), String.t()) :: {:ok, Fount.Document.t()} | {:error, term()}
  def load_revision(%__MODULE__{} = store, key, revision_id) do
    with_connection(store, fn conn ->
      case one(conn, "SELECT source,snapshot_json FROM revisions WHERE key=? AND revision_id=?", [key, revision_id]) do
        {:ok, [source, snapshot_json]} -> parse_saved_document(source, snapshot_json)
        {:ok, nil} -> {:error, :not_found}
        error -> error
      end
    end)
  end

  defp with_connection(%__MODULE__{conn: conn}, fun) when is_reference(conn) do
    if available?() do
      with :ok <- require_schema(conn), do: fun.(conn)
    else
      {:error, :exqlite_not_available}
    end
  end

  defp with_connection(%__MODULE__{} = store, fun) do
    if available?() do
      File.mkdir_p!(Path.dirname(store.path))

      with {:ok, conn} <- Sqlite3.open(store.path) do
        try do
          :ok = Sqlite3.set_busy_timeout(conn, store.busy_timeout)
          :ok = Sqlite3.execute(conn, "PRAGMA foreign_keys=ON")
          with :ok <- ensure_schema(conn), do: fun.(conn)
        after
          Sqlite3.close(conn)
        end
      end
    else
      {:error, :exqlite_not_available}
    end
  end

  defp ensure_schema(conn) do
    case one(conn, "PRAGMA user_version", []) do
      {:ok, [0]} -> Sqlite3.execute(conn, @schema)
      {:ok, [1]} -> :ok
      {:ok, [version]} -> {:error, {:unsupported_schema_version, version}}
      error -> error
    end
  end

  defp require_schema(conn) do
    case one(conn, "PRAGMA user_version", []) do
      {:ok, [1]} -> :ok
      {:ok, [0]} -> {:error, :schema_not_initialized}
      {:ok, [version]} -> {:error, {:unsupported_schema_version, version}}
      error -> error
    end
  end

  defp transaction(conn, fun) do
    with :ok <- Sqlite3.execute(conn, "BEGIN IMMEDIATE") do
      case fun.() do
        :ok ->
          Sqlite3.execute(conn, "COMMIT")

        {:error, _} = error ->
          _ = Sqlite3.execute(conn, "ROLLBACK")
          error
      end
    end
  end

  defp exec(conn, sql, params) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(stmt, params) do
          case Sqlite3.step(conn, stmt) do
            :done -> :ok
            {:error, reason} -> {:error, reason}
            other -> {:error, {:unexpected_sqlite_result, other}}
          end
        end
      after
        Sqlite3.release(conn, stmt)
      end
    end
  end

  defp one(conn, sql, params) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(stmt, params) do
          case Sqlite3.step(conn, stmt) do
            {:row, row} -> {:ok, row}
            :done -> {:ok, nil}
            {:error, reason} -> {:error, reason}
          end
        end
      after
        Sqlite3.release(conn, stmt)
      end
    end
  end

  defp all(conn, sql, params) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(stmt, params) do
          fetch_rows(conn, stmt, [])
        end
      after
        Sqlite3.release(conn, stmt)
      end
    end
  end

  defp fetch_rows(conn, stmt, acc) do
    case Sqlite3.step(conn, stmt) do
      {:row, row} -> fetch_rows(conn, stmt, [row | acc])
      :done -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end
end
