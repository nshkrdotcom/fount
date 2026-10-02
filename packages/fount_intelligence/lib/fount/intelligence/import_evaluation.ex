defmodule Fount.Intelligence.ImportEvaluation do
  @moduledoc "Offline evaluation against independently annotated byte ranges; never dispatches inference."
  alias Fount.Intelligence.ImportIdentity

  def evaluate(result, gold) do
    if result["binding"]["render_sha256"] == gold["visible_source_sha256"] do
      {:ok, score(result, gold)}
    else
      {:error, :gold_source_mismatch}
    end
  rescue
    _error in [KeyError, ArgumentError] -> {:error, :invalid_evaluation_evidence}
  end

  def verify_source(result, source) do
    evidence = Enum.flat_map(result["occurrences"], & &1["evidence"])

    valid =
      Enum.all?(evidence, fn row ->
        absolute = ImportIdentity.absolute_evidence(row, result["span_bindings"])
        start = absolute["byte_start"]
        finish = absolute["byte_end"]

        start >= 0 and finish > start and finish <= byte_size(source) and
          binary_part(source, start, finish - start) == absolute["quote"]
      end)

    if valid and Fount.ID.hash(source) == result["binding"]["render_sha256"],
      do: :ok,
      else: {:error, :evaluation_source_mismatch}
  rescue
    _error in [KeyError, ArgumentError] -> {:error, :invalid_evaluation_evidence}
  end

  defp score(result, gold) do
    occurrences = result["occurrences"]
    expected = gold["occurrences"]

    pairs =
      for actual <- occurrences,
          truth <- expected,
          matches?(actual, truth, result["span_bindings"]),
          do: {truth["entity_id"], actual["entity_id"]}

    expected_people =
      gold["entities"] |> Enum.filter(&(&1["kind"] == "character")) |> MapSet.new(& &1["id"])

    actual_people =
      result["entities"]
      |> Enum.filter(&(&1["kind"] == "character"))
      |> MapSet.new(& &1["local_id"])

    person_pairs =
      Enum.filter(pairs, fn {truth, actual} ->
        MapSet.member?(expected_people, truth) and MapSet.member?(actual_people, actual)
      end)

    hit_expected = MapSet.new(person_pairs, &elem(&1, 0))
    hit_actual = MapSet.new(person_pairs, &elem(&1, 1))

    matched = match_occurrences(occurrences, expected, result["span_bindings"])
    missed = length(expected) - length(matched)
    extra = length(occurrences) - length(matched)
    roles = Enum.map(expected ++ occurrences, & &1["role"]) |> Enum.uniq()

    role_metrics =
      Map.new(roles, fn role ->
        wanted = Enum.count(expected, &(&1["role"] == role))
        predicted = Enum.count(occurrences, &(&1["role"] == role))
        hits = Enum.count(matched, fn {_actual, truth} -> truth["role"] == role end)

        {role,
         %{
           "precision" => ratio(hits, predicted),
           "recall" => ratio(hits, wanted),
           "missing" => wanted - hits,
           "extra" => predicted - hits
         }}
      end)

    %{
      "expected_people" => MapSet.size(expected_people),
      "predicted_people" => MapSet.size(actual_people),
      "false_people" => MapSet.size(MapSet.difference(actual_people, hit_actual)),
      "missing_people" => MapSet.size(MapSet.difference(expected_people, hit_expected)),
      "entity_precision" => ratio(MapSet.size(hit_actual), MapSet.size(actual_people)),
      "entity_recall" => ratio(MapSet.size(hit_expected), MapSet.size(expected_people)),
      "missing_occurrences" => missed,
      "extra_occurrences" => extra,
      "occurrence_precision" => ratio(length(occurrences) - extra, length(occurrences)),
      "occurrence_recall" => ratio(length(expected) - missed, length(expected)),
      "false_merges" => partition_errors(person_pairs, 1, 0),
      "false_splits" => partition_errors(person_pairs, 0, 1),
      "unresolved" => length(result["unresolved"] || []),
      "roles" => role_metrics,
      "coverage" => result["coverage"],
      "mode" => "offline_supplied_result"
    }
  end

  defp match_occurrences(actual, expected, spans) do
    candidates =
      actual
      |> Enum.with_index()
      |> Map.new(fn {row, index} ->
        {index,
         expected
         |> Enum.with_index()
         |> Enum.filter(fn {truth, _} -> matches?(row, truth, spans) end)
         |> Enum.map(&elem(&1, 1))}
      end)

    matching =
      Enum.reduce(Map.keys(candidates) |> Enum.sort(), %{}, fn index, matching ->
        case augment(index, candidates, matching, %{}) do
          {:ok, next} -> next
          :unmatched -> matching
        end
      end)

    Enum.map(matching, fn {truth, index} -> {Enum.at(actual, index), Enum.at(expected, truth)} end)
  end

  defp augment(index, candidates, matching, visited) do
    Enum.reduce_while(candidates[index], :unmatched, fn truth, _ ->
      case assign_candidate(index, truth, candidates, matching, visited) do
        {:ok, next} -> {:halt, {:ok, next}}
        :unmatched -> {:cont, :unmatched}
      end
    end)
  end

  defp assign_candidate(index, truth, candidates, matching, visited) do
    cond do
      Map.has_key?(visited, truth) ->
        :unmatched

      not Map.has_key?(matching, truth) ->
        {:ok, Map.put(matching, truth, index)}

      true ->
        case augment(matching[truth], candidates, matching, Map.put(visited, truth, true)) do
          {:ok, next} -> {:ok, Map.put(next, truth, index)}
          :unmatched -> :unmatched
        end
    end
  end

  defp matches?(actual, truth, spans) do
    actual["role"] == truth["role"] and
      Enum.any?(actual["evidence"], fn row ->
        absolute = ImportIdentity.absolute_evidence(row, spans)
        absolute["byte_start"] < truth["byte_end"] and absolute["byte_end"] > truth["byte_start"]
      end)
  end

  defp partition_errors(pairs, grouping, value) do
    pairs
    |> Enum.group_by(&elem(&1, grouping), &elem(&1, value))
    |> Enum.reduce(0, fn {_id, members}, total ->
      total + max(length(Enum.uniq(members)) - 1, 0)
    end)
  end

  defp ratio(_numerator, 0), do: 0.0
  defp ratio(numerator, denominator), do: numerator / denominator
end
