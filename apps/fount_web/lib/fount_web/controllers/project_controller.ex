defmodule FountWeb.ProjectController do
  use FountWeb, :controller

  @max_upload 1_048_576

  @doc "Controller fallback for project creation; the primary UX is ProjectLive at /new."
  def create(conn, %{"project" => attrs} = params) when is_map(attrs) do
    with {:ok, attrs} <- source(attrs, params["screenplay"]),
         attrs <-
           Map.put_new(
             attrs,
             "kind",
             if(Map.get(attrs, "source", "") == "", do: "blank", else: "import")
           ),
         {:ok, %{project: project}} <-
           FountWeb.Launch.create_project(conn.assigns.current_owner, attrs) do
      destination =
        if attrs["kind"] == "blank",
          do: "/p/#{project["key"]}/write",
          else: "/p/#{project["key"]}"

      redirect(conn, to: destination)
    else
      {:error, :upload_too_large} ->
        reject(conn, "The screenplay upload must be at most 1 MiB.")

      {:error, :upload_unreadable} ->
        reject(conn, "The screenplay upload could not be read.")

      {:error, :unsupported_screenplay_format} ->
        reject(conn, "Choose a Fountain (.fountain) or Final Draft (.fdx) file.")

      {:error, {:invalid_fdx, _reason}} ->
        reject(conn, "This Final Draft file could not be parsed. The project was not created.")

      {:error, :semantic_schema_missing} ->
        reject(conn, "Fount needs the SI01 database migration before projects can be opened. Apply migrations, then retry; no project or source review was created.")

      {:error, _reason} ->
        reject(conn, "The screenplay could not be opened. Your source file was not changed.")
    end
  end

  def create(conn, _params), do: reject(conn, "Choose a screenplay to import or start blank.")

  defp source(attrs, %Plug.Upload{path: path, filename: filename}) do
    extension = filename |> Path.extname() |> String.downcase()

    if extension in [".fountain", ".fdx"] do
      with {:ok, stat} <- File.stat(path),
           true <- stat.size <= @max_upload,
           {:ok, bytes} <- File.read(path) do
        {:ok, Map.merge(attrs, %{"source" => bytes, "filename" => filename, "kind" => "import"})}
      else
        false -> {:error, :upload_too_large}
        _ -> {:error, :upload_unreadable}
      end
    else
      {:error, :unsupported_screenplay_format}
    end
  end

  defp source(attrs, _upload), do: {:ok, attrs}

  defp reject(conn, message) do
    conn |> put_flash(:error, message) |> redirect(to: "/new")
  end
end
