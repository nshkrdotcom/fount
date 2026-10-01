defmodule FountWeb.ProductionController do
  use FountWeb, :controller

  alias FountWeb.{ProductionStore, ProductionTools, Store}

  def notes(conn, %{"key" => key, "task_key" => task_key} = params) do
    with {:ok, access} <-
           Store.run_access_by_task_key(Fount.Repo, conn.assigns.current_owner, key, task_key),
         {:ok, workspace} <-
           ProductionTools.workspace(
             Fount.Repo,
             conn.assigns.current_owner,
             access["run_id"],
             params["view"]
           ) do
      json(conn, %{
        "kind" => "fount.authored_notes_export",
        "screenplay_id" => workspace.screenplay.id,
        "revision_id" => workspace.screenplay.revision.id,
        "source" => FountWeb.ScreenplayViews.token(workspace.selection),
        "notes" => Enum.map(ProductionTools.notes(workspace.screenplay), &plain/1)
      })
    else
      {:error, reason} -> unavailable(conn, reason)
    end
  end

  def table_read(conn, %{"key" => key, "task_key" => task_key, "read_ref" => read_ref}) do
    with {:ok, access} <-
           Store.run_access_by_task_key(Fount.Repo, conn.assigns.current_owner, key, task_key),
         {:ok, row} <-
           ProductionStore.table_read_by_ref(
             Fount.Repo,
             conn.assigns.current_owner,
             access["project_id"],
             access["run_id"],
             read_ref
           ) do
      json(conn, %{
        "kind" => "fount.saved_table_read",
        "identity" =>
          Map.take(
            row,
            ~w(id owner_id project_id run_id screenplay_id revision_id packet_id bookmark_index elapsed_ms scroll_mode version inserted_at updated_at)
          ),
        "packet" => row["packet"]
      })
    else
      {:error, reason} -> unavailable(conn, reason)
    end
  end

  def usefulness(conn, %{"key" => key, "task_key" => task_key}) do
    with {:ok, access} <-
           Store.run_access_by_task_key(Fount.Repo, conn.assigns.current_owner, key, task_key),
         {:ok, report} <-
           ProductionTools.usefulness_report(
             Fount.Repo,
             conn.assigns.current_owner,
             access["project_id"]
           ) do
      rows =
        ProductionStore.list_usefulness(
          Fount.Repo,
          conn.assigns.current_owner,
          access["project_id"],
          limit: 100
        )

      json(conn, %{
        "kind" => "fount.writer_usefulness_export",
        "project" => access["title"],
        "task" => access["display_label"],
        "report" => report,
        "records" => if(is_list(rows), do: Enum.map(rows, &plain/1), else: [])
      })
    else
      {:error, reason} -> unavailable(conn, reason)
    end
  end

  defp unavailable(conn, reason) do
    conn
    |> put_status(:not_found)
    |> json(%{"error" => "production_resource_unavailable", "reason" => inspect(reason)})
  end

  defp plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp plain(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp plain(value) when is_struct(value), do: value |> Map.from_struct() |> plain()

  defp plain(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), plain(item)} end)

  defp plain(value) when is_list(value), do: Enum.map(value, &plain/1)
  defp plain(value) when is_atom(value), do: Atom.to_string(value)
  defp plain(value), do: value
end
