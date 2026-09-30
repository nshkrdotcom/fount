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

  @preview_formats ~w(fountain fdx review_json review_markdown source_diff structural_diff resources_checks provenance table_read_json table_read_html)
  @preview_bytes 204_800

  def preview(conn, %{"run_id" => run_id, "delivery_id" => delivery_id}) do
    owner = conn.assigns.current_owner

    with {:ok, delivery} <- FountWeb.Store.delivery(Fount.Repo, owner, run_id, delivery_id),
         true <- delivery["state"] == "ready" or {:error, :not_ready},
         true <- delivery["format"] in @preview_formats or {:error, :unsupported_preview},
         {:ok, path} <- safe_artifact(delivery["output_location"]),
         {:ok, bytes} <- File.read(path),
         true <- checksum(bytes) == delivery["output_checksum"] or {:error, :checksum_mismatch} do
      {preview, truncated?} =
        if byte_size(bytes) > @preview_bytes,
          do: {binary_part(bytes, 0, @preview_bytes), true},
          else: {bytes, false}

      suffix = if truncated?, do: "\n\n[preview truncated at #{@preview_bytes} bytes]\n", else: ""

      conn
      |> put_resp_content_type("text/plain", "utf-8")
      |> put_resp_header("content-disposition", ~s(inline; filename="#{Path.basename(path)}.txt"))
      |> send_resp(:ok, preview <> suffix)
    else
      _ -> send_resp(conn, :not_found, "artifact preview not found")
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
