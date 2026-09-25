defmodule FountWorkshop.SequenceRebuild do
  @moduledoc "Rebuilds a selected run of scenes as a reviewable candidate."

  alias Fount.{Persistence, Query, Screenplay}
  alias FountWorkshop.Writing.Completion

  @types ~w(action character dialogue parenthetical transition centered lyric note blank)
  @schema %{
    "type" => "object",
    "required" => ["approach", "scenes"],
    "additionalProperties" => false,
    "properties" => %{
      "approach" => %{"type" => "string"},
      "scenes" => %{
        "type" => "array",
        "minItems" => 1,
        "items" => %{
          "type" => "object",
          "required" => ["heading", "elements"],
          "additionalProperties" => false,
          "properties" => %{
            "heading" => %{"type" => "string"},
            "elements" => %{
              "type" => "array",
              "minItems" => 1,
              "items" => %{
                "type" => "object",
                "required" => ["type", "text"],
                "additionalProperties" => false,
                "properties" => %{
                  "type" => %{"type" => "string", "enum" => @types},
                  "text" => %{"type" => "string"}
                }
              }
            }
          }
        }
      }
    }
  }

  @doc "Writes a new sequence with required passages preserved exactly."
  def propose(%Screenplay{} = base, scene_ids, direction, client, opts \\ []) do
    required = Keyword.get(opts, :required_texts, [])
    target_count = Keyword.get(opts, :target_scene_count)

    with :ok <- validate_selection(base, scene_ids),
         :ok <- validate_request(direction, required, target_count),
         {:ok, output, trace} <-
           Completion.complete(
             client,
             prompt(base, scene_ids, direction, required, target_count),
             @schema,
             &validate_output(&1, required, target_count),
             name: "fount_sequence_rebuild"
           ),
         {:ok, result, changes} <- materialize(base, scene_ids, output["scenes"]) do
      if result.revision.id == base.revision.id do
        {:error, :no_change}
      else
        {:ok,
         %{
           screenplay: result,
           changes: changes,
           approach: output["approach"],
           completion_trace: trace
         }}
      end
    else
      {:error, reason, trace} -> {:error, {:completion_failed, reason, trace}}
      error -> error
    end
  end

  @doc "Persists the candidate and session without advancing the accepted revision."
  def run(repo, key, scene_ids, direction, client, opts \\ []) do
    with {:ok, base} <- Persistence.load(repo, key),
         :ok <- validate_selection(base, scene_ids),
         {:ok, session} <-
           Persistence.save_session(repo, %{
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             workflow: "sequence",
             status: "running",
             request: %{
               "scene_ids" => scene_ids,
               "direction" => direction,
               "required_texts" => Keyword.get(opts, :required_texts, []),
               "target_scene_count" => Keyword.get(opts, :target_scene_count)
             }
           }) do
      case propose(base, scene_ids, direction, client, opts) do
        {:ok, proposal} ->
          candidate =
            Map.merge(proposal, %{
              label: "Sequence route: #{proposal.approach}",
              strategy: %{"approach" => proposal.approach},
              change_groups: [%{"id" => "sequence", "operations" => proposal.changes.operations}],
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

  defp validate_selection(base, ids) when is_list(ids) and ids != [] do
    indices = Enum.map(ids, &Enum.find_index(base.ir.scenes, fn scene -> scene.id == &1 end))

    cond do
      Enum.any?(indices, &is_nil/1) ->
        {:error, :unknown_scene}

      length(Enum.uniq(ids)) != length(ids) ->
        {:error, :duplicate_scene}

      indices != Enum.to_list(hd(indices)..List.last(indices)) ->
        {:error, :noncontiguous_sequence}

      true ->
        :ok
    end
  end

  defp validate_selection(_, _), do: {:error, :invalid_scene_selection}

  defp validate_request(direction, required, count) do
    cond do
      not is_binary(direction) or String.trim(direction) == "" ->
        {:error, :empty_direction}

      not is_list(required) or Enum.any?(required, &(not is_binary(&1) or &1 == "")) ->
        {:error, :invalid_required_texts}

      count != nil and (not is_integer(count) or count < 1) ->
        {:error, :invalid_target_scene_count}

      true ->
        :ok
    end
  end

  defp prompt(base, ids, direction, required, count) do
    selected = Enum.map(ids, &Query.scene(base, &1))
    first = Enum.find_index(base.ir.scenes, &(&1.id == hd(ids)))
    last = Enum.find_index(base.ir.scenes, &(&1.id == List.last(ids)))
    before_scene = if first > 0, do: Enum.at(base.ir.scenes, first - 1), else: nil
    after_scene = Enum.at(base.ir.scenes, last + 1)

    """
    Rebuild the selected screenplay sequence as actual spec-script scenes, not an outline.
    Make causal action and character choices do the work. Keep the entrance and exit
    compatible with the neighboring scenes. Return only the replacement scenes.
    Writer direction: #{direction}
    Target scene count: #{target_count_text(count)}
    Exact passages that must survive: #{inspect(required)}
    Previous scene: #{scene_text(base, before_scene)}
    Selected scenes: #{Enum.map_join(selected, "\n\n", &scene_text(base, &1))}
    Following scene: #{scene_text(base, after_scene)}
    """
  end

  defp target_count_text(nil), do: "writer's choice"
  defp target_count_text(count), do: Integer.to_string(count)
  defp scene_text(_, nil), do: "None"

  defp scene_text(base, scene) do
    Enum.map_join(scene.element_ids, "\n", fn id ->
      element = Query.node(base, id)
      "#{element.type}: #{element.text}"
    end)
  end

  defp validate_output(%{"approach" => approach, "scenes" => scenes}, required, count)
       when is_binary(approach) and is_list(scenes) and scenes != [] do
    text =
      Enum.map_join(scenes, "\n", fn scene ->
        Enum.map_join(Map.get(scene, "elements", []), "\n", &Map.get(&1, "text", ""))
      end)

    cond do
      count != nil and length(scenes) != count ->
        {:error, :wrong_scene_count}

      Enum.any?(required, &(not String.contains?(text, &1))) ->
        {:error, :missing_required_passage}

      not Enum.all?(scenes, &valid_scene?/1) ->
        {:error, :invalid_scene_shape}

      true ->
        :ok
    end
  end

  defp validate_output(_, _, _), do: {:error, :invalid_sequence_output}

  defp valid_scene?(%{"heading" => heading, "elements" => elements})
       when is_binary(heading) and is_list(elements) and elements != [] do
    Fount.SceneHeading.standard_fountain?(heading) and valid_elements?(elements)
  end

  defp valid_scene?(_), do: false

  defp valid_elements?(elements) do
    Enum.reduce_while(elements, false, fn
      %{"type" => type, "text" => text}, cue_active
      when is_binary(type) and is_binary(text) ->
        cond do
          type not in @types or not String.valid?(text) or String.trim(text) == "" ->
            {:halt, :invalid}

          type in ["dialogue", "parenthetical"] and not cue_active ->
            {:halt, :invalid}

          type in ["character", "dialogue", "parenthetical"] ->
            {:cont, true}

          true ->
            {:cont, false}
        end

      _, _ ->
        {:halt, :invalid}
    end) != :invalid
  end

  defp materialize(base, ids, scenes) do
    old_scenes = Enum.map(ids, &Query.scene(base, &1))
    old_by_heading = Enum.group_by(old_scenes, &Query.node(base, &1.heading_id).text)

    old_elements =
      old_scenes
      |> Enum.flat_map(& &1.element_ids)
      |> Enum.map(&Query.node(base, &1))
      |> Enum.group_by(&{to_string(&1.type), &1.text})

    {specs, _used_scenes, _used_elements} =
      scenes
      |> Enum.with_index()
      |> Enum.reduce({[], MapSet.new(), MapSet.new()}, fn {scene, index}, {acc, used_s, used_e} ->
        matching =
          case old_by_heading[scene["heading"]] do
            [one] -> one
            _ -> nil
          end

        retained = matching && not MapSet.member?(used_s, matching.id)
        scene_spec = %{"heading" => scene["heading"], "elements" => []}

        scene_spec =
          if retained,
            do: Map.put(scene_spec, "id", matching.id),
            else: Map.put(scene_spec, "local_id", "new:scene_#{index}")

        used_s = if retained, do: MapSet.put(used_s, matching.id), else: used_s

        {elements, used_e} =
          scene["elements"]
          |> Enum.with_index()
          |> Enum.map_reduce(used_e, fn {element, ordinal}, used ->
            matching_element =
              old_elements[{element["type"], element["text"]}]
              |> List.wrap()
              |> Enum.find(&(not MapSet.member?(used, &1.id)))

            if matching_element do
              {%{"keep" => matching_element.id}, MapSet.put(used, matching_element.id)}
            else
              {element
               |> Map.put_new("attrs", %{})
               |> Map.put("local_id", "new:element_#{index}_#{ordinal}"), used}
            end
          end)

        {[Map.put(scene_spec, "elements", elements) | acc], used_s, used_e}
      end)

    Screenplay.apply(
      base,
      [
        %{
          "kind" => "replace_sequence",
          "value" => %{"scene_ids" => ids, "scenes" => Enum.reverse(specs)}
        }
      ],
      []
    )
  end
end
