defmodule FountWeb.SemanticPartitions do
  @moduledoc "Conservative human precedence when reassessment changes a reviewed source partition."

  def reconcile(current, reviewed) do
    {kept, issues} =
      Enum.reduce(current, {[], []}, fn row, {kept, issues} ->
        overlaps =
          if row["assessment_origin"] in ["model", "deterministic_fixture"],
            do: Enum.filter(reviewed, &overlap?(row, &1)),
            else: []

        if overlaps == [] do
          {[row | kept], issues}
        else
          issue = %{
            "reason_code" => "review_partition_conflict",
            "model_handle_id" => row["handle_id"],
            "reviewed_handle_ids" => Enum.map(overlaps, & &1["handle_id"]),
            "literal_element_ids" => literal_ids(row),
            "explanation" =>
              "A new model grouping overlaps an existing human decision. The reviewed interpretation is retained; the new suggestion needs source review."
          }

          {kept, [issue | issues]}
        end
      end)

    {Enum.reverse(kept), Enum.reverse(issues)}
  end

  defp overlap?(left, right), do: not MapSet.disjoint?(anchors(left), anchors(right))

  defp literal_ids(row) do
    (get_in(row, ["payload", "occurrences"]) || [])
    |> Enum.map(&(&1["literal_element_id"] || &1["element_id"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp anchors(row) do
    payload = row["payload"] || %{}

    case payload["support_set"] do
      support when is_list(support) and support != [] ->
        MapSet.new(support, &support_anchor/1)

      _ ->
        if payload["element_id"],
          do: MapSet.new([{:literal, payload["element_id"]}]),
          else: MapSet.new()
    end
  end

  defp support_anchor([_kind, _role, start, finish, literal]) do
    if literal, do: {:literal, literal}, else: {:range, start, finish}
  end
end
