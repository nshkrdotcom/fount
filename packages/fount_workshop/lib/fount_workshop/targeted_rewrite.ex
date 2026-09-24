defmodule FountWorkshop.TargetedRewrite do
  @moduledoc "Creates an exact-element writing candidate from a writer's revision direction."

  alias Fount.{Persistence, Query, Screenplay}
  alias FountWorkshop.Writing.Completion

  @editable [:action, :dialogue, :parenthetical, :lyric, :centered, :transition]

  @schema %{
    "type" => "object",
    "required" => ["changes"],
    "additionalProperties" => false,
    "properties" => %{
      "changes" => %{
        "type" => "array",
        "minItems" => 1,
        "items" => %{
          "type" => "object",
          "required" => ["element_id", "text"],
          "additionalProperties" => false,
          "properties" => %{
            "element_id" => %{"type" => "string"},
            "text" => %{"type" => "string"}
          }
        }
      }
    }
  }

  @doc "Rewrites selected action/dialogue elements and retains their exact identities."
  def propose(%Screenplay{} = base, element_ids, direction, client)
      when is_list(element_ids) and element_ids != [] and is_binary(direction) do
    selected = Enum.map(element_ids, &Query.node(base, &1))

    cond do
      String.trim(direction) == "" ->
        {:error, :empty_direction}

      length(Enum.uniq(element_ids)) != length(element_ids) or
        Enum.any?(selected, &(&1 == nil or &1.type not in @editable)) or
          Enum.any?(element_ids, &(Query.scene_for(base, &1) == nil)) ->
        {:error, :invalid_targets}

      true ->
        selected_scene_ids =
          element_ids
          |> Enum.map(&Query.scene_for(base, &1))
          |> Enum.reject(&is_nil/1)
          |> Enum.map(& &1.id)
          |> MapSet.new()

        selected_indices =
          base.ir.scenes
          |> Enum.with_index()
          |> Enum.filter(fn {scene, _} -> MapSet.member?(selected_scene_ids, scene.id) end)
          |> Enum.map(&elem(&1, 1))

        context_indices =
          selected_indices
          |> Enum.flat_map(&(max(0, &1 - 2)..min(length(base.ir.scenes) - 1, &1 + 2)))
          |> MapSet.new()

        context =
          base.ir.scenes
          |> Enum.with_index()
          |> Enum.filter(fn {scene, index} ->
            not scene.omitted? and MapSet.member?(context_indices, index)
          end)
          |> Enum.map_join("\n\n", fn {scene, _} ->
            label =
              if MapSet.member?(selected_scene_ids, scene.id),
                do: "TARGET SCENE",
                else: "CONTEXT SCENE"

            body =
              scene.element_ids
              |> Enum.map(&Query.node(base, &1))
              |> Enum.reject(&(&1.type in [:note, :boneyard, :section, :synopsis]))
              |> Enum.map_join("\n", &"#{&1.type}: #{&1.text}")

            "#{label}\n#{body}"
          end)

        targets =
          Enum.map_join(selected, "\n", &"#{&1.id} (#{&1.type}): #{&1.text}")

        prompt = """
        Revise only the listed screenplay elements. Return one replacement text for each exact ID.
        Keep the same screenplay element type, character intent, pronouns and established
        story facts unless the writer direction explicitly changes them. The surrounding
        scenes show continuity you must respect; only exact targets may be rewritten.
        Do not add scene headings, cues or commentary.

        Writer direction: #{direction}
        Surrounding scenes:\n#{context}
        Exact targets:\n#{targets}
        """

        allowed = MapSet.new(element_ids)

        case Completion.complete(client, prompt, @schema, &validate(&1, allowed),
               name: "fount_targeted_rewrite"
             ) do
          {:ok, %{"changes" => replacements}, trace} ->
            operations =
              Enum.map(replacements, fn item ->
                %{
                  "kind" => "replace_text",
                  "target" => %{"kind" => "element", "id" => item["element_id"]},
                  "value" => item["text"]
                }
              end)

            case Screenplay.apply(base, operations, []) do
              {:ok, result, changes} when result.revision.id != base.revision.id ->
                {:ok, %{screenplay: result, changes: changes, completion_trace: trace}}

              {:ok, _, _} ->
                {:error, :no_change}

              error ->
                error
            end

          {:error, reason, trace} ->
            {:error, {:completion_failed, reason, trace}}
        end
    end
  end

  def propose(_, _, _, _), do: {:error, :invalid_request}

  @doc "Saves the proposal and its reviewable revision; the accepted head stays put."
  def run(repo, key, element_ids, direction, client) do
    with {:ok, base} <- Persistence.load(repo, key),
         {:ok, session} <-
           Persistence.save_session(repo, %{
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             workflow: "pass",
             status: "running",
             request: %{
               "kind" => "targeted_rewrite",
               "element_ids" => element_ids,
               "direction" => direction
             }
           }) do
      case propose(base, element_ids, direction, client) do
        {:ok, proposal} ->
          candidate =
            Map.merge(proposal, %{
              label: "Targeted rewrite",
              change_groups: [%{"id" => "rewrite", "operations" => proposal.changes.operations}],
              lineage: proposal.changes.lineage,
              provenance: %{"completion" => proposal.completion_trace}
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
              Persistence.save_session(
                repo,
                Map.merge(session, %{status: "failed", progress: %{"error" => inspect(error)}})
              )

              error
          end

        {:error, reason} ->
          Persistence.save_session(
            repo,
            Map.merge(session, %{status: "failed", progress: %{"error" => inspect(reason)}})
          )

          {:error, reason}
      end
    end
  end

  defp validate(%{"changes" => changes}, allowed) when is_list(changes) do
    valid_rows =
      Enum.all?(changes, fn
        %{"element_id" => id, "text" => text} ->
          is_binary(id) and is_binary(text) and String.valid?(text) and String.trim(text) != ""

        _ ->
          false
      end)

    ids = if valid_rows, do: Enum.map(changes, & &1["element_id"]), else: []

    if valid_rows and length(ids) == MapSet.size(allowed) and MapSet.new(ids) == allowed do
      :ok
    else
      {:error, :invalid_rewrite_targets}
    end
  end

  defp validate(_, _), do: {:error, :invalid_rewrite_output}
end
