defmodule FountWeb.ProjectContext do
  @moduledoc "Owner-bound, run-independent screenplay workspace loading for the project experience."

  alias FountWeb.{Authoring, AuthoringStore, ScreenplayIndex, SemanticContext, Store}

  @source_tokens ~w(current working proposed)

  def load(owner, project_key, opts \\ [])
      when is_binary(owner) and is_binary(project_key) and is_list(opts) do
    requested = Keyword.get(opts, :source, "current")

    with {:ok, project} <- Store.project_by_key(Fount.Repo, owner, project_key),
         {:ok, current} <- Fount.Persistence.load(Fount.Repo, project["key"]),
         true <- current.id == project["screenplay_id"] do
      sources = sources(owner, project, current)
      selected = Enum.find(sources, &(&1.token == requested)) || hd(sources)

      {:ok,
       %{
         project: project,
         current: current,
         selected: selected,
         sources: sources,
         index: ScreenplayIndex.build(selected.screenplay),
         facts: ScreenplayIndex.facts(selected.screenplay),
         semantic: semantic_context(owner, project, current, selected)
       }}
    else
      false -> {:error, :project_screenplay_mismatch}
      {:error, _} = error -> error
    end
  end

  def card(owner, project) when is_binary(owner) and is_map(project) do
    case load(owner, project["key"]) do
      {:ok, context} ->
        %{
          project: project,
          scene_count: context.facts.scene_count,
          cast_count: context.facts.confirmed_cast_count,
          source_label: context.selected.label
        }

      _ ->
        %{project: project, scene_count: nil, cast_count: nil, source_label: "Current draft"}
    end
  end

  def remember(owner, project_key, view, extra \\ %{})
      when is_binary(owner) and is_binary(project_key) and is_binary(view) and is_map(extra) do
    Store.put_owner_preferences(
      Fount.Repo,
      owner,
      Map.merge(%{"last_project_key" => project_key, "last_view" => view}, extra)
    )
  end

  def source_token(token) when token in @source_tokens, do: token
  def source_token(_), do: "current"

  defp sources(owner, project, current) do
    [
      %{
        token: "current",
        label: current_source_label(project),
        kind: :current,
        screenplay: current
      }
    ]
    |> maybe_working(owner, project)
    |> maybe_proposed(owner, project)
  end

  defp semantic_context(owner, project, current, %{kind: :current}) do
    case SemanticContext.load(Fount.Repo, owner, project, current) do
      {:ok, semantic} -> semantic
      {:error, reason} -> %{error: reason, assessment_state: :unavailable}
    end
  end

  defp semantic_context(_owner, _project, current, selected) do
    %{
      assessment_state: :source_not_persisted,
      error: :semantic_review_current_source_only,
      revision_id: current.revision.id,
      selected_revision_id: selected.screenplay.revision.id,
      characters: [],
      locations: [],
      canonical_cast: [],
      review_history: [],
      version: 0
    }
  end

  defp current_source_label(%{"project_kind" => "example"}), do: "Original example"
  defp current_source_label(_), do: "Current draft"

  defp maybe_working(sources, owner, project) do
    with {:ok, draft} <- AuthoringStore.current(Fount.Repo, owner, project["id"]),
         {:ok, base} <-
           Fount.Persistence.load_revision(
             Fount.Repo,
             draft["screenplay_id"],
             draft["base_revision_id"]
           ),
         {:ok, preview} <-
           Authoring.preview(base, draft["raw_source"],
             prior_source: draft["last_valid_source"],
             identity_anchors: draft["identity_anchors"] || []
           ) do
      sources ++
        [
          %{
            token: "working",
            label: "Working draft",
            kind: :working,
            screenplay: preview.screenplay,
            draft: draft,
            valid?: preview.valid?
          }
        ]
    else
      _ -> sources
    end
  end

  defp maybe_proposed(sources, owner, project) do
    with {:ok, draft} <- AuthoringStore.current(Fount.Repo, owner, project["id"]),
         candidate_id when is_binary(candidate_id) <- draft["saved_candidate_id"],
         true <- draft["saved_candidate_version"] == draft["version"],
         {:ok, candidate} <- Fount.Persistence.candidate(Fount.Repo, candidate_id),
         true <- candidate["screenplay_id"] == project["screenplay_id"],
         true <- candidate["base_revision_id"] == draft["base_revision_id"] do
      sources ++
        [
          %{
            token: "proposed",
            label: "Proposed change",
            kind: :proposed,
            screenplay: candidate["screenplay"],
            candidate: candidate
          }
        ]
    else
      _ -> sources
    end
  end
end
