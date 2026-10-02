defmodule Fount.Intelligence.ImportReview do
  @moduledoc "Bounded comparison of source rereading with the initial proposal, without equating agreement with truth."

  def finalize(proposed, reviewed) do
    prior = Map.new(proposed["cue_decisions"], &{&1["literal_element_id"], &1})

    {decisions, unresolved_ids, changes} =
      Enum.reduce(reviewed["cue_decisions"], {[], [], []}, fn row, {kept, unresolved, changes} ->
        old = prior[row["literal_element_id"]]
        changed = old && old["disposition"] != row["disposition"]
        stronger = old && Enum.any?(row["evidence"], &(&1 not in old["evidence"]))

        corrected =
          if changed and not stronger,
            do: %{
              row
              | "disposition" => "unresolved",
                "entity_id" => nil,
                "reason_code" => "ambiguous_role"
            },
            else: row

        unresolved =
          if corrected["disposition"] == "unresolved",
            do: [row["literal_element_id"] | unresolved],
            else: unresolved

        changes =
          if changed,
            do: [
              %{
                "literal_element_id" => row["literal_element_id"],
                "before" => old["disposition"],
                "after" => corrected["disposition"]
              }
              | changes
            ],
            else: changes

        {[corrected | kept], unresolved, changes}
      end)

    occurrences =
      Enum.reject(
        reviewed["occurrences"],
        &(&1["role"] == "speaker" and &1["literal_element_id"] in unresolved_ids)
      )

    reviewed =
      reviewed
      |> Map.put("cue_decisions", Enum.reverse(decisions))
      |> Map.put("occurrences", occurrences)

    diff = %{
      "changed_cues" => length(changes),
      "examples" => Enum.take(Enum.reverse(changes), 20),
      "examples_truncated" => max(length(changes) - 20, 0),
      "added_entities" => count_difference(reviewed["entities"], proposed["entities"]),
      "removed_entities" => count_difference(proposed["entities"], reviewed["entities"]),
      "changed_roles" => changed_roles(proposed, reviewed),
      "changed_partitions" => partition_difference(proposed, reviewed),
      "changed_alias_sets" => alias_difference(proposed, reviewed)
    }

    {reviewed, diff}
  end

  defp partition_difference(proposed, reviewed) do
    old = partitions(proposed)
    new = partitions(reviewed)
    MapSet.size(MapSet.difference(old, new)) + MapSet.size(MapSet.difference(new, old))
  end

  defp partitions(result) do
    result["occurrences"]
    |> Enum.group_by(& &1["entity_id"])
    |> MapSet.new(fn {_id, rows} ->
      rows
      |> Enum.map(&{&1["role"], &1["literal_element_id"], Enum.sort(&1["evidence"])})
      |> Enum.sort()
    end)
  end

  defp alias_difference(proposed, reviewed) do
    old = MapSet.new(proposed["entities"], &alias_signature/1)
    Enum.count(reviewed["entities"], &(not MapSet.member?(old, alias_signature(&1))))
  end

  defp alias_signature(entity) do
    {Enum.sort(entity["evidence"]),
     Enum.map(entity["aliases"], &{&1["label"], &1["relation"]}) |> Enum.sort()}
  end

  defp count_difference(left, right) do
    signatures = MapSet.new(right, &{&1["kind"], &1["label"], Enum.sort(&1["evidence"])})

    Enum.count(
      left,
      &(not MapSet.member?(signatures, {&1["kind"], &1["label"], Enum.sort(&1["evidence"])}))
    )
  end

  defp changed_roles(proposed, reviewed) do
    prior = Map.new(proposed["occurrences"], &{Enum.sort(&1["evidence"]), &1["role"]})

    Enum.count(reviewed["occurrences"], fn row ->
      prior[Enum.sort(row["evidence"])] not in [nil, row["role"]]
    end)
  end
end
