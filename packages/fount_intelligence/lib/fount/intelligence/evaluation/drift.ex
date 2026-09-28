defmodule Fount.Intelligence.Evaluation.Drift do
  @moduledoc "Distribution drift comparison without declaring one provider/model better."

  @identity_fields ~w(provider model stability lens_sha256 projection_sha256 output_contract_sha256)

  @spec compare([map()], [map()]) :: {:ok, map()} | {:error, atom()}
  def compare(baseline, current) when is_list(baseline) and is_list(current) do
    with {:ok, left} <- index(baseline),
         {:ok, right} <- index(current) do
      ids = Map.keys(left) |> Enum.filter(&Map.has_key?(right, &1)) |> Enum.sort()

      rows = Enum.map(ids, &compare_case(&1, left[&1], right[&1]))

      {:ok,
       %{
         "matched_cases" => length(rows),
         "missing_from_current" => Map.keys(left) -- Map.keys(right) |> Enum.sort(),
         "new_in_current" => Map.keys(right) -- Map.keys(left) |> Enum.sort(),
         "changed_selection_count" => Enum.count(rows, & &1["selection_changed"]),
         "mean_l1_distance" => if(rows == [], do: nil, else: mean(rows, "l1_distance")),
         "max_l1_distance" => if(rows == [], do: nil, else: Enum.max(Enum.map(rows, & &1["l1_distance"]))),
         "cases" => rows,
         "interpretation" => "descriptive_drift_only_not_quality_ranking"
       }}
    end
  end

  def compare(_, _), do: {:error, :invalid_drift_input}

  defp index(cases) do
    Enum.reduce_while(cases, {:ok, %{}}, fn
      %{"case_id" => id, "distribution" => distribution} = item, {:ok, acc}
      when is_binary(id) and id != "" and is_map(distribution) ->
        if Map.has_key?(acc, id) or not valid_distribution?(distribution),
          do: {:halt, {:error, :invalid_drift_case}},
          else: {:cont, {:ok, Map.put(acc, id, item)}}

      _, _ ->
        {:halt, {:error, :invalid_drift_case}}
    end)
  end

  defp compare_case(id, left, right) do
    labels = (Map.keys(left["distribution"]) ++ Map.keys(right["distribution"])) |> Enum.uniq() |> Enum.sort()

    l1 =
      Enum.sum(
        Enum.map(labels, fn label ->
          abs(Map.get(left["distribution"], label, 0.0) - Map.get(right["distribution"], label, 0.0))
        end)
      )

    %{
      "case_id" => id,
      "l1_distance" => l1,
      "baseline_selection" => selected(left["distribution"]),
      "current_selection" => selected(right["distribution"]),
      "selection_changed" => selected(left["distribution"]) != selected(right["distribution"]),
      "identity_changes" =>
        Enum.reduce(@identity_fields, %{}, fn key, acc ->
          before = get_in(left, ["identity", key])
          after_value = get_in(right, ["identity", key])
          if before == after_value, do: acc, else: Map.put(acc, key, %{"before" => before, "after" => after_value})
        end)
    }
  end

  defp selected(distribution) do
    distribution |> Enum.sort_by(fn {label, p} -> {-p, label} end) |> hd() |> elem(0)
  end

  defp valid_distribution?(distribution) do
    values = Map.values(distribution)
    map_size(distribution) >= 2 and Enum.all?(Map.keys(distribution), &is_binary/1) and
      Enum.all?(values, &(is_number(&1) and &1 >= 0 and &1 <= 1)) and
      abs(Enum.sum(values) - 1.0) <= 0.020000000001
  end

  defp mean(rows, key), do: Enum.sum(Enum.map(rows, & &1[key])) / length(rows)
end
