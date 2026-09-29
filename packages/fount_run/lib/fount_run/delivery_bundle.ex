defmodule FountRun.DeliveryBundle do
  @moduledoc """
  Durable Phase-05 artifact delivery.

  Every format gets its own immutable delivery record. Ready artifacts are
  reused only when their bytes still match the recorded checksum; a failed or
  missing artifact is retried with a new delivery identity. The manifest is
  published last and records candidate versus accepted identity explicitly.
  """

  alias Ecto.Adapters.SQL
  alias Fount.Persistence, as: CorePersistence
  alias Fount.Screenplay.Model
  alias FountRun.{ActorContext, Control, Persistence}

  @standard_formats ~w(fountain fdx review_json review_markdown source_diff structural_diff resources_checks provenance)

  def deliver(repo, run_id, destination, %ActorContext{} = context, opts \\ [])
      when is_binary(destination) and is_list(opts) do
    with {:ok, run} <- FountRun.get_run(repo, run_id, context),
         :ok <- deliverable_run(run),
         {:ok, candidate_id} <- selected_candidate(run),
         {:ok, candidate} <- CorePersistence.candidate(repo, candidate_id),
         {:ok, packet} <- FountWorkshop.Review.packet(repo, candidate_id),
         {:ok, identity} <- delivery_identity(repo, run, candidate, context),
         :ok <- exact_identity(run, candidate, packet, identity),
         {:ok, root, directory, relative_directory} <- safe_destination(destination, opts),
         :ok <- File.mkdir_p(directory),
         {:ok, progress} <- FountRun.ExecutionStore.progress(repo, run_id, context) do
      requested = requested_formats(opts)
      common = common_data(run, candidate, packet, progress, identity)

      results =
        Enum.map(requested, fn format ->
          deliver_format(
            repo,
            run,
            candidate,
            packet,
            progress,
            identity,
            root,
            directory,
            relative_directory,
            format,
            context,
            opts
          )
        end)

      manifest = build_manifest(common, relative_directory, results)
      manifest_path = Path.join(directory, "manifest.json")

      with :ok <- atomic_write(manifest_path, Jason.encode!(manifest, pretty: true)),
           {:ok, manifest_bytes} <- File.read(manifest_path) do
        manifest_sha = sha256(manifest_bytes)
        failures = Enum.filter(results, &(&1["state"] != "ready"))
        status = if failures == [], do: identity.completion_status, else: "partial"

        completion =
          cond do
            run["status"] == "stopped" -> {:ok, run}
            Keyword.get(opts, :defer_run_completion, false) -> {:ok, Map.put(run, "delivery_completion_status", status)}
            true -> Control.mark_completion(repo, run_id, candidate_id, status, context)
          end

        case completion do
          {:ok, updated_run} ->
            payload = %{
              "run" => updated_run,
              "manifest" => Map.put(manifest, "manifest_sha256", manifest_sha),
              "manifest_location" => relative_path(root, manifest_path),
              "failures" => failures
            }

            if failures == [], do: {:ok, payload}, else: {:partial, :delivery_partial, payload}

          {:error, _} = error ->
            error
        end
      end
    end
  rescue
    error in File.Error -> {:error, {:artifact_io_error, error.reason}}
    _error in Postgrex.Error -> {:error, :storage_error}
  end

  def deliver(_repo, _run_id, _destination, _context, _opts), do: {:error, :invalid_delivery_request}

  defp deliverable_run(run) do
    cond do
      run["stop_requested_at"] && is_nil(run["selected_candidate_id"]) -> {:error, :no_exportable_candidate}
      run["status"] in ~w(completed_candidate completed_accepted partial stopped) -> :ok
      true -> {:error, {:run_not_deliverable, run["status"]}}
    end
  end

  defp selected_candidate(%{"selected_candidate_id" => id}) when is_binary(id), do: {:ok, id}
  defp selected_candidate(_), do: {:error, :no_exportable_candidate}

  defp delivery_identity(repo, run, candidate, context) do
    accepted =
      one(
        repo,
        ~S"""
        SELECT aa.id AS approval_attempt_id,aa.approval_id::text,aa.acceptance_id::text,
               a.result_revision_id::text AS accepted_revision_id,a.approval_hash
        FROM fount_run_approval_attempts aa
        JOIN acceptances a ON a.id=aa.acceptance_id
        WHERE aa.run_id=$1::text::uuid AND aa.candidate_id=$2::text::uuid AND aa.outcome='accepted'
        ORDER BY aa.finished_at DESC NULLS LAST,aa.inserted_at DESC,aa.id DESC
        LIMIT 1
        """,
        [run["id"], candidate["id"]]
      )

    if accepted do
      {:ok,
       %{
         kind: "accepted",
         candidate_id: candidate["id"],
         accepted_revision_id: accepted["accepted_revision_id"],
         acceptance_id: accepted["acceptance_id"],
         approval_id: accepted["approval_id"],
         approval_hash: accepted["approval_hash"],
         completion_status: "completed_accepted"
       }}
    else
      # Candidate-only completion and stopped runs may still export saved work.
      with :ok <- ActorContext.authorize(context, :read_run, run["screenplay_id"]) do
        {:ok,
         %{
           kind: "candidate",
           candidate_id: candidate["id"],
           accepted_revision_id: nil,
           acceptance_id: nil,
           approval_id: nil,
           approval_hash: nil,
           completion_status: "completed_candidate"
         }}
      end
    end
  end

  defp exact_identity(run, candidate, packet, identity) do
    cond do
      candidate["screenplay_id"] != run["screenplay_id"] -> {:error, :delivery_screenplay_mismatch}
      packet["candidate_id"] != candidate["id"] -> {:error, :delivery_candidate_mismatch}
      packet["result_revision_id"] != candidate["result_revision_id"] -> {:error, :delivery_revision_mismatch}
      identity.kind == "accepted" and identity.accepted_revision_id != candidate["result_revision_id"] ->
        {:error, :accepted_revision_mismatch}
      true -> :ok
    end
  end

  defp safe_destination(destination, opts) do
    root = Keyword.get(opts, :artifact_root) || Application.get_env(:fount_run, :artifact_root)

    cond do
      not (is_binary(root) and String.trim(root) != "") ->
        {:error, :artifact_root_not_configured}

      String.contains?(destination, <<0>>) ->
        {:error, :invalid_artifact_destination}

      true ->
        root = Path.expand(root)
        directory = if Path.type(destination) == :absolute, do: Path.expand(destination), else: Path.expand(destination, root)
        prefix = root <> "/"

        if directory == root or String.starts_with?(directory <> "/", prefix) do
          {:ok, root, directory, relative_path(root, directory)}
        else
          {:error, :artifact_destination_outside_root}
        end
    end
  end

  defp requested_formats(opts) do
    @standard_formats ++
      if(Keyword.get(opts, :pdf, false), do: ["pdf"], else: []) ++
      if(Keyword.get(opts, :table_read, false), do: ["table_read_json", "table_read_html"], else: [])
  end

  defp deliver_format(repo, run, candidate, packet, progress, identity, root, directory, relative_directory, format, context, opts) do
    path = Path.join(directory, file_name(format))
    relative = relative_path(root, path)
    base_options = format_options(format, relative_directory, opts)

    case reusable_delivery(repo, run["id"], identity, format, base_options, root) do
      {:ready, delivery} ->
        result_row(format, delivery, true)

      {:retry, retry_index, prior_id} ->
        options = base_options |> Map.put("retry_index", retry_index) |> Map.put("retry_of", prior_id)
        perform_delivery(repo, run, candidate, packet, progress, identity, format, path, relative, options, context, opts)

      :new ->
        options = Map.put(base_options, "retry_index", 0)
        perform_delivery(repo, run, candidate, packet, progress, identity, format, path, relative, options, context, opts)
    end
  end

  defp perform_delivery(repo, run, candidate, packet, progress, identity, format, path, relative, options, context, opts) do
    attrs =
      %{
        "candidate_id" => if(identity.kind == "candidate", do: identity.candidate_id, else: nil),
        "accepted_revision_id" => identity.accepted_revision_id,
        "format" => format,
        "options" => options
      }

    with {:ok, delivery} <- Persistence.create_delivery(repo, run["id"], attrs, context) do
      case render(format, candidate, packet, progress, run, identity, path, opts) do
        {:ok, metadata} ->
          with {:ok, bytes} <- File.read(path),
               checksum = sha256(bytes),
               {:ok, saved} <-
                 Persistence.record_delivery_result(
                   repo,
                   delivery["id"],
                   %{
                     "state" => "ready",
                     "output_checksum" => checksum,
                     "output_location" => relative,
                     "error" => nil
                   },
                   context
                 ) do
            result_row(format, saved, false) |> Map.put("metadata", Model.plain(metadata))
          else
            {:error, reason} -> fail_delivery(repo, delivery, format, path, reason, context)
          end

        {:error, reason} ->
          fail_delivery(repo, delivery, format, path, reason, context)
      end
    else
      {:error, reason} ->
        %{"format" => format, "state" => "failed", "error" => error_code(reason)}
    end
  end

  defp fail_delivery(repo, delivery, format, path, reason, context) do
    _ = File.rm(path)
    error = error_code(reason)

    case Persistence.record_delivery_result(
           repo,
           delivery["id"],
           %{"state" => "failed", "output_checksum" => nil, "output_location" => nil, "error" => error},
           context
         ) do
      {:ok, saved} -> result_row(format, saved, false)
      {:error, _} -> %{"format" => format, "state" => "failed", "error" => error}
    end
  end

  defp render("fountain", candidate, _packet, _progress, _run, _identity, path, _opts) do
    atomic_write(path, Fount.Screenplay.to_fountain(candidate["screenplay"], mode: :spec))
    |> ok_metadata(%{"serializer" => "Fount.Screenplay.to_fountain/2"})
  end

  defp render("fdx", candidate, _packet, _progress, _run, _identity, path, _opts) do
    with {:ok, exported} <- Fount.Screenplay.to_fdx(candidate["screenplay"]),
         :ok <- atomic_write(path, exported.data) do
      {:ok, %{"serializer" => "Fount.Screenplay.to_fdx/1", "losses" => exported.losses}}
    end
  end

  defp render("review_json", _candidate, packet, _progress, _run, _identity, path, _opts) do
    body = packet |> safe_packet() |> Jason.encode!(pretty: true)
    atomic_write(path, body) |> ok_metadata(%{"kind" => "exact_review_packet"})
  end

  defp render("review_markdown", _candidate, packet, _progress, run, identity, path, _opts) do
    body = review_markdown(run, packet, identity)
    atomic_write(path, body) |> ok_metadata(%{"kind" => "review_summary"})
  end

  defp render("source_diff", _candidate, packet, _progress, _run, _identity, path, _opts) do
    body =
      packet["source_diff"]
      |> Enum.map(fn {kind, text} -> %{"kind" => to_string(kind), "text" => text} end)
      |> Jason.encode!(pretty: true)

    atomic_write(path, body) |> ok_metadata(%{"kind" => "myers_source_diff"})
  end

  defp render("structural_diff", _candidate, packet, _progress, _run, _identity, path, _opts) do
    body = packet["structural_diff"] |> Model.plain() |> Jason.encode!(pretty: true)
    atomic_write(path, body) |> ok_metadata(%{"kind" => "screenplay_structural_diff"})
  end

  defp render("resources_checks", _candidate, packet, progress, _run, _identity, path, _opts) do
    body =
      %{
        "checks" => Model.plain(packet["checks"] || []),
        "required_checks" => packet["required_checks"] || [],
        "candidate_check_set_fingerprint" => packet["check_set_fingerprint"],
        "run_usage" => progress["usage"],
        "provider_requests" => progress["provider_requests"]
      }
      |> Jason.encode!(pretty: true)

    atomic_write(path, body) |> ok_metadata(%{"kind" => "resource_and_check_summary"})
  end

  defp render("provenance", candidate, packet, _progress, run, identity, path, _opts) do
    body =
      %{
        "run_id" => run["id"],
        "screenplay_id" => run["screenplay_id"],
        "plan_version" => run["current_plan_version"],
        "plan_fingerprint" => get_in(run, ["plan", "fingerprint"]),
        "policy_version" => run["current_policy_version"],
        "policy_fingerprint" => get_in(run, ["policy", "fingerprint"]),
        "completion_kind" => identity.kind,
        "candidate_id" => identity.candidate_id,
        "base_revision_id" => packet["base_revision_id"],
        "result_revision_id" => packet["result_revision_id"],
        "accepted_revision_id" => identity.accepted_revision_id,
        "acceptance_id" => identity.acceptance_id,
        "approval_id" => identity.approval_id,
        "approval_hash" => identity.approval_hash,
        "content_hash" => packet["content_hash"],
        "check_set_fingerprint" => packet["check_set_fingerprint"],
        "candidate_provenance" => Model.plain(candidate["provenance"] || %{}),
        "lineage" => Model.plain(candidate["lineage"] || [])
      }
      |> Jason.encode!(pretty: true)

    atomic_write(path, body) |> ok_metadata(%{"kind" => "delivery_provenance"})
  end

  defp render("pdf", candidate, _packet, _progress, _run, _identity, path, opts) do
    FountWorkshop.Export.PDF.export(candidate["screenplay"], path, Keyword.get(opts, :pdf_options, []))
  end

  defp render("table_read_json", candidate, _packet, _progress, _run, _identity, path, _opts),
    do: FountWorkshop.TableRead.export(candidate["screenplay"], path, :json)

  defp render("table_read_html", candidate, _packet, _progress, _run, _identity, path, _opts),
    do: FountWorkshop.TableRead.export(candidate["screenplay"], path, :html)

  defp render(format, _candidate, _packet, _progress, _run, _identity, _path, _opts),
    do: {:error, {:unsupported_delivery_format, format}}

  defp reusable_delivery(repo, run_id, identity, format, base_options, root) do
    rows =
      rows(
        repo,
        "SELECT * FROM fount_run_deliveries WHERE run_id=$1::text::uuid AND format=$2 ORDER BY inserted_at,id",
        [run_id, format]
      )
      |> Enum.filter(&same_identity?(&1, identity))
      |> Enum.filter(fn row -> comparable_options(row["options"] || %{}) == comparable_options(base_options) end)

    ready = Enum.reverse(rows) |> Enum.find(&(&1["state"] == "ready" and ready_file?(&1, root)))

    cond do
      ready ->
        {:ready, ready}

      rows == [] ->
        :new

      true ->
        prior = List.last(rows)
        max_retry = rows |> Enum.map(&(get_in(&1, ["options", "retry_index"]) || 0)) |> Enum.max(fn -> 0 end)
        {:retry, max_retry + 1, prior["id"]}
    end
  end

  defp same_identity?(row, %{kind: "accepted", accepted_revision_id: revision}),
    do: row["accepted_revision_id"] == revision and is_nil(row["candidate_id"])

  defp same_identity?(row, %{kind: "candidate", candidate_id: candidate}),
    do: row["candidate_id"] == candidate and is_nil(row["accepted_revision_id"])

  defp comparable_options(options), do: Map.drop(options, ["retry_index", "retry_of"])

  defp ready_file?(row, root) do
    location = row["output_location"]

    if is_binary(location) do
      path = Path.expand(location, root)
      prefix = Path.expand(root) <> "/"

      String.starts_with?(path <> "/", prefix) and File.regular?(path) and
        case File.read(path) do
          {:ok, bytes} -> sha256(bytes) == row["output_checksum"]
          _ -> false
        end
    else
      false
    end
  end

  defp format_options(format, relative_directory, opts) do
    base = %{"bundle_version" => 1, "destination" => relative_directory}

    case format do
      "pdf" -> Map.put(base, "pdf_settings", stringify_keyword(Keyword.get(opts, :pdf_options, [])))
      "table_read_json" -> Map.put(base, "table_read", true)
      "table_read_html" -> Map.put(base, "table_read", true)
      _ -> base
    end
  end

  defp stringify_keyword(values) when is_list(values),
    do: Map.new(values, fn {key, value} -> {to_string(key), value} end)

  defp stringify_keyword(_), do: %{}

  defp file_name("fountain"), do: "screenplay.fountain"
  defp file_name("fdx"), do: "screenplay.fdx"
  defp file_name("review_json"), do: "review.json"
  defp file_name("review_markdown"), do: "review.md"
  defp file_name("source_diff"), do: "source-diff.json"
  defp file_name("structural_diff"), do: "structural-diff.json"
  defp file_name("resources_checks"), do: "resources-checks.json"
  defp file_name("provenance"), do: "provenance.json"
  defp file_name("pdf"), do: "screenplay.pdf"
  defp file_name("table_read_json"), do: "table-read.json"
  defp file_name("table_read_html"), do: "table-read.html"

  defp safe_packet(packet) do
    packet
    |> Map.update("source_diff", [], fn diff ->
      Enum.map(diff, fn {kind, text} -> %{"kind" => to_string(kind), "text" => text} end)
    end)
    |> Model.plain()
  end

  defp review_markdown(run, packet, identity) do
    """
    # Fount Run review

    - Run: `#{run["id"]}`
    - Completion: `#{identity.kind}`
    - Candidate: `#{packet["candidate_id"]}`
    - Base revision: `#{packet["base_revision_id"]}`
    - Result revision: `#{packet["result_revision_id"]}`
    - Content hash: `#{packet["content_hash"]}`
    - Check set: `#{packet["check_set_fingerprint"]}`
    - Acceptance: `#{identity.acceptance_id || "none"}`

    This bundle reports the exact saved candidate and review evidence. Exporting candidate-only content does not advance canon.
    """
  end

  defp common_data(run, candidate, packet, _progress, identity) do
    %{
      "version" => 1,
      "run_id" => run["id"],
      "screenplay_id" => run["screenplay_id"],
      "completion_kind" => identity.kind,
      "candidate_id" => candidate["id"],
      "base_revision_id" => packet["base_revision_id"],
      "result_revision_id" => packet["result_revision_id"],
      "accepted_revision_id" => identity.accepted_revision_id,
      "acceptance_id" => identity.acceptance_id,
      "approval_id" => identity.approval_id,
      "content_hash" => packet["content_hash"],
      "check_set_fingerprint" => packet["check_set_fingerprint"],
      "plan_version" => run["current_plan_version"],
      "plan_fingerprint" => get_in(run, ["plan", "fingerprint"]),
      "policy_version" => run["current_policy_version"],
      "policy_fingerprint" => get_in(run, ["policy", "fingerprint"])
    }
  end

  defp build_manifest(common, relative_directory, results) do
    common
    |> Map.put("destination", relative_directory)
    |> Map.put("state", if(Enum.all?(results, &(&1["state"] == "ready")), do: "ready", else: "partial"))
    |> Map.put("artifacts", results)
  end

  defp result_row(format, row, replay) do
    %{
      "delivery_id" => row["id"],
      "format" => format,
      "state" => row["state"],
      "output_checksum" => row["output_checksum"],
      "output_location" => row["output_location"],
      "error" => row["error"],
      "reused" => replay
    }
  end

  defp ok_metadata(:ok, metadata), do: {:ok, metadata}
  defp ok_metadata({:error, _} = error, _metadata), do: error

  defp atomic_write(path, bytes) when is_binary(bytes) do
    tmp = path <> ".tmp-" <> Integer.to_string(System.unique_integer([:positive]))

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp, bytes, [:binary]),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, reason} = error ->
        File.rm(tmp)
        if is_atom(reason), do: error, else: {:error, :artifact_write_failed}
    end
  end

  defp relative_path(root, path) do
    case Path.relative_to(path, root) do
      "." -> "."
      value -> value
    end
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp error_code(reason) do
    case reason do
      atom when is_atom(atom) -> Atom.to_string(atom)
      {atom, _} when is_atom(atom) -> Atom.to_string(atom)
      {atom, _, _} when is_atom(atom) -> Atom.to_string(atom)
      _ -> "delivery_failed"
    end
  end


  defp one(repo, sql, params) do
    case q!(repo, sql, params) do
      %{columns: columns, rows: [row | _]} -> Map.new(Enum.zip(columns, row))
      _ -> nil
    end
  end

  defp rows(repo, sql, params) do
    result = q!(repo, sql, params)
    Enum.map(result.rows, &Map.new(Enum.zip(result.columns, &1)))
  end

  defp q!(repo, sql, params), do: SQL.query!(repo, sql, params)
end
