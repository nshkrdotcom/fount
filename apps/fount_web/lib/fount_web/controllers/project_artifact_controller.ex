defmodule FountWeb.ProjectArtifactController do
  use FountWeb, :controller

  alias FountWeb.{ProductionStore, ProductionTools, ProjectContext, Store}

  @preview_bytes 204_800

  def show(conn, %{"key" => key, "artifact_ref" => artifact_ref}) do
    with {:ok, artifact} <- resolve(conn, key, artifact_ref),
         true <- artifact["state"] == "ready" or {:error, :not_ready},
         {:ok, bytes} <- verified_bytes(artifact) do
      send_download(conn, {:binary, bytes},
        filename: artifact["filename"],
        disposition: :attachment
      )
    else
      _ -> recover_artifact(conn, key)
    end
  end

  def preview(conn, %{"key" => key, "artifact_ref" => artifact_ref}) do
    with {:ok, artifact} <- resolve(conn, key, artifact_ref),
         true <- artifact["state"] == "ready" or {:error, :not_ready},
         true <- artifact["kind"] in ~w(fountain fdx notes_memo) or {:error, :unsupported_preview},
         {:ok, bytes} <- verified_bytes(artifact) do
      {preview, truncated?} =
        if byte_size(bytes) > @preview_bytes,
          do: {binary_part(bytes, 0, @preview_bytes), true},
          else: {bytes, false}

      suffix = if truncated?, do: "\n\n[preview truncated at #{@preview_bytes} bytes]\n", else: ""

      conn
      |> put_resp_content_type("text/plain", "utf-8")
      |> put_resp_header(
        "content-disposition",
        ~s(inline; filename="#{artifact["filename"]}.txt")
      )
      |> send_resp(:ok, preview <> suffix)
    else
      _ -> recover_artifact(conn, key)
    end
  end

  def view_pdf(conn, %{"key" => key, "artifact_ref" => artifact_ref}) do
    with {:ok, artifact} <- resolve(conn, key, artifact_ref),
         true <-
           (artifact["state"] == "ready" and artifact["kind"] == "pdf") or {:error, :not_pdf},
         {:ok, bytes} <- verified_bytes(artifact) do
      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(inline; filename="#{artifact["filename"]}"))
      |> put_resp_header("cache-control", "private, no-store")
      |> send_resp(:ok, bytes)
    else
      _ -> recover_artifact(conn, key)
    end
  end

  def notes(conn, %{"key" => key}) do
    owner = conn.assigns.current_owner

    with {:ok, project} <- Store.project_by_key(Fount.Repo, owner, key),
         {:ok, screenplay} <- Fount.Persistence.load(Fount.Repo, key) do
      json(conn, %{
        "kind" => "fount.authored_notes_export",
        "project" => project["title"],
        "screenplay_id" => screenplay.id,
        "revision_id" => screenplay.revision.id,
        "source" => "Current draft",
        "notes" => Enum.map(ProductionTools.notes(screenplay), &plain/1)
      })
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "notes_not_found"})
    end
  end

  def feedback(conn, %{"key" => key}) do
    owner = conn.assigns.current_owner

    with {:ok, project} <- Store.project_by_key(Fount.Repo, owner, key),
         {:ok, report} <- ProductionTools.usefulness_report(Fount.Repo, owner, project["id"]) do
      rows = ProductionStore.list_usefulness(Fount.Repo, owner, project["id"], limit: 100)

      json(conn, %{
        "kind" => "fount.writer_usefulness_export",
        "project" => project["title"],
        "report" => report,
        "records" => if(is_list(rows), do: Enum.map(rows, &plain/1), else: [])
      })
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "feedback_not_found"})
    end
  end

  def source_interpretation(conn, %{"key" => key}) do
    owner = conn.assigns.current_owner

    with {:ok, context} <- ProjectContext.load(owner, key),
         %{assessment_id: assessment_id, source_sha256: source_sha256} = semantic <-
           context.semantic do
      json(conn, %{
        "kind" => "fount.semantic_source_review_v2",
        "project" => context.project["title"],
        "source" => %{
          "screenplay_id" => context.current.id,
          "revision_id" => semantic.revision_id,
          "assessment_id" => assessment_id,
          "source_sha256" => source_sha256,
          "source_artifact_id" => semantic.assessment["source_artifact_id"],
          "render_sha256" => semantic.assessment["render_sha256"],
          "source_name" => context.project["source_name"],
          "representation" => semantic.assessment["origin"] || "manual"
        },
        "assessment" => %{
          "id" => assessment_id,
          "schema_version" => semantic.assessment["schema_version"],
          "request_fingerprint" => semantic.assessment["request_fingerprint"],
          "origin" => semantic.assessment["origin"],
          "status" => semantic.assessment["status"],
          "parser_version" => semantic.assessment["parser_version"],
          "model" => semantic.assessment["model"],
          "run_id" => semantic.assessment["run_id"],
          "coverage" => semantic.assessment["coverage"],
          "prompt_version" => semantic.assessment["prompt_version"],
          "reasoning_effort" => semantic.assessment["reasoning_effort"],
          "provider_family" => semantic.assessment["provider_family"],
          "provider_returned_model" => semantic.assessment["provider_returned_model"],
          "usage" => semantic.assessment["usage"],
          "limits" => semantic.assessment["limits"],
          "provenance" => semantic.assessment["provenance"]
        },
        "assessment_state" => to_string(semantic.assessment_state),
        "import_audit" => semantic.inventory["import_audit"],
        "latest_assessment" => plain(semantic.latest_assessment),
        "assessment_history" => Enum.map(semantic.assessment_history, &plain/1),
        "historical_model_assessments" =>
          Enum.map(Map.get(semantic, :model_assessment_history, []), &plain/1),
        "review_version" => semantic.version,
        "entities" => Enum.map(semantic.entities, &plain/1),
        "characters" => Enum.map(semantic.characters, &plain/1),
        "cue_groups" => Enum.map(semantic.cue_groups, &plain/1),
        "assessment_result" => semantic.assessment_result,
        "cue_decisions" => semantic.assessment_result["cue_decisions"] || [],
        "relations" => semantic.assessment_result["relations"] || [],
        "resolution_issues" => semantic.resolution_issues,
        "review_history" => Enum.map(semantic.review_history, &plain/1),
        "canonical_cast" => semantic.canonical_cast,
        "provenance" => %{
          "manual_review_available_without_provider" => true,
          "model_entities_require_human_review" => true,
          "human_review_precedence" => true,
          "screenplay_accepted_by_review" => false
        }
      })
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "source_interpretation_not_found"})
    end
  end

  def table_read(conn, %{"key" => key, "read_ref" => read_ref}) do
    owner = conn.assigns.current_owner

    with {:ok, project} <- Store.project_by_key(Fount.Repo, owner, key),
         {:ok, row} <-
           ProductionStore.project_table_read_by_ref(Fount.Repo, owner, project["id"], read_ref) do
      json(conn, %{
        "kind" => "fount.saved_table_read",
        "source" => %{
          "screenplay_id" => row["screenplay_id"],
          "revision_id" => row["revision_id"],
          "project" => project["title"]
        },
        "reading_state" => %{
          "bookmark_index" => row["bookmark_index"],
          "elapsed_ms" => row["elapsed_ms"],
          "scroll_mode" => row["scroll_mode"],
          "version" => row["version"]
        },
        "packet" => row["packet"]
      })
    else
      _ -> conn |> put_status(:not_found) |> json(%{"error" => "table_read_not_found"})
    end
  end

  defp recover_artifact(conn, key) do
    case Store.project_by_key(Fount.Repo, conn.assigns.current_owner, key) do
      {:ok, _project} ->
        conn
        |> put_flash(
          :error,
          "This artifact is unavailable or failed verification. Build it again from the exact selected source in Exports."
        )
        |> redirect(to: "/p/#{key}/exports")

      _ ->
        send_resp(conn, :not_found, "artifact not found")
    end
  end

  defp resolve(conn, key, artifact_ref) do
    owner = conn.assigns.current_owner

    with {:ok, project} <- Store.project_by_key(Fount.Repo, owner, key),
         do:
           ProductionStore.project_artifact_by_ref(Fount.Repo, owner, project["id"], artifact_ref)
  end

  defp verified_bytes(artifact) do
    with {:ok, path} <- safe_artifact(artifact["output_location"]),
         {:ok, bytes} <- File.read(path),
         true <- sha256(bytes) == artifact["output_checksum"] or {:error, :checksum_mismatch} do
      {:ok, bytes}
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

  defp plain(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp plain(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp plain(value) when is_struct(value), do: value |> Map.from_struct() |> plain()

  defp plain(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {to_string(key), plain(item)} end)

  defp plain(value) when is_list(value), do: Enum.map(value, &plain/1)
  defp plain(value) when is_atom(value), do: Atom.to_string(value)
  defp plain(value), do: value

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
