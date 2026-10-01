defmodule FountWeb.CandidateWorkspace do
  @moduledoc false

  @max_related 24
  @max_groups 96
  @max_combine_sources 4

  def related(repo, progress) when is_map(progress) do
    services = services(repo)

    progress
    |> session_ids()
    |> Enum.flat_map(&session_candidates(services, &1))
    |> Enum.uniq_by(& &1["id"])
    |> Enum.reverse()
    |> Enum.take(@max_related)
    |> Enum.map(&present_candidate/1)
  end

  def related(_, _), do: []

  def audition(repo, run, progress, candidate_id)
      when is_map(run) and is_map(progress) and is_binary(candidate_id) do
    with true <-
           candidate_allowed?(repo, progress, candidate_id) or {:error, :candidate_not_in_task},
         selection when is_map(selection) <- get_in(run, ["plan", "scope"]),
         root <- Application.fetch_env!(:fount_web, :artifact_root),
         output <- Path.join([root, "runs", run["id"], "auditions"]),
         {:ok, result} <-
           FountWorkshop.Audition.build(candidate_id, selection, services(repo),
             output_dir: output
           ),
         {:ok, source} <- File.read(result["fountain"]) do
      {:ok,
       %{
         "candidate_id" => candidate_id,
         "scene_ids" => result["scene_ids"],
         "source_revision_id" => result["source_revision_id"],
         "fountain" => source
       }}
    else
      false -> {:error, :candidate_not_in_task}
      nil -> {:error, :task_scope_unavailable}
      {:error, _} = error -> error
    end
  end

  def select_groups(repo, progress, candidate_id, group_ids)
      when is_map(progress) and is_binary(candidate_id) and is_list(group_ids) do
    group_ids = group_ids |> Enum.uniq() |> Enum.take(@max_groups)

    with true <-
           candidate_allowed?(repo, progress, candidate_id) or {:error, :candidate_not_in_task},
         true <- group_ids != [] or {:error, :change_group_required},
         {:ok, candidate} <-
           FountWorkshop.CandidateAPI.select(candidate_id, group_ids, services(repo),
             label: "Writer-selected changes"
           ) do
      {:ok, candidate}
    else
      false -> {:error, :candidate_not_in_task}
      {:error, _} = error -> error
    end
  end

  def combine(repo, progress, picks) when is_map(progress) and is_list(picks) do
    picks =
      picks
      |> Enum.take(@max_combine_sources)
      |> Enum.map(fn pick ->
        %{
          "candidate_id" => pick["candidate_id"],
          "group_ids" => List.wrap(pick["group_ids"]) |> Enum.uniq() |> Enum.take(@max_groups)
        }
      end)
      |> Enum.filter(&(is_binary(&1["candidate_id"]) and &1["group_ids"] != []))

    ids = Enum.map(picks, & &1["candidate_id"])

    with true <- length(picks) >= 2 or {:error, :combination_requires_two_sources},
         true <- Enum.uniq(ids) == ids or {:error, :duplicate_combination_source},
         true <-
           Enum.all?(ids, &candidate_allowed?(repo, progress, &1)) or
             {:error, :candidate_not_in_task},
         {:ok, candidate} <-
           FountWorkshop.CandidateAPI.combine(
             ids,
             %{"picks" => picks, "label" => "Writer-selected combination", "join" => nil},
             services(repo)
           ) do
      {:ok, candidate}
    else
      false -> {:error, :candidate_not_in_task}
      {:error, _} = error -> error
    end
  end

  def present_candidate(candidate) when is_map(candidate) do
    groups =
      candidate["change_groups"] ||
        get_in(candidate, ["provenance", "proposal", "groups"]) || []

    %{
      "id" => candidate["id"],
      "session_id" => candidate["session_id"],
      "base_revision_id" => candidate["base_revision_id"],
      "result_revision_id" => candidate["result_revision_id"],
      "label" =>
        get_in(candidate, ["provenance", "label"]) ||
          get_in(candidate, ["provenance", "proposal", "summary"]) || "Proposed writing",
      "groups" =>
        groups
        |> Enum.take(@max_groups)
        |> Enum.map(fn group ->
          %{
            "id" => group["id"],
            "title" => group["title"] || "Change",
            "reason" => group["reason"] || "Saved proposed change"
          }
        end),
      "fountain" => Fount.Screenplay.to_fountain(candidate["screenplay"], mode: :spec)
    }
  end

  defp candidate_allowed?(repo, progress, candidate_id) do
    progress
    |> session_ids()
    |> Enum.flat_map(&session_candidates(services(repo), &1))
    |> Enum.any?(&(&1["id"] == candidate_id))
  end

  defp session_ids(progress) do
    progress
    |> Map.get("steps", [])
    |> Enum.flat_map(fn step ->
      [step["session_id"], get_in(step, ["result", "session_id"])]
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp session_candidates(services, session_id) do
    case FountWorkshop.Store.call(services[:store], :candidates_for_session, [session_id]) do
      candidates when is_list(candidates) -> candidates
      _ -> []
    end
  end

  defp services(repo), do: %{store: FountWorkshop.Store.new(repo)}
end
