defmodule FountWeb.ArtifactController do
  use FountWeb, :controller

  def show(conn, %{"run_id" => run_id, "delivery_id" => delivery_id}) do
    owner = conn.assigns.current_owner

    with {:ok, delivery} <- FountWeb.Store.delivery(Fount.Repo, owner, run_id, delivery_id),
         true <- delivery["state"] == "ready" or {:error, :not_ready},
         {:ok, path} <- safe_artifact(delivery["output_location"]),
         {:ok, bytes} <- File.read(path),
         true <- checksum(bytes) == delivery["output_checksum"] or {:error, :checksum_mismatch} do
      send_download(conn, {:binary, bytes},
        filename: Path.basename(path),
        disposition: :attachment
      )
    else
      _ -> send_resp(conn, :not_found, "artifact not found")
    end
  end

  defp safe_artifact(location) when is_binary(location) do
    root = Application.fetch_env!(:fount_web, :artifact_root) |> Path.expand()
    path = Path.expand(location, root)

    if path == root or String.starts_with?(path, root <> "/"),
      do: {:ok, path},
      else: {:error, :outside_root}
  end

  defp safe_artifact(_), do: {:error, :invalid_location}
  defp checksum(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
