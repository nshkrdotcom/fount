defmodule FountWeb.ProjectController do
  use FountWeb, :controller

  @max_upload 1_048_576

  def create(conn, %{"project" => attrs} = params) when is_map(attrs) do
    with {:ok, attrs} <- source(attrs, params["screenplay"]),
         {:ok, %{run: run}} <- FountWeb.Launch.create(conn.assigns.current_owner, attrs) do
      redirect(conn, to: ~p"/runs/#{run["id"]}/setup")
    else
      {:error, :upload_too_large} ->
        reject(conn, "The screenplay upload must be at most 1 MiB.")

      {:error, :upload_unreadable} ->
        reject(conn, "The screenplay upload could not be read.")

      {:error, _} ->
        reject(
          conn,
          "Could not create Run. Check the project title, unique key and screenplay source."
        )
    end
  end

  def create(conn, _params), do: reject(conn, "Project fields are required to create a Run.")

  defp source(attrs, %Plug.Upload{path: path, filename: filename}) do
    with {:ok, stat} <- File.stat(path),
         true <- stat.size <= @max_upload,
         {:ok, bytes} <- File.read(path) do
      {:ok, Map.merge(attrs, %{"source" => bytes, "filename" => filename})}
    else
      false -> {:error, :upload_too_large}
      _ -> {:error, :upload_unreadable}
    end
  end

  defp source(attrs, _upload), do: {:ok, attrs}

  defp reject(conn, message) do
    conn |> put_flash(:error, message) |> redirect(to: ~p"/projects/new")
  end
end
