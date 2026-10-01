defmodule FountWeb.ReadingArtifacts do
  @moduledoc "Owner-bound deterministic project artifacts for UX03 reading, notes memos and exact exports."

  alias FountWeb.{ProductionStore, Store}

  @formats ~w(fountain fdx pdf)

  def build_source(repo, owner, project, screenplay, format, opts \\ [])
      when format in @formats and is_map(project) do
    source_label = Keyword.get(opts, :source_label, "Current draft")

    with :ok <- validate_project_source(repo, owner, project, screenplay),
         {:ok, artifact} <-
           ProductionStore.create_project_artifact(repo, %{
             owner_id: owner,
             project_id: project["id"],
             screenplay_id: screenplay.id,
             revision_id: screenplay.revision.id,
             kind: format,
             source_label: source_label,
             filename: filename(project, format),
             state: "building",
             metadata: source_metadata(screenplay, source_label)
           }) do
      render_source(repo, owner, artifact, screenplay, format, opts)
    end
  end

  def build_source(_repo, _owner, _project, _screenplay, _format, _opts),
    do: {:error, :unsupported_project_export}

  def build_notes_memo(repo, owner, project, screenplay, notes, attrs \\ %{})
      when is_list(notes) and is_map(attrs) do
    with :ok <- validate_project_source(repo, owner, project, screenplay),
         true <- notes != [] or {:error, :notes_required},
         {:ok, artifact} <-
           ProductionStore.create_project_artifact(repo, %{
             owner_id: owner,
             project_id: project["id"],
             screenplay_id: screenplay.id,
             revision_id: screenplay.revision.id,
             kind: "notes_memo",
             source_label: "Current draft",
             filename: "#{safe_name(project["title"] || "screenplay")}-notes-memo.txt",
             state: "building",
             metadata: %{
               "note_count" => length(notes),
               "include_responses" => truthy?(attrs["include_responses"])
             }
           }) do
      body = notes_memo(project, screenplay, notes, attrs)
      persist_bytes(repo, owner, artifact, body, %{
        "note_count" => length(notes),
        "content_type" => "text/plain; charset=utf-8",
        "source_revision_id" => screenplay.revision.id
      })
    end
  end

  def artifact_ref(artifacts, artifact) do
    case Enum.find_index(artifacts, &(&1["id"] == artifact["id"])) do
      nil -> nil
      index -> "artifact-#{index + 1}"
    end
  end

  defp render_source(repo, owner, artifact, screenplay, "fountain", _opts) do
    case Fount.Screenplay.export_fountain(screenplay, mode: :spec) do
      {:ok, result} ->
        persist_bytes(repo, owner, artifact, result.data, %{
          "content_type" => "text/plain; charset=utf-8",
          "losses" => result.losses,
          "source_revision_id" => screenplay.revision.id
        })

      {:error, reason} ->
        fail(repo, owner, artifact, reason)
    end
  end

  defp render_source(repo, owner, artifact, screenplay, "fdx", _opts) do
    case Fount.Screenplay.to_fdx(screenplay) do
      {:ok, exported} ->
        persist_bytes(repo, owner, artifact, exported.data, %{
          "content_type" => "application/xml; charset=utf-8",
          "losses" => exported.losses || [],
          "source_revision_id" => screenplay.revision.id
        })

      {:error, reason} ->
        fail(repo, owner, artifact, reason)
    end
  end

  defp render_source(repo, owner, artifact, screenplay, "pdf", opts) do
    path = absolute_path(artifact)
    pdf_opts = Keyword.get(opts, :pdf_options, [])

    case File.mkdir_p(Path.dirname(path)) do
      :ok ->
        case FountWorkshop.Export.PDF.export(screenplay, path, pdf_opts) do
          {:ok, report} ->
            with {:ok, bytes} <- File.read(path) do
              metadata = %{
                "content_type" => "application/pdf",
                "pages" => report.pages,
                "blank_pages" => report.blank_pages,
                "page_size" => to_string(report.page_size),
                "courier_prime" => report.courier_prime?,
                "renderer" => report.renderer,
                "renderer_settings" => report.settings,
                "renderer_settings_sha256" => report.settings_sha256,
                "source_sha256" => report.source_sha256,
                "source_revision_id" => screenplay.revision.id,
                "page_map" => "unavailable"
              }

              ProductionStore.complete_project_artifact(
                repo,
                owner,
                artifact["id"],
                relative_path(artifact),
                sha256(bytes),
                metadata
              )
            else
              {:error, reason} -> fail(repo, owner, artifact, reason)
            end

          {:error, reason} ->
            fail(repo, owner, artifact, reason)
        end

      {:error, reason} ->
        fail(repo, owner, artifact, reason)
    end
  end

  defp persist_bytes(repo, owner, artifact, data, metadata) when is_binary(data) do
    path = absolute_path(artifact)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- atomic_write(path, data),
         {:ok, completed} <-
           ProductionStore.complete_project_artifact(
             repo,
             owner,
             artifact["id"],
             relative_path(artifact),
             sha256(data),
             Map.merge(artifact["metadata"] || %{}, metadata)
           ) do
      {:ok, completed}
    else
      {:error, reason} -> fail(repo, owner, artifact, reason)
    end
  end

  defp fail(repo, owner, artifact, reason) do
    _ = File.rm(absolute_path(artifact))
    friendly = artifact_error(reason)
    _ = ProductionStore.fail_project_artifact(repo, owner, artifact["id"], friendly)
    {:error, friendly}
  end

  defp validate_project_source(repo, owner, project, screenplay) do
    with {:ok, stored} <- Store.project(repo, owner, project["id"]),
         true <- stored["screenplay_id"] == screenplay.id or {:error, :project_screenplay_mismatch},
         {:ok, persisted} <- Fount.Persistence.load_revision(repo, screenplay.id, screenplay.revision.id),
         true <- persisted.revision.id == screenplay.revision.id or {:error, :revision_unavailable} do
      :ok
    else
      false -> {:error, :revision_unavailable}
      {:error, _} = error -> error
    end
  end

  defp notes_memo(project, screenplay, notes, attrs) do
    from = clean(attrs["from"])
    to = clean(attrs["to"])
    include_responses = truthy?(attrs["include_responses"])
    responses = Map.get(attrs, "responses", %{})

    header =
      [
        "#{project["title"] || "Screenplay"} — Notes memo",
        "Source: Current draft",
        if(from, do: "From: #{from}"),
        if(to, do: "To: #{to}"),
        "Generated: #{Date.utc_today() |> Date.to_iso8601()}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    rows =
      notes
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {note, index} ->
        target = target_label(screenplay, note.target)
        title = note.title |> clean() |> then(&(&1 || "Untitled note"))
        response = if(include_responses, do: responses[note.id], else: nil)

        [
          "#{index}. #{title}",
          "Source passage: #{target}",
          "Source status: #{String.replace(note.target_state, "_", " ")}",
          if(note.category, do: "Category: #{note.category}"),
          note.text || "",
          response_line(response)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")
      end)

    header <> "\n\n" <> rows <> "\n"
  end

  defp response_line(%{} = row) do
    status = row["response"] |> to_string() |> String.replace("_", " ")
    comment = clean(row["comment"])
    "Reviewer response: #{status} on Current draft" <>
      if(comment, do: " — #{comment}", else: "")
  end

  defp response_line(_), do: nil

  defp target_label(_screenplay, %{"kind" => "screenplay"}), do: "Whole screenplay"

  defp target_label(screenplay, %{"kind" => kind, "id" => id} = target) do
    case Fount.Target.resolve(screenplay, target) do
      {:ok, %{text: text}} when is_binary(text) ->
        "#{kind} · #{text |> String.replace(~r/\s+/u, " ") |> String.slice(0, 140)}"

      {:ok, %{heading_id: heading_id}} ->
        case Fount.Query.node(screenplay, heading_id) do
          %{text: text} -> "scene · #{text}"
          _ -> "scene · exact source recorded"
        end

      {:ok, %{display_name: name}} ->
        "character · #{name}"

      _ ->
        "#{kind} · source no longer resolves on this draft"
    end
  end

  defp target_label(_screenplay, _target), do: "Source target unavailable"

  defp source_metadata(screenplay, source_label) do
    %{
      "source_label" => source_label,
      "source_revision_id" => screenplay.revision.id,
      "source_render_hash" => screenplay.revision.render_hash
    }
  end

  defp filename(project, format) do
    base = safe_name(project["title"] || "screenplay")
    extension = if(format == "fountain", do: "fountain", else: format)
    "#{base}.#{extension}"
  end

  defp safe_name(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "screenplay"
      name -> String.slice(name, 0, 80)
    end
  end

  defp absolute_path(artifact) do
    root = Application.fetch_env!(:fount_web, :artifact_root) |> Path.expand()
    Path.join(root, relative_path(artifact))
  end

  defp relative_path(artifact) do
    Path.join(["projects", artifact["project_id"], artifact["id"], artifact["filename"]])
  end

  defp atomic_write(path, data) do
    temporary = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(temporary, data, [:binary]),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, reason} = error ->
        File.rm(temporary)
        if reason == :eexist do
          with :ok <- File.rm(path), do: File.rename(temporary, path)
        else
          error
        end
    end
  end

  defp artifact_error(:renderer_not_installed),
    do: "PDF renderer is not installed. Responsive reading remains available; retry after the configured renderer is available."

  defp artifact_error({:tool_not_installed, tool}),
    do: "PDF inspection tool #{tool} is unavailable. No PDF artifact was recorded."

  defp artifact_error({:render_failed, _status, _output}),
    do: "PDF rendering failed. The selected source is unchanged and can be retried."

  defp artifact_error(:project_screenplay_mismatch),
    do: "The project source changed before export. Reopen the current draft and try again."

  defp artifact_error(:revision_unavailable),
    do: "That exact saved revision is no longer available for export."

  defp artifact_error(reason), do: "Artifact build failed: #{inspect(reason)}"

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp truthy?(value), do: value in [true, "true", "1", "on", 1]

  defp clean(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp clean(_), do: nil
end
