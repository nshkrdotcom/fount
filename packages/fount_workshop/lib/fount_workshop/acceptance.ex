defmodule FountWorkshop.Acceptance do
  @moduledoc "Small provenance record for a writer-accepted model proposal."

  @spec supported?(struct()) :: :ok | {:error, :acceptance_store_not_supported}
  def supported?(%Fount.Store.Filesystem{}), do: :ok
  def supported?(_), do: {:error, :acceptance_store_not_supported}

  @spec record(struct(), String.t(), FountWorkshop.Preview.t()) :: :ok | {:error, term()}
  def record(%Fount.Store.Filesystem{root: root}, key, preview) do
    path = record_path(root, key, preview.document.revision.id)

    data = %{
      schema_version: 1,
      key: key,
      base_revision: preview.base_revision,
      resulting_revision: preview.document.revision.id,
      accepted_at: DateTime.utc_now(),
      ai_generated: not is_nil(preview.inference),
      inference: preview.inference,
      operations: Enum.map(preview.change_set.operations, &Map.take(&1, [:kind, :target]))
    }

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      case File.write(path, Jason.encode!(data, pretty: true), [:exclusive]) do
        :ok -> :ok
        error -> {:error, {:source_saved_but_acceptance_record_failed, error}}
      end
    end
  end

  def record(_store, _key, _preview), do: {:error, :acceptance_store_not_supported}

  @spec any_for?(struct(), String.t()) :: boolean()
  def any_for?(%Fount.Store.Filesystem{root: root}, key) do
    root
    |> record_dir(key)
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.any?(&ai_record?/1)
  end

  defp ai_record?(path) do
    case File.read(path) do
      {:ok, json} -> ai_json?(Jason.decode(json))
      _ -> true
    end
  end

  defp ai_json?({:ok, %{"ai_generated" => false}}), do: false
  defp ai_json?(_), do: true

  defp record_path(root, key, revision) do
    root |> record_dir(key) |> Path.join(revision <> ".json")
  end

  defp record_dir(root, key) do
    digest = Fount.ID.hash(key)
    Path.join([root, ".fount_workshop", "acceptances", digest])
  end
end
