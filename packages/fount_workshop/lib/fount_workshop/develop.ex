defmodule FountWorkshop.Develop do
  @moduledoc "Generates editable screenplay candidates from a writer brief through Inference."

  alias Fount.{Query, Screenplay}
  alias Fount.Persistence
  alias FountWorkshop.Writing.Completion

  @types ~w(action character dialogue parenthetical transition centered lyric note blank)
  @schema %{
    "type" => "object",
    "required" => ["scenes", "approach"],
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

  @doc "Creates separate candidate values; the accepted base is never changed."
  def develop(base, brief, client, opts \\ [])

  def develop(%Screenplay{} = base, brief, client, opts)
      when is_binary(brief) and byte_size(brief) > 0 do
    approaches =
      Keyword.get(opts, :approaches, ["A direct dramatic route", "A contrasting dramatic route"])

    previous = Keyword.get(opts, :prior_candidates, [])
    route_start = Keyword.get(opts, :route_start, 1)

    after_id =
      Keyword.get(
        opts,
        :after_scene_id,
        List.last(base.ir.scenes) && List.last(base.ir.scenes).id
      )

    if after_id && !Query.scene(base, after_id) do
      {:error, :unknown_anchor}
    else
      approaches
      |> Enum.with_index(route_start)
      |> Enum.reduce_while({:ok, []}, fn {approach, index}, {:ok, acc} ->
        route_client = Enum.at(Keyword.get(opts, :clients, []), index - 1) || client
        prior = Enum.map(acc ++ previous, &Screenplay.to_fountain(&1.screenplay))

        with {:ok, output, trace} <-
               Completion.complete(
                 route_client,
                 prompt(base, brief, approach, after_id, prior),
                 @schema,
                 &validate/1,
                 name: "fount_develop"
               ),
             {:ok, screenplay, changes} <- materialize(base, output["scenes"], after_id) do
          candidate = %{
            label: "Route #{index}: #{approach}",
            screenplay: screenplay,
            changes: changes,
            approach: output["approach"],
            completion_trace: trace
          }

          if Enum.any?(
               acc ++ previous,
               &(&1.screenplay.revision.content_hash == screenplay.revision.content_hash)
             ) do
            {:halt, partial_result(acc, {:duplicate_candidate, index})}
          else
            {:cont, {:ok, [candidate | acc]}}
          end
        else
          {:error, reason, trace} ->
            {:halt, partial_result(acc, {:completion_failed, index, reason, trace})}

          {:error, reason} ->
            {:halt, partial_result(acc, {:candidate_failed, index, reason})}
        end
      end)
      |> case do
        {:ok, candidates} -> {:ok, Enum.reverse(candidates)}
        error -> error
      end
    end
  end

  def develop(_, _, _, _), do: {:error, :invalid_develop_request}

  defp partial_result([], reason), do: {:error, reason}
  defp partial_result(acc, reason), do: {:partial, Enum.reverse(acc), reason}

  @doc "Saves the writing session and all generated candidate pages in PostgreSQL."
  def run(repo, key, brief, client, opts \\ []) do
    approaches =
      Keyword.get(opts, :approaches, ["A direct dramatic route", "A contrasting dramatic route"])

    with {:ok, base} <- Persistence.load(repo, key),
         {:ok, session} <-
           Persistence.save_session(repo, %{
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             workflow: "develop",
             status: "running",
             request: %{"brief" => brief, "approaches" => approaches}
           }) do
      case develop(base, brief, client, opts) do
        {:ok, generated} ->
          case save_all(repo, session.id, generated) do
            {:ok, saved} ->
              {:ok, updated} =
                Persistence.save_session(
                  repo,
                  Map.merge(session, %{
                    status: "ready",
                    progress: %{"candidate_ids" => Enum.map(saved, & &1.id)}
                  })
                )

              {:ok,
               %{session: updated, candidates: saved, accepted_revision_id: base.revision.id}}

            {:error, reason, saved} ->
              {:ok, updated} =
                Persistence.save_session(
                  repo,
                  Map.merge(session, %{
                    status: "partial",
                    progress: %{
                      "candidate_ids" => Enum.map(saved, & &1.id),
                      "error" => inspect(reason)
                    }
                  })
                )

              {:partial,
               %{session: updated, candidates: saved, accepted_revision_id: base.revision.id},
               reason}
          end

        {:partial, generated, reason} ->
          case save_all(repo, session.id, generated) do
            {:ok, saved} ->
              {:ok, updated} =
                Persistence.save_session(
                  repo,
                  Map.merge(session, %{
                    status: "partial",
                    progress: %{
                      "candidate_ids" => Enum.map(saved, & &1.id),
                      "next_route" => length(saved) + 1,
                      "error" => inspect(reason)
                    }
                  })
                )

              {:partial,
               %{session: updated, candidates: saved, accepted_revision_id: base.revision.id},
               reason}

            {:error, save_reason, saved} ->
              {:ok, updated} =
                Persistence.save_session(
                  repo,
                  Map.merge(session, %{
                    status: "partial",
                    progress: %{
                      "candidate_ids" => Enum.map(saved, & &1.id),
                      "error" => inspect({reason, save_reason})
                    }
                  })
                )

              {:partial,
               %{session: updated, candidates: saved, accepted_revision_id: base.revision.id},
               {reason, save_reason}}
          end

        {:error, reason} ->
          Persistence.save_session(
            repo,
            Map.merge(session, %{
              status: "failed",
              progress: %{"error" => inspect(reason)}
            })
          )

          {:error, {:failed_session, session.id, reason}}
      end
    end
  end

  @doc "Continues a partial session from its next unfinished route."
  def resume(repo, session_id, client, opts \\ []) do
    with {:ok, session} <- Persistence.session(repo, session_id),
         true <- session["status"] == "partial",
         {:ok, base} <-
           Persistence.load_revision(repo, session["screenplay_id"], session["base_revision_id"]) do
      previous_rows = Persistence.candidates_for_session(repo, session_id)
      previous = Enum.map(previous_rows, &%{id: &1["id"], screenplay: &1["screenplay"]})
      next_route = session["progress"]["next_route"] || length(previous) + 1
      approaches = session["request"]["approaches"] || []
      remaining = Enum.drop(approaches, next_route - 1)

      if remaining == [],
        do: {:error, :no_remaining_routes},
        else: resume_routes(repo, session, base, previous, remaining, next_route, client, opts)
    else
      false -> {:error, :session_not_partial}
      error -> error
    end
  end

  defp resume_routes(repo, session, base, previous, approaches, next_route, client, opts) do
    opts =
      Keyword.merge(opts,
        approaches: approaches,
        prior_candidates: previous,
        route_start: next_route
      )

    generated = develop(base, session["request"]["brief"], client, opts)

    case generated do
      {status, candidates} when status == :ok ->
        finish_resume(repo, session, base, previous, candidates, :ready, nil)

      {:partial, candidates, reason} ->
        finish_resume(repo, session, base, previous, candidates, :partial, reason)

      {:error, reason} ->
        {:error, {:resume_failed, session["id"], reason}}
    end
  end

  defp finish_resume(repo, session, base, previous, candidates, status, reason) do
    case save_all(repo, session["id"], candidates) do
      {:ok, saved} ->
        all = previous ++ saved
        progress = %{"candidate_ids" => Enum.map(all, & &1.id)}

        progress =
          if status == :partial,
            do:
              Map.merge(progress, %{
                "next_route" => length(all) + 1,
                "error" => inspect(reason)
              }),
            else: progress

        {:ok, updated} =
          Persistence.save_session(
            repo,
            session |> Map.put(:status, to_string(status)) |> Map.put(:progress, progress)
          )

        result = %{session: updated, candidates: all, accepted_revision_id: base.revision.id}
        if status == :ready, do: {:ok, result}, else: {:partial, result, reason}

      {:error, save_reason, saved} ->
        all = previous ++ saved

        progress = %{
          "candidate_ids" => Enum.map(all, & &1.id),
          "next_route" => length(all) + 1,
          "error" => inspect(save_reason)
        }

        {:ok, updated} =
          Persistence.save_session(
            repo,
            session |> Map.put(:status, "partial") |> Map.put(:progress, progress)
          )

        {:partial, %{session: updated, candidates: all, accepted_revision_id: base.revision.id},
         save_reason}
    end
  end

  defp save_all(repo, session_id, candidates) do
    Enum.reduce_while(candidates, {:ok, []}, fn candidate, {:ok, acc} ->
      candidate =
        Map.merge(candidate, %{
          strategy: %{"approach" => candidate.approach},
          change_groups: [%{"id" => "draft", "operations" => candidate.changes.operations}],
          lineage: candidate.changes.lineage,
          provenance: %{"completion" => candidate.completion_trace}
        })

      case Persistence.save_candidate(repo, session_id, candidate) do
        {:ok, stored} -> {:cont, {:ok, [stored | acc]}}
        {:error, reason} -> {:halt, {:error, reason, Enum.reverse(acc)}}
      end
    end)
    |> case do
      {:ok, saved} -> {:ok, Enum.reverse(saved)}
      error -> error
    end
  end

  defp prompt(base, brief, approach, after_id, prior) do
    preceding =
      if after_id do
        ids = Query.scene(base, after_id).element_ids |> MapSet.new()

        base.ir.elements
        |> Enum.filter(&MapSet.member?(ids, &1.id))
        |> Enum.map_join("\n", &"#{&1.type}: #{&1.text}")
      else
        "The screenplay has no scenes. Begin with actual scenes."
      end

    """
    Write professional spec-screenplay pages from this writer brief. Make a distinct creative
    choice for this route. Give concrete dramatic action and dialogue a writer can revise.
    Preserve explicit facts and constraints. Return complete scenes, not an outline or commentary.
    Use standard INT./EXT. sluglines and screenplay elements in reading order. Character cues
    have type character; speeches have type dialogue. Avoid generic placeholders.

    Writer brief: #{brief}
    Route: #{approach}
    Preceding material: #{preceding}
    Previous alternatives to differ from: #{Enum.join(prior, "\n---\n")}
    """
  end

  defp validate(%{"scenes" => scenes, "approach" => approach})
       when is_list(scenes) and scenes != [] and is_binary(approach) do
    if Enum.all?(scenes, &valid_scene?/1), do: :ok, else: {:error, :invalid_scene_shape}
  end

  defp validate(_), do: {:error, :invalid_develop_output}

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

  defp materialize(base, scenes, after_id) do
    operations =
      scenes
      |> Enum.with_index()
      |> Enum.map(fn {scene, index} ->
        %{
          "kind" => "insert_scene",
          "value" => %{
            "after_scene_id" => if(index == 0, do: after_id, else: "new:scene_#{index - 1}"),
            "scene" => %{
              "local_id" => "new:scene_#{index}",
              "heading" => scene["heading"],
              "elements" =>
                scene["elements"]
                |> Enum.with_index()
                |> Enum.map(fn {element, ordinal} ->
                  element
                  |> Map.put_new("attrs", %{})
                  |> Map.put("local_id", "new:element_#{index}_#{ordinal}")
                end)
            }
          }
        }
      end)

    Screenplay.apply(base, operations, [])
  end
end
