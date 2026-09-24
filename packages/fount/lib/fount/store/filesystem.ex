defmodule Fount.Store.Filesystem do
  @moduledoc "Git-friendly Fountain files plus `.fount.json` sidecars."
  @behaviour Fount.Store

  alias Fount.Store.Snapshot

  @enforce_keys [:root]
  defstruct [:root]

  @spec new(Path.t()) :: %__MODULE__{}
  def new(root), do: %__MODULE__{root: Path.expand(root)}

  @impl true
  def save(%__MODULE__{} = store, key, doc, _opts) do
    with {:ok, base} <- base_path(store, key),
         :ok <- File.mkdir_p(Path.dirname(base)) do
      with :ok <- atomic_write(base <> ".fountain", doc.source.raw) do
        atomic_write(base <> ".fount.json", Snapshot.encode!(doc))
      end
    end
  end

  @impl true
  def load(%__MODULE__{} = store, key, _opts) do
    with {:ok, base} <- base_path(store, key),
         {:ok, source} <- File.read(base <> ".fountain") do
      opts = sidecar_options(base <> ".fount.json")
      Fount.parse(source, Keyword.put(opts, :path, base <> ".fountain"))
    end
  end

  defp sidecar_options(path) do
    with {:ok, json} <- File.read(path),
         {:ok, snapshot} <- Snapshot.decode(json) do
      Snapshot.parse_options(snapshot)
    else
      _ -> []
    end
  end

  @impl true
  def list(%__MODULE__{} = store, _opts) do
    pattern = Path.join(store.root, "**/*.fountain")

    documents =
      Path.wildcard(pattern)
      |> Enum.sort()
      |> Enum.map(fn path ->
        relative = Path.relative_to(path, store.root)
        key = String.trim_trailing(relative, ".fountain")
        stat = File.stat!(path)
        %{key: key, path: path, bytes: stat.size, modified_at: stat.mtime}
      end)

    {:ok, documents}
  rescue
    error -> {:error, error}
  end

  @impl true
  def delete(%__MODULE__{} = store, key, _opts) do
    with {:ok, base} <- base_path(store, key) do
      Enum.reduce_while([base <> ".fountain", base <> ".fount.json"], :ok, &remove_file/2)
    end
  end

  defp remove_file(path, :ok) do
    case File.rm(path) do
      :ok -> {:cont, :ok}
      {:error, :enoent} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp base_path(%__MODULE__{root: root}, key) when is_binary(key) do
    cond do
      Path.type(key) == :absolute -> {:error, :absolute_key_not_allowed}
      Enum.any?(Path.split(key), &(&1 in ["..", "."])) -> {:error, :unsafe_key}
      true -> {:ok, Path.join(root, String.trim_trailing(key, ".fountain"))}
    end
  end

  defp atomic_write(path, bytes) do
    temp = path <> ".tmp-" <> Integer.to_string(System.unique_integer([:positive]))

    with :ok <- File.write(temp, bytes, [:binary, :sync]),
         :ok <- replace(temp, path) do
      :ok
    else
      error ->
        File.rm(temp)
        error
    end
  end

  defp replace(temp, target) do
    case File.rename(temp, target) do
      :ok ->
        :ok

      {:error, :eexist} ->
        with :ok <- File.rm(target), do: File.rename(temp, target)

      {:error, :eacces} ->
        with :ok <- File.rm(target), do: File.rename(temp, target)

      error ->
        error
    end
  end
end
