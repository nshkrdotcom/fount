defmodule FountWorkshop.Recover do
  @moduledoc "Restores or adapts exact historical screenplay material as a candidate."
  alias Fount.Persistence
  alias Fount.Query
  alias Fount.Screenplay

  @doc "Restores one historical element by ID, preserving its identity when possible."
  def propose(%Screenplay{} = current, %Screenplay{} = source, element_id)
      when is_binary(element_id) do
    historical = Query.node(source, element_id)

    cond do
      source.id != current.id ->
        {:error, :wrong_screenplay}

      historical == nil ->
        {:error, :unknown_historical_element}

      historical.type not in [
        :action,
        :dialogue,
        :parenthetical,
        :lyric,
        :note,
        :centered,
        :transition
      ] ->
        {:error, :unsupported_historical_element}

      true ->
        current_element = Query.node(current, element_id)

        case current_element do
          nil -> restore_cut(current, source, historical)
          _ -> restore_text(current, source, historical, current_element)
        end
    end
  end

  def propose(_, _, _), do: {:error, :invalid_recovery_request}

  @doc "Loads actual historical and accepted values, then saves a recovery candidate."
  def run(repo, key, source_revision_id, element_id) do
    with {:ok, current} <- Persistence.load(repo, key),
         {:ok, source} <- Persistence.load_revision(repo, current.id, source_revision_id),
         {:ok, session} <-
           Persistence.save_session(repo, %{
             screenplay_id: current.id,
             base_revision_id: current.revision.id,
             workflow: "recover",
             status: "running",
             request: %{"source_revision_id" => source_revision_id, "element_id" => element_id}
           }) do
      run_recovery(repo, current, source, session, source_revision_id, element_id)
    end
  end

  defp run_recovery(repo, current, source, session, source_revision_id, element_id) do
    case propose(current, source, element_id) do
      {:ok, proposal} ->
        candidate =
          Map.merge(proposal, %{
            label: "Restore from revision #{source_revision_id}",
            change_groups: [
              %{"id" => "restore_#{element_id}", "operations" => proposal.changes.operations}
            ],
            lineage: proposal.changes.lineage,
            provenance: %{
              "source_revision_id" => source_revision_id,
              "source_element_id" => element_id,
              "source_excerpt" => proposal.source_text,
              "current_excerpt" => proposal.current_text
            }
          })

        case Persistence.save_candidate(repo, session.id, candidate) do
          {:ok, saved} ->
            {:ok, updated} =
              Persistence.save_session(
                repo,
                Map.merge(session, %{
                  status: "ready",
                  progress: %{"candidate_ids" => [saved.id]}
                })
              )

            {:ok,
             %{session: updated, candidate: saved, accepted_revision_id: current.revision.id}}

          error ->
            mark_failed(repo, session, error)
            error
        end

      {:error, reason} ->
        mark_failed(repo, session, reason)
        {:error, reason}
    end
  end

  defp restore_text(current, source, historical, existing) do
    if historical.type != existing.type do
      {:error, :historical_type_changed}
    else
      op = %{
        "kind" => "replace_text",
        "target" => %{"kind" => "element", "id" => existing.id},
        "value" => historical.text
      }

      finish(current, source, historical, existing.text, [op], [])
    end
  end

  defp restore_cut(current, source, historical) do
    scene = Query.scene_for(source, historical.id)
    current_scene = scene && Query.scene(current, scene.id)

    if current_scene == nil do
      {:error, :source_scene_missing}
    else
      position = position_for(current, scene, historical.id)

      op = %{
        "kind" => "insert_elements",
        "target" => %{"kind" => "scene", "id" => scene.id},
        "value" => Map.merge(position, %{"elements" => [%{"keep" => historical.id}]})
      }

      finish(current, source, historical, nil, [op],
        restore_registry: %{historical.id => historical}
      )
    end
  end

  defp position_for(current, scene, element_id) do
    index = Enum.find_index(scene.element_ids, &(&1 == element_id))

    earlier =
      scene.element_ids
      |> Enum.take(index)
      |> Enum.reverse()
      |> Enum.find(&(Query.node(current, &1) != nil))

    later =
      scene.element_ids
      |> Enum.drop(index + 1)
      |> Enum.find(&(Query.node(current, &1) != nil))

    cond do
      earlier && earlier != scene.heading_id ->
        %{"position" => "after", "anchor_id" => earlier}

      later && later != scene.heading_id ->
        %{"position" => "before", "anchor_id" => later}

      true ->
        %{"position" => "start"}
    end
  end

  defp finish(current, source, historical, current_text, operations, opts) do
    case Screenplay.apply(current, operations, opts) do
      {:ok, result, changes} when result.revision.id != current.revision.id ->
        {:ok,
         %{
           screenplay: result,
           changes: changes,
           source_revision_id: source.revision.id,
           source_element_id: historical.id,
           source_text: historical.text,
           current_text: current_text,
           proposed_text: Query.node(result, historical.id).text
         }}

      {:ok, _, _} ->
        {:error, :already_current}

      error ->
        error
    end
  end

  defp mark_failed(repo, session, reason) do
    Persistence.save_session(
      repo,
      Map.merge(session, %{status: "failed", progress: %{"error" => inspect(reason)}})
    )
  end
end
