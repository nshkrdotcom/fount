defmodule FountWorkshop.ConsequenceReview do
  @moduledoc """
  Deterministic consequence review for an actual candidate branch.

  The review separates changed pages from declared downstream dependencies and
  hypotheses. It does not convert a strategy or model claim into evidence and it
  reports local-scope spillover instead of silently broadening the rewrite.
  """

  alias Fount.Query
  alias Fount.Screenplay

  @scopes ~w(local sequence whole_draft)

  @doc "Compares actual pages and renders the Phase-14 consequence plan saved in candidate lineage."
  def build(%Screenplay{} = base, %{"screenplay" => %Screenplay{} = result} = candidate) do
    phase14 = get_in(candidate, ["provenance", "intelligence_lineage", "phase14"]) || %{}
    changed = changed_scene_ids(base, result)

    if map_size(phase14) == 0 do
      %{
        "status" => "not_declared",
        "baseline_revision_id" => base.revision.id,
        "candidate_revision_id" => result.revision.id,
        "changed_scene_ids" => changed,
        "candidate_claims_are_evidence" => false
      }
    else
      plan = phase14["consequence_plan"] || %{}
      scope = if phase14["scope"] in @scopes, do: phase14["scope"], else: "local"
      approved = MapSet.new(phase14["approved_scene_ids"] || [])
      unrelated = Enum.reject(changed, &MapSet.member?(approved, &1))

      %{
        "status" => "declared",
        "baseline_revision_id" => base.revision.id,
        "candidate_revision_id" => result.revision.id,
        "scope" => scope,
        "changed_scene_ids" => changed,
        "approved_scene_ids" => MapSet.to_list(approved),
        "unrelated_rewritten_scene_ids" => unrelated,
        "local_scope_respected" => scope != "local" or unrelated == [],
        "preserved" => phase14["preserved"] || [],
        "supported_dependencies" => Map.get(plan, "supported", []),
        "uncertain_consequences" => Map.get(plan, "uncertain", []),
        "unresolved_downstream_work" => Map.get(plan, "unresolved", []),
        "coverage" => %{
          "checked_scene_ids" => Map.get(plan, "checked_scene_ids", []),
          "not_analyzed_scene_ids" => Map.get(plan, "not_analyzed_scene_ids", [])
        },
        "candidate_claims_are_evidence" => false,
        "automatic_scope_expansion" => false
      }
    end
  end

  def build(_, _), do: %{"status" => "unavailable", "reason" => "invalid_candidate"}

  defp changed_scene_ids(base, result) do
    diff = Screenplay.diff(base, result)
    before = Map.new(base.ir.elements, &{&1.id, &1})
    after_map = Map.new(result.ir.elements, &{&1.id, &1})

    ids = Enum.uniq(diff.elements.added ++ diff.elements.removed ++ diff.elements.changed)

    element_scenes =
      ids
      |> Enum.flat_map(fn id ->
        [
          scene_id(base, before[id] && before[id].id),
          scene_id(result, after_map[id] && after_map[id].id)
        ]
      end)
      |> Enum.reject(&is_nil/1)

    Enum.uniq(
      diff.scenes.moved ++
        diff.scenes.added ++ diff.scenes.removed ++ diff.scenes.changed ++ element_scenes
    )
  end

  defp scene_id(_model, nil), do: nil

  defp scene_id(model, id) do
    case Query.scene_for(model, id) do
      nil -> nil
      scene -> scene.id
    end
  end
end
