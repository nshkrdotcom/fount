defmodule FountWorkshop.NoteResponse do
  @moduledoc "Turns one writer note into exact screenplay edits and resolves it only in the candidate."

  alias Fount.{Persistence, Query, Screenplay}
  alias FountWorkshop.TargetedRewrite

  @doc "Proposes replacement pages for a note's selected targets."
  def propose(%Screenplay{} = base, note_id, target_ids, client) do
    note = Query.node(base, note_id)

    cond do
      note == nil or note.type != :note ->
        {:error, :unknown_note}

      not is_list(target_ids) or target_ids == [] ->
        {:error, :missing_targets}

      true ->
        note_scene = Query.scene_for(base, note_id)

        if note_scene == nil or
             Enum.any?(target_ids, fn id ->
               scene = Query.scene_for(base, id)
               scene == nil or scene.id != note_scene.id
             end) do
          {:error, :targets_outside_note_scene}
        else
          with {:ok, rewrite} <- TargetedRewrite.propose(base, target_ids, note.text, client),
               operations =
                 rewrite.changes.operations ++
                   [%{"kind" => "delete_elements", "value" => %{"ids" => [note_id]}}],
               {:ok, result, changes} <- Screenplay.apply(base, operations, []) do
            {:ok,
             %{
               screenplay: result,
               changes: changes,
               addressed_note_id: note_id,
               completion_trace: rewrite.completion_trace
             }}
          end
        end
    end
  end

  @doc "Stores the note response without changing the accepted revision."
  def run(repo, key, note_id, target_ids, client) do
    with {:ok, base} <- Persistence.load(repo, key),
         {:ok, session} <-
           Persistence.save_session(repo, %{
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             workflow: "notes",
             status: "running",
             request: %{"note_id" => note_id, "target_ids" => target_ids}
           }) do
      case propose(base, note_id, target_ids, client) do
        {:ok, proposal} ->
          candidate =
            Map.merge(proposal, %{
              label: "Response to note #{note_id}",
              change_groups: [
                %{
                  "id" => "note_#{note_id}",
                  "operations" => proposal.changes.operations,
                  "addressed_note_ids" => [note_id]
                }
              ],
              lineage: proposal.changes.lineage,
              provenance: %{
                "completion" => proposal.completion_trace,
                "addressed_note_ids" => [note_id]
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

              {:ok, %{session: updated, candidate: saved, accepted_revision_id: base.revision.id}}

            error ->
              mark_failed(repo, session, error)
              error
          end

        {:error, reason} ->
          mark_failed(repo, session, reason)
          {:error, reason}
      end
    end
  end

  defp mark_failed(repo, session, reason) do
    Persistence.save_session(
      repo,
      Map.merge(session, %{status: "failed", progress: %{"error" => inspect(reason)}})
    )
  end
end
