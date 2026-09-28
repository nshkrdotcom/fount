defmodule FountWorkshop.Comparison do
  @moduledoc "Deterministic original-versus-candidate page comparison; generator self-description is never treated as proof."

  alias Fount.Screenplay
  alias FountWorkshop.Store

  @language_types ~w(character dialogue parenthetical lyric)

  @doc "Loads a saved candidate and compares the actual candidate screenplay with its immutable base revision."
  def candidate(id, services) when is_binary(id) do
    with {:ok, candidate} <- Store.call(services[:store], :candidate, [id]),
         {:ok, base} <-
           Store.call(services[:store], :load_revision, [
             candidate["screenplay_id"],
             candidate["base_revision_id"]
           ]) do
      {:ok, compare(base, candidate)}
    end
  end

  @doc "Compares actual typed elements by stable identity and reports changed action/language separately."
  def compare(%Screenplay{} = base, %{"screenplay" => %Screenplay{} = result} = candidate) do
    diff = Screenplay.diff(base, result)
    changes = element_changes(base, result, diff.elements)
    checks = get_in(candidate, ["provenance", "checks"]) || []

    %{
      "base_revision_id" => base.revision.id,
      "candidate_id" => candidate["id"],
      "candidate_revision_id" => result.revision.id,
      "actual_changes" => changes,
      "action_changes" => Enum.filter(changes, &action_change?/1),
      "language_changes" => Enum.filter(changes, &language_change?/1),
      "transition_changes" => Enum.filter(changes, &transition_change?/1),
      "dialogue_delta" => dialogue_delta(changes),
      "moved_scene_ids" => diff.scenes.moved,
      "protected_text_checks" => Enum.filter(checks, &(&1["kind"] == "pin_text")),
      "generator_claim" => %{
        "proposal_summary" => get_in(candidate, ["provenance", "proposal", "summary"]),
        "strategy" => candidate["strategy"]
      },
      "generator_claim_is_evidence" => false,
      "human_review" => %{
        "required_for" => [
          "voice fit",
          "language authenticity",
          "dramatic preference",
          "whether the original is stronger"
        ],
        "automatic_winner" => false
      }
    }
  end

  def compare(_, _), do: {:error, :invalid_candidate_comparison}

  defp element_changes(base, result, diff) do
    base_by_id = Map.new(base.ir.elements, &{&1.id, &1})
    result_by_id = Map.new(result.ir.elements, &{&1.id, &1})

    ids =
      result.ir.elements
      |> Enum.map(& &1.id)
      |> Kernel.++(Enum.filter(Enum.map(base.ir.elements, & &1.id), &(&1 in diff.removed)))
      |> Enum.uniq()

    changed = MapSet.new(diff.added ++ diff.removed ++ diff.changed)

    ids
    |> Enum.filter(&MapSet.member?(changed, &1))
    |> Enum.map(fn id -> change(base, result, base_by_id[id], result_by_id[id], id) end)
  end

  defp change(base, result, before, after_value, id) do
    kind =
      cond do
        is_nil(before) -> "added"
        is_nil(after_value) -> "removed"
        true -> "modified"
      end

    %{
      "id" => id,
      "kind" => kind,
      "before_type" => type(before),
      "after_type" => type(after_value),
      "before" => text(before),
      "after" => text(after_value),
      "before_scene_id" => scene_id(base, id),
      "after_scene_id" => scene_id(result, id)
    }
  end

  defp action_change?(change), do: "action" in element_types(change)
  defp transition_change?(change), do: "transition" in element_types(change)
  defp language_change?(change), do: Enum.any?(element_types(change), &(&1 in @language_types))

  defp dialogue_delta(changes) do
    language = Enum.filter(changes, &language_change?/1)

    %{
      "added" => Enum.count(language, &(&1["kind"] == "added")),
      "removed" => Enum.count(language, &(&1["kind"] == "removed")),
      "modified" => Enum.count(language, &(&1["kind"] == "modified"))
    }
  end

  defp element_types(change) do
    [change["before_type"], change["after_type"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp type(nil), do: nil
  defp type(value), do: Atom.to_string(value.type)
  defp text(nil), do: nil
  defp text(value), do: value.text

  defp scene_id(model, id) do
    case Fount.Query.scene_for(model, id) do
      nil -> nil
      scene -> scene.id
    end
  end
end
