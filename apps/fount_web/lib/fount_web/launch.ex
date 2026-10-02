defmodule FountWeb.Launch do
  @moduledoc "Creates owner-bound screenplay projects and starts durable creative tasks only when explicitly requested."
  alias Ecto.Adapters.SQL
  alias Fount.{Persistence, Screenplay}
  alias Fount.Writing.CanonicalJSON
  alias FountRun.PipelineRequest

  @max_bytes 1_048_576

  @doc "Creates an owner-bound screenplay project without creating an AI Run."
  def create_project(owner_id, attrs) when is_binary(owner_id) and is_map(attrs) do
    Fount.Repo.transaction(fn ->
      case persist_project(owner_id, attrs) do
        {:ok, created} -> created
        {:error, reason} -> Fount.Repo.rollback(reason)
      end
    end)
  end

  defp persist_project(owner_id, attrs) do
    title = Map.get(attrs, "title", "Untitled screenplay") |> String.trim()
    kind = Map.get(attrs, "kind", "import")
    filename = Map.get(attrs, "filename", "project.fountain")
    source = Map.get(attrs, "source", "")
    project_kind = if Map.get(attrs, "example", false), do: "example", else: "screenplay"

    with :ok <- validate_project_title(title),
         {:ok, root, import} <- project_root(kind, title, source, filename),
         {:ok, key} <- generated_project_key(owner_id, title),
         {:ok, _created} <- Persistence.create(Fount.Repo, key, root),
         {:ok, project} <-
           FountWeb.Store.create_project(Fount.Repo, %{
             owner_id: owner_id,
             screenplay_id: root.id,
             key: key,
             title: title,
             synopsis: optional_text(attrs, "synopsis", 4_000),
             logline: optional_text(attrs, "logline", 1_000),
             thumbnail_ref: nil,
             import_format: import["format"],
             import_fidelity: import,
             project_kind: project_kind,
             source_name: import["source_name"]
           }),
         {:ok, persisted_root} <- Persistence.load(Fount.Repo, key),
         {:ok, _inventory} <-
           FountWeb.SemanticStore.ensure_inventory(Fount.Repo, owner_id, project, persisted_root) do
      {:ok, %{project: project, screenplay: persisted_root, import: import}}
    end
  end

  @doc "Parses an uploaded screenplay for the UX01 preview without writing project or Run state."
  def preview_import(source, filename) when is_binary(source) and is_binary(filename) do
    with :ok <- validate_import_source(source), do: parse(source, filename)
  end

  defp project_root("blank", _title, _source, _filename) do
    root = Screenplay.new()

    {:ok, root,
     %{
       "format" => "blank",
       "source_name" => nil,
       "source_bytes" => 0,
       "parsed" => true,
       "adapter_losses" => [],
       "loss_count" => 0,
       "original_bytes_preserved_when_unchanged" => true
     }}
  end

  defp project_root(kind, _title, source, filename) when kind in ["import", "example"] do
    with :ok <- validate_import_source(source),
         {:ok, root, import} <- parse(source, filename) do
      {:ok, root, Map.put(import, "source_name", filename)}
    end
  end

  defp project_root(_, _title, _source, _filename), do: {:error, :invalid_project_kind}

  defp validate_project_title(title) do
    cond do
      title == "" -> {:error, :title_required}
      byte_size(title) > 160 -> {:error, :title_too_long}
      true -> :ok
    end
  end

  defp validate_import_source(source) do
    cond do
      not is_binary(source) or byte_size(source) == 0 -> {:error, :source_required}
      byte_size(source) > @max_bytes -> {:error, :source_too_large}
      true -> :ok
    end
  end

  defp generated_project_key(owner_id, title) do
    base = slug(title)

    # Core keys are globally unique, including across host owners. Allocate
    # under a transaction lock so two imports cannot select the same free key.
    with {:ok, _} <-
           SQL.query(
             Fount.Repo,
             "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
             ["fount:generated-project-key"],
             log: false
           ) do
      key =
        1
        |> Stream.iterate(&(&1 + 1))
        |> Stream.map(fn
          1 -> base
          n -> base <> "-" <> Integer.to_string(n)
        end)
        |> Enum.find(&project_key_available?(owner_id, &1))

      {:ok, key}
    end
  end

  defp project_key_available?(owner_id, key) do
    FountWeb.Store.project_key_available?(Fount.Repo, owner_id, key) and
      match?({:error, :not_found}, Persistence.load(Fount.Repo, key))
  end

  defp slug(title) do
    title
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "untitled-screenplay"
      value -> value |> String.slice(0, 48) |> String.trim("-")
    end
  end

  def create(owner_id, attrs) when is_binary(owner_id) and is_map(attrs) do
    source = Map.get(attrs, "source", "")
    filename = Map.get(attrs, "filename", "project.fountain")
    key = Map.get(attrs, "key", "") |> String.trim()
    title = Map.get(attrs, "title", "Untitled") |> String.trim()
    journey = Map.get(attrs, "journey", "opening")

    with :ok <- validate_input(key, title, journey, source),
         {:ok, root, import} <- parse(source, filename),
         {:ok, _created} <- Persistence.create(Fount.Repo, key, root),
         {:ok, project} <-
           FountWeb.Store.create_project(Fount.Repo, %{
             owner_id: owner_id,
             screenplay_id: root.id,
             key: key,
             title: title,
             synopsis: optional_text(attrs, "synopsis", 4_000),
             thumbnail_ref: optional_text(attrs, "thumbnail_ref", 2_048),
             import_format: import["format"],
             import_fidelity: import
           }),
         {:ok, context} <- FountWeb.Actors.owner_context(owner_id, root.id),
         config <- FountWeb.Journeys.configuration(root, journey, owner_id),
         {:ok, run} <-
           FountRun.start_run(
             Fount.Repo,
             run_attrs(root, config, journey, "web:" <> project["id"]),
             context
           ),
         {:ok, access} <-
           FountWeb.Store.register_run(Fount.Repo, %{
             run_id: run["id"],
             project_id: project["id"],
             owner_id: owner_id,
             preset: preset(config.policy),
             journey: journey
           }),
         {:ok, envelope} <- PipelineRequest.new(config.request),
         {:ok, _step} <-
           FountRun.enqueue_step(Fount.Repo, run["id"], intake(root, envelope), context) do
      {:ok,
       %{
         project: project,
         run: run,
         access: Map.merge(access, %{"screenplay_id" => root.id, "key" => key, "title" => title})
       }}
    end
  end

  @doc "Starts a new Run from the project's current accepted head without creating a new genesis revision."
  def create_from_project(owner_id, project_id, attrs)
      when is_binary(owner_id) and is_binary(project_id) and is_map(attrs) do
    journey = Map.get(attrs, "journey", "opening")
    command_id = Map.get(attrs, "command_id", "") |> String.trim()

    with :ok <- validate_existing(journey, command_id),
         {:ok, project} <- FountWeb.Store.project(Fount.Repo, owner_id, project_id),
         {:ok, root} <- Persistence.load(Fount.Repo, project["key"]),
         true <- root.id == project["screenplay_id"],
         {:ok, context} <- FountWeb.Actors.owner_context(owner_id, root.id),
         config <- FountWeb.Journeys.configuration(root, journey, owner_id),
         {:ok, run} <-
           FountRun.start_run(
             Fount.Repo,
             run_attrs(root, config, journey, "web-existing:" <> command_id),
             context
           ),
         {:ok, access} <-
           FountWeb.Store.register_run(Fount.Repo, %{
             run_id: run["id"],
             project_id: project["id"],
             owner_id: owner_id,
             preset: preset(config.policy),
             journey: journey
           }),
         {:ok, envelope} <- PipelineRequest.new(config.request),
         {:ok, _step} <-
           FountRun.enqueue_step(Fount.Repo, run["id"], intake(root, envelope), context) do
      {:ok,
       %{
         project: project,
         run: run,
         access:
           Map.merge(access, %{
             "screenplay_id" => root.id,
             "key" => project["key"],
             "title" => project["title"]
           })
       }}
    else
      false -> {:error, :project_screenplay_mismatch}
      {:error, _} = error -> error
    end
  end

  @doc "Starts the generic authoring AI journey from an owner-bound saved manual candidate without accepting it."
  def create_from_candidate(owner_id, project_id, candidate_id, attrs)
      when is_binary(owner_id) and is_binary(project_id) and is_binary(candidate_id) and
             is_map(attrs) do
    command_id = Map.get(attrs, "command_id", "") |> String.trim()

    with :ok <- validate_authoring_command(command_id),
         {:ok, project} <- FountWeb.Store.project(Fount.Repo, owner_id, project_id),
         {:ok, head} <- Persistence.load(Fount.Repo, project["key"]),
         {:ok, candidate} <- Persistence.candidate(Fount.Repo, candidate_id),
         true <- candidate["screenplay_id"] == project["screenplay_id"],
         true <- candidate["base_revision_id"] == head.revision.id,
         true <- candidate["decision"] == "proposed",
         root <- candidate["screenplay"],
         {:ok, context} <- FountWeb.Actors.owner_context(owner_id, root.id),
         config <- FountWeb.Journeys.configuration(root, "opening", owner_id),
         {:ok, run} <-
           FountRun.start_run(
             Fount.Repo,
             run_attrs(root, config, "opening", "web-authoring:" <> command_id),
             context
           ),
         {:ok, access} <-
           FountWeb.Store.register_run(Fount.Repo, %{
             run_id: run["id"],
             project_id: project["id"],
             owner_id: owner_id,
             preset: preset(config.policy),
             journey: "opening"
           }),
         {:ok, envelope} <- PipelineRequest.new(config.request),
         {:ok, _step} <-
           FountRun.enqueue_step(Fount.Repo, run["id"], intake(root, envelope), context) do
      {:ok,
       %{
         project: project,
         run: run,
         access:
           Map.merge(access, %{
             "screenplay_id" => root.id,
             "key" => project["key"],
             "title" => project["title"]
           })
       }}
    else
      false -> {:error, :authoring_candidate_stale_or_unbound}
      {:error, _} = error -> error
    end
  end

  @doc "Starts a validated creative action from an exact owner-authorized screenplay revision."
  def create_action_from_base(owner_id, project_id, base_revision_id, attrs)
      when is_binary(owner_id) and is_binary(project_id) and is_binary(base_revision_id) and
             is_map(attrs) do
    command_id = Map.get(attrs, "command_id", "") |> String.trim()
    action = Map.get(attrs, "action", "")
    instruction = Map.get(attrs, "instruction", "")
    selection = Map.get(attrs, "selection")
    policy = Map.get(attrs, "policy")
    request_attrs = Map.get(attrs, "request_attrs", %{})

    with :ok <- validate_authoring_command(command_id),
         {:ok, project} <- FountWeb.Store.project(Fount.Repo, owner_id, project_id),
         {:ok, root} <-
           Persistence.load_revision(Fount.Repo, project["screenplay_id"], base_revision_id),
         true <- root.id == project["screenplay_id"],
         {:ok, context} <- FountWeb.Actors.owner_context(owner_id, root.id),
         {:ok, request} <-
           FountWeb.WorkflowManagement.build_workshop_request(
             root,
             action,
             instruction,
             selection,
             request_attrs
           ),
         {:ok, validated_policy} <- FountRun.Policy.new(policy, context),
         {:ok, run} <-
           FountRun.start_run(
             Fount.Repo,
             action_run_attrs(
               root,
               request,
               validated_policy.value,
               instruction,
               "web-action:" <> command_id
             ),
             context
           ),
         {:ok, access} <-
           FountWeb.Store.register_run(Fount.Repo, %{
             run_id: run["id"],
             project_id: project["id"],
             owner_id: owner_id,
             preset: preset(validated_policy.value),
             journey: "workflow:" <> action
           }),
         {:ok, envelope} <- PipelineRequest.new(request),
         {:ok, _step} <-
           FountRun.enqueue_step(Fount.Repo, run["id"], intake(root, envelope), context) do
      {:ok,
       %{
         project: project,
         run: run,
         access:
           Map.merge(access, %{
             "screenplay_id" => root.id,
             "key" => project["key"],
             "title" => project["title"]
           })
       }}
    else
      false -> {:error, :project_screenplay_mismatch}
      {:error, _} = error -> error
    end
  end

  defp action_run_attrs(root, request, policy, instruction, idempotency_key) do
    %{
      "screenplay_id" => root.id,
      "base_revision_id" => root.revision.id,
      "goal" => String.trim(instruction),
      "scope" => request["selection"],
      "constraints" => request["constraints"] || [],
      "protected_material" => get_in(request, ["options", "protected_text"]) || [],
      "client_idempotency_key" => idempotency_key,
      "operation_parameters" => %{
        "workflow" => request["workflow"],
        "request_fingerprint" => CanonicalJSON.hash(request),
        "selection_fingerprint" => CanonicalJSON.hash(request["selection"])
      },
      "policy" => policy
    }
  end

  defp validate_authoring_command(command_id) do
    if command_id != "" and byte_size(command_id) <= 128,
      do: :ok,
      else: {:error, :invalid_command_id}
  end

  defp validate_input(key, title, journey, source) do
    cond do
      not Regex.match?(~r/^[a-z0-9][a-z0-9_-]{1,63}$/, key) -> {:error, :invalid_project_key}
      title == "" -> {:error, :title_required}
      journey not in FountWeb.Journeys.names() -> {:error, :invalid_journey}
      not is_binary(source) or byte_size(source) == 0 -> {:error, :source_required}
      byte_size(source) > @max_bytes -> {:error, :source_too_large}
      true -> :ok
    end
  end

  defp validate_existing(journey, command_id) do
    cond do
      journey not in FountWeb.Journeys.names() -> {:error, :invalid_journey}
      command_id == "" or byte_size(command_id) > 128 -> {:error, :invalid_command_id}
      true -> :ok
    end
  end

  defp parse(source, filename) do
    lower = String.downcase(filename)

    cond do
      String.ends_with?(lower, ".fdx") ->
        case Screenplay.from_fdx(source) do
          {:ok, root, losses} ->
            {:ok, root,
             %{
               "format" => "fdx",
               "source_bytes" => byte_size(source),
               "parsed" => true,
               "adapter_losses" => losses,
               "loss_count" => length(losses),
               "original_bytes_preserved_when_unchanged" => true
             }}

          {:error, reason} ->
            {:error, {:invalid_fdx, reason}}
        end

      String.ends_with?(lower, ".fountain") ->
        with {:ok, doc} <- Fount.parse(source) do
          root = Screenplay.from_document(doc, cast_resolution: :manual)

          {:ok, root,
           %{
             "format" => "fountain",
             "source_bytes" => byte_size(source),
             "parsed" => true,
             "adapter_losses" => [],
             "loss_count" => 0,
             "original_bytes_preserved_when_unchanged" => Screenplay.to_fountain(root) == source
           }}
        end

      true ->
        {:error, :unsupported_screenplay_format}
    end
  end

  defp optional_text(attrs, key, max_bytes) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "" or byte_size(value) > max_bytes, do: nil, else: value

      _ ->
        nil
    end
  end

  defp run_attrs(root, config, journey, idempotency_key) do
    %{
      "screenplay_id" => root.id,
      "base_revision_id" => root.revision.id,
      "goal" => goal(journey),
      "scope" => config.request["selection"],
      "constraints" => [],
      "protected_material" => config.protected_material,
      "client_idempotency_key" => idempotency_key,
      "operation_parameters" => %{"workflow" => config.workflow},
      "policy" => config.policy
    }
  end

  defp intake(root, envelope) do
    %{
      "stage" => "intake",
      "iteration" => 0,
      "branch_id" => "main",
      "input_revision_id" => root.revision.id,
      "idempotency_key" => "pipeline-intake",
      "request" => envelope
    }
  end

  defp goal("opening"),
    do: "Propose an opening, check it and leave the approved screenplay unchanged"

  defp goal("reveal"),
    do:
      "Move the reveal while preserving the protected train beat and approve exact checked pages"

  defp goal("dialogue"),
    do: "Revise selected-scene dialogue only and exercise configured automated approval"

  defp goal("analysis"),
    do:
      "Propose dialogue changes with analysis and required checks, leaving the approved screenplay unchanged"

  defp preset(%{"completion" => "candidate"}), do: "candidate"
  defp preset(%{"approver" => %{"type" => type}}), do: "accept:" <> type
  defp preset(_), do: "custom"
end
