defmodule Fount.Store.SQLite do
  @moduledoc """
  Transactional SQLite document/revision store using Exqlite directly.

  `:exqlite` is an optional dependency. Filesystem-only users do not need a NIF;
  applications selecting this store should add/enable Exqlite in their dependency graph.
  """
  @behaviour Fount.Store

  alias Exqlite.Sqlite3
  alias Fount.Store.Snapshot

  @enforce_keys [:path]
  defstruct [:path, busy_timeout: 5_000]

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

  @spec new(Path.t(), keyword()) :: %__MODULE__{}
  def new(path, opts \\ []) do
    %__MODULE__{path: Path.expand(path), busy_timeout: Keyword.get(opts, :busy_timeout, 5_000)}
  end

  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Sqlite3)

  @impl true
  def save(%__MODULE__{} = store, key, doc, _opts) do
    snapshot = Snapshot.encode!(doc)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    with_connection(store, fn conn ->
      transaction(conn, fn ->
        with :ok <-
               exec(
                 conn,
                 """
                 INSERT OR IGNORE INTO revisions
                   (key, revision_id, parent_revision_id, source, snapshot_json, inserted_at)
                 VALUES (?, ?, ?, ?, ?, ?)
                 """,
                 [key, doc.revision.id, doc.revision.parent_id, {:blob, doc.source.raw}, snapshot, now]
               ),
             :ok <-
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
               ) do
          :ok
        end
      end)
    end)
  end

  @impl true
  def load(%__MODULE__{} = store, key, _opts) do
    with_connection(store, fn conn ->
      case one(conn, "SELECT source, snapshot_json FROM documents WHERE key = ?", [key]) do
        {:ok, [source, snapshot_json]} ->
          with {:ok, snapshot} <- Snapshot.decode(snapshot_json) do
            Fount.parse(source, Snapshot.parse_options(snapshot))
          end

        {:ok, nil} ->
          {:error, :not_found}

        error ->
          error
      end
    end)
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
      transaction(conn, fn ->
        with :ok <- exec(conn, "DELETE FROM documents WHERE key = ?", [key]),
             :ok <- exec(conn, "DELETE FROM revisions WHERE key = ?", [key]) do
          :ok
        end
      end)
    end)
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

  defp with_connection(%__MODULE__{} = store, fun) do
    if available?() do
      File.mkdir_p!(Path.dirname(store.path))

      with {:ok, conn} <- Sqlite3.open(store.path) do
        try do
          :ok = Sqlite3.set_busy_timeout(conn, store.busy_timeout)
          :ok = Sqlite3.execute(conn, @schema)
          fun.(conn)
        after
          Sqlite3.close(conn)
        end
      end
    else
      {:error, :exqlite_not_available}
    end
  end

  defp transaction(conn, fun) do
    with :ok <- Sqlite3.execute(conn, "BEGIN IMMEDIATE") do
      case fun.() do
        :ok ->
          case Sqlite3.execute(conn, "COMMIT") do
            :ok -> :ok
            {:error, _} = error -> error
          end

        {:error, _} = error ->
          _ = Sqlite3.execute(conn, "ROLLBACK")
          error

        other ->
          _ = Sqlite3.execute(conn, "ROLLBACK")
          {:error, {:invalid_transaction_result, other}}
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
