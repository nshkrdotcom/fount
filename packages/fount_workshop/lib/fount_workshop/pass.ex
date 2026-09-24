defmodule FountWorkshop.Pass do
  @moduledoc "Runs one writer-directed creative pass as an editable candidate."

  alias Fount.{Persistence, Query, Screenplay}
  alias FountWorkshop.{SequenceRebuild, TargetedRewrite}

  @profiles ~w(action_visual brevity custom dialogue_subtext dry_comedy tension)

  @doc "Returns the six callable profile IDs."
  def profiles, do: @profiles

  @doc "Loads a shipped writing direction, without treating its craft advice as a rule."
  def profile(id) when id in @profiles do
    path = Application.app_dir(:fount_workshop, "priv/writing_profiles/#{id}.json")
    with {:ok, text} <- File.read(path), {:ok, value} <- Jason.decode(text), do: {:ok, value}
  end

  def profile(_), do: {:error, :unknown_profile}

  @doc "Produces actual typed screenplay edits for the selected profile."
  def propose(%Screenplay{} = base, id, scene_ids, direction, client, opts \\ []) do
    with {:ok, profile} <- profile(id),
         :ok <- validate_scenes(base, scene_ids),
         true <- is_binary(direction) and String.trim(direction) != "" do
      instruction =
        "#{profile["goal"]}\n#{profile["creative_prompt"]}\nWriter direction: #{direction}"

      case id do
        "dialogue_subtext" ->
          rewrite_type(base, scene_ids, :dialogue, instruction, client)

        "action_visual" ->
          rewrite_type(base, scene_ids, :action, instruction, client)

        "custom" ->
          ids = Keyword.get(opts, :element_ids, [])

          if Enum.all?(ids, &(scene_id_for(base, &1) in scene_ids)),
            do: TargetedRewrite.propose(base, ids, instruction, client),
            else: {:error, :target_outside_selection}

        _ ->
          SequenceRebuild.propose(base, scene_ids, instruction, client,
            required_texts: Keyword.get(opts, :required_texts, []),
            target_scene_count: Keyword.get(opts, :target_scene_count)
          )
      end
      |> case do
        {:ok, result} ->
          {:ok, Map.merge(result, %{profile_id: id, profile_version: profile["version"]})}

        error ->
          error
      end
    else
      false -> {:error, :empty_direction}
      error -> error
    end
  end

  @doc "Saves a pass candidate and leaves the accepted draft untouched."
  def run(repo, key, id, scene_ids, direction, client, opts \\ []) do
    with {:ok, base} <- Persistence.load(repo, key),
         {:ok, profile} <- profile(id),
         :ok <- validate_scenes(base, scene_ids),
         {:ok, session} <-
           Persistence.save_session(repo, %{
             screenplay_id: base.id,
             base_revision_id: base.revision.id,
             workflow: "pass",
             status: "running",
             request: %{
               "profile_id" => id,
               "profile_version" => profile["version"],
               "scene_ids" => scene_ids,
               "direction" => direction
             }
           }) do
      case propose(base, id, scene_ids, direction, client, opts) do
        {:ok, proposal} ->
          candidate =
            Map.merge(proposal, %{
              label: "#{id} pass",
              strategy: %{"profile_id" => id, "profile_version" => profile["version"]},
              change_groups: [%{"id" => id, "operations" => proposal.changes.operations}],
              lineage: proposal.changes.lineage,
              provenance: %{
                "completion" => proposal.completion_trace,
                "profile_id" => id,
                "profile_version" => profile["version"]
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

  defp rewrite_type(base, scene_ids, type, instruction, client) do
    selected = MapSet.new(scene_ids)

    ids =
      base.ir.elements
      |> Enum.filter(fn element ->
        scene = Query.scene_for(base, element.id)
        (element.type == type and scene) && MapSet.member?(selected, scene.id)
      end)
      |> Enum.map(& &1.id)

    if ids == [],
      do: {:error, :no_matching_elements},
      else: TargetedRewrite.propose(base, ids, instruction, client)
  end

  defp validate_scenes(base, ids) when is_list(ids) and ids != [] do
    cond do
      length(Enum.uniq(ids)) != length(ids) -> {:error, :duplicate_scene}
      Enum.any?(ids, &(Query.scene(base, &1) == nil)) -> {:error, :unknown_scene}
      true -> :ok
    end
  end

  defp validate_scenes(_, _), do: {:error, :invalid_scene_selection}

  defp scene_id_for(base, id) do
    case Query.scene_for(base, id) do
      nil -> nil
      scene -> scene.id
    end
  end
end
