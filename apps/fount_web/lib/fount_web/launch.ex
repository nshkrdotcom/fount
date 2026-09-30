defmodule FountWeb.Launch do
  @moduledoc "Creates the canonical genesis project, Run, and intake operation without advancing canon afterward."
  alias Fount.{Persistence, Screenplay}
  alias FountRun.PipelineRequest

  @max_bytes 1_048_576

  def create(owner_id, attrs) when is_binary(owner_id) and is_map(attrs) do
    source = Map.get(attrs, "source", "")
    filename = Map.get(attrs, "filename", "project.fountain")
    key = Map.get(attrs, "key", "") |> String.trim()
    title = Map.get(attrs, "title", "Untitled") |> String.trim()
    journey = Map.get(attrs, "journey", "opening")

    with :ok <- validate_input(key, title, journey, source),
         {:ok, root} <- parse(source, filename),
         {:ok, _created} <- Persistence.create(Fount.Repo, key, root),
         {:ok, project} <-
           FountWeb.Store.create_project(Fount.Repo, %{
             owner_id: owner_id,
             screenplay_id: root.id,
             key: key,
             title: title
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
    if String.ends_with?(String.downcase(filename), ".fdx") do
      case Screenplay.from_fdx(source) do
        {:ok, root, _losses} -> {:ok, root}
        {:error, reason} -> {:error, {:invalid_fdx, reason}}
      end
    else
      with {:ok, doc} <- Fount.parse(source),
           do: {:ok, Screenplay.from_document(doc, cast_resolution: :literal_cues)}
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

  defp goal("opening"), do: "Produce a checked opening candidate without advancing canon"

  defp goal("reveal"),
    do:
      "Move the reveal while preserving the protected train beat and approve exact checked pages"

  defp goal("dialogue"),
    do: "Revise selected-scene dialogue only and exercise configured automated approval"

  defp goal("analysis"),
    do: "Produce an Observe-backed checked dialogue candidate without advancing canon"

  defp preset(%{"completion" => "candidate"}), do: "candidate"
  defp preset(%{"approver" => %{"type" => type}}), do: "accept:" <> type
  defp preset(_), do: "custom"
end
