defmodule FountWorkshop.CharacterRewrite do
  @moduledoc "Rewrites a character's dialogue progression with immediate partner replies."

  alias Fount.{Persistence, Query, Screenplay}
  alias FountWorkshop.TargetedRewrite

  @doc "Returns exact dialogue IDs selected for a character and responsive partners."
  def targets(%Screenplay{} = base, character_id, scene_ids) do
    cond do
      not Map.has_key?(base.cast, character_id) ->
        {:error, :unknown_character}

      not is_list(scene_ids) or scene_ids == [] or
          Enum.any?(scene_ids, &(Query.scene(base, &1) == nil)) ->
        {:error, :invalid_scene_selection}

      true ->
        speaker_cues =
          base.mentions
          |> Map.values()
          |> Enum.filter(
            &(&1.character_id == character_id and &1.role == :speaker_cue and
                &1.status == :confirmed)
          )
          |> Enum.map(& &1.element_id)
          |> MapSet.new()

        ids =
          base.ir.scenes
          |> Enum.filter(&(&1.id in scene_ids))
          |> Enum.flat_map(fn scene ->
            members = MapSet.new(scene.element_ids)

            blocks =
              Enum.filter(
                base.ir.dialogue_blocks,
                &MapSet.member?(members, &1.cue_id)
              )

            blocks
            |> Enum.with_index()
            |> Enum.flat_map(fn {block, index} ->
              if MapSet.member?(speaker_cues, block.cue_id) do
                own = dialogue_ids(base, block)

                partner =
                  case Enum.at(blocks, index + 1) do
                    nil -> []
                    next -> dialogue_ids(base, next)
                  end

                own ++ partner
              else
                []
              end
            end)
          end)
          |> Enum.uniq()

        if ids == [], do: {:error, :no_character_dialogue}, else: {:ok, ids}
    end
  end

  @doc "Generates multi-scene, exact-element candidate dialogue."
  def propose(%Screenplay{} = base, character_id, scene_ids, direction, client) do
    with {:ok, ids} <- targets(base, character_id, scene_ids) do
      character = base.cast[character_id]

      instruction = """
      Rewrite #{character.display_name}'s progression across the selected scenes according to
      the writer direction. Change the character's choices and how partners respond, not just
      vocabulary. Keep each scene's established outcome and continuity unless requested.
      Writer direction: #{direction}
      """

      case TargetedRewrite.propose(base, ids, instruction, client) do
        {:ok, result} ->
          {:ok, Map.merge(result, %{character_id: character_id, target_element_ids: ids})}

        error ->
          error
      end
    end
  end

  @doc "Saves the candidate and review session; leaves accepted pages untouched."
  def run(repo, key, character_id, scene_ids, direction, client) do
    with {:ok, base} <- Persistence.load(repo, key),
         {:ok, ids} <- targets(base, character_id, scene_ids),
         {:ok, session} <-
           Persistence.save_session(repo, %{
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             workflow: "character",
             status: "running",
             request: %{
               "character_id" => character_id,
               "scene_ids" => scene_ids,
               "target_element_ids" => ids,
               "direction" => direction
             }
           }) do
      case propose(base, character_id, scene_ids, direction, client) do
        {:ok, proposal} ->
          candidate =
            Map.merge(proposal, %{
              label: "Character rewrite: #{base.cast[character_id].display_name}",
              change_groups: [
                %{
                  "id" => "character_#{character_id}",
                  "operations" => proposal.changes.operations
                }
              ],
              lineage: proposal.changes.lineage,
              provenance: %{
                "completion" => proposal.completion_trace,
                "character_id" => character_id,
                "target_element_ids" => ids
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

  defp dialogue_ids(base, block) do
    Enum.filter(block.body_ids, &(Query.node(base, &1).type == :dialogue))
  end

  defp mark_failed(repo, session, reason) do
    Persistence.save_session(
      repo,
      Map.merge(session, %{status: "failed", progress: %{"error" => inspect(reason)}})
    )
  end
end
