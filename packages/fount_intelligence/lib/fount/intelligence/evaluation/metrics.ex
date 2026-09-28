defmodule Fount.Intelligence.Evaluation.Metrics do
  @moduledoc """
  Distributional evaluation for `noul`, `choice`, and ordinal `score` measurements.

  Subjective labels are converted to empirical reader distributions instead of forcing
  consensus. Metrics intentionally remain separate from writer-usefulness ratings.
  """

  @default_thresholds [0.0, 0.5, 0.7, 0.8, 0.9, 0.95]

  @spec evaluate(String.t() | atom(), [map()], keyword()) :: {:ok, map()} | {:error, atom()}
  def evaluate(kind, cases, opts \\ [])

  def evaluate(kind, cases, opts) when is_list(cases) and cases != [] do
    case to_string(kind) do
      "noul" -> categorical("noul", cases, opts)
      "choice" -> categorical("choice", cases, opts)
      "score" -> ordinal(cases, opts)
      _ -> {:error, :unsupported_evaluation_kind}
    end
  end

  def evaluate(_, _, _), do: {:error, :invalid_evaluation_cases}

  defp categorical(kind, cases, opts) do
    with {:ok, prepared} <- prepare_categorical(cases) do
      brier = mean(prepared, & &1.brier)
      log_loss = mean(prepared, & &1.log_loss)
      calibration = calibration(prepared, Keyword.get(opts, :bins, 10))

      {:ok,
       %{
         "kind" => kind,
         "case_count" => length(prepared),
         "brier_score" => brier,
         "log_loss" => log_loss,
         "expected_calibration_error" => calibration.ece,
         "calibration_bins" => calibration.bins,
         "abstention" =>
           abstention(prepared, Keyword.get(opts, :thresholds, @default_thresholds)),
         "human_disagreement_preserved" => true,
         "metric_notes" => [
           "Human labels are evaluated as empirical distributions, not adjudicated consensus.",
           "Abstention support is reported as coverage plus retained human-label support."
         ]
       }}
    end
  end

  defp ordinal(cases, opts) do
    with {:ok, prepared} <- prepare_ordinal(cases),
         {:ok, categorical_cases} <- ordinal_as_categorical(cases),
         {:ok, categorical} <- categorical("score_distribution", categorical_cases, opts) do
      {:ok,
       categorical
       |> Map.put("kind", "score")
       |> Map.put("ordinal_mean_absolute_error", mean(prepared, & &1.absolute_error))
       |> Map.put(
         "ordinal_root_mean_square_error",
         :math.sqrt(mean(prepared, & &1.squared_error))
       )
       |> Map.put("ordinal_cases", length(prepared))}
    end
  end

  defp prepare_categorical(cases) do
    Enum.reduce_while(cases, {:ok, []}, fn case_data, {:ok, acc} ->
      case categorical_case(case_data) do
        {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
        _ -> {:halt, {:error, :invalid_evaluation_case}}
      end
    end)
  end

  defp categorical_case(%{"distribution" => distribution, "human_labels" => labels} = case_data)
       when is_map(distribution) and is_list(labels) and labels != [] do
    domain = Map.keys(distribution) |> Enum.sort()

    with true <- domain != [] and valid_distribution?(distribution),
         true <- Enum.all?(labels, &(is_binary(&1) and &1 in domain)) do
      human =
        labels
        |> Enum.frequencies()
        |> Map.new(fn {label, count} -> {label, count / length(labels)} end)

      selected = selected(distribution)
      confidence = distribution[selected]
      support = Map.get(human, selected, 0.0)

      brier =
        Enum.sum(Enum.map(domain, &:math.pow(distribution[&1] - Map.get(human, &1, 0.0), 2)))

      log_loss =
        -Enum.sum(
          Enum.map(domain, fn label ->
            Map.get(human, label, 0.0) * :math.log(max(distribution[label], 1.0e-12))
          end)
        )

      {:ok,
       %{
         id: Map.get(case_data, "case_id"),
         confidence: confidence,
         support: support,
         brier: brier,
         log_loss: log_loss
       }}
    else
      _ -> {:error, :invalid_case}
    end
  end

  defp categorical_case(_), do: {:error, :invalid_case}

  defp prepare_ordinal(cases) do
    Enum.reduce_while(cases, {:ok, []}, fn case_data, {:ok, acc} ->
      case ordinal_case(case_data) do
        {:ok, value} -> {:cont, {:ok, acc ++ [value]}}
        error -> {:halt, error}
      end
    end)
  end

  defp ordinal_case(%{"distribution" => distribution, "human_ordinals" => labels})
       when is_map(distribution) and is_list(labels) and labels != [] do
    with {:ok, values} <- ordinal_distribution(distribution),
         true <- Enum.all?(labels, &is_integer/1),
         true <- Enum.all?(labels, fn value -> value in Enum.map(values, &elem(&1, 0)) end) do
      predicted = Enum.sum(Enum.map(values, fn {ordinal, p} -> ordinal * p end))
      actual = Enum.sum(labels) / length(labels)
      error = predicted - actual
      {:ok, %{absolute_error: abs(error), squared_error: error * error}}
    else
      _ -> {:error, :invalid_evaluation_case}
    end
  end

  defp ordinal_case(_), do: {:error, :invalid_evaluation_case}

  defp ordinal_as_categorical(cases) do
    Enum.reduce_while(cases, {:ok, []}, fn
      %{"distribution" => distribution, "human_ordinals" => labels} = case_data, {:ok, acc} ->
        converted =
          case_data
          |> Map.delete("human_ordinals")
          |> Map.put(
            "distribution",
            Map.new(distribution, fn {key, value} -> {to_string(key), value} end)
          )
          |> Map.put("human_labels", Enum.map(labels, &to_string/1))

        {:cont, {:ok, acc ++ [converted]}}

      _, _ ->
        {:halt, {:error, :invalid_evaluation_case}}
    end)
  end

  defp ordinal_distribution(distribution) do
    values =
      Enum.map(distribution, fn {key, probability} ->
        case Integer.parse(to_string(key)) do
          {ordinal, ""} -> {ordinal, probability}
          _ -> {:invalid, probability}
        end
      end)

    probabilities = Enum.map(values, &elem(&1, 1))

    valid =
      values != [] and
        Enum.all?(values, fn {ordinal, probability} ->
          is_integer(ordinal) and is_number(probability) and probability >= 0 and probability <= 1
        end) and abs(Enum.sum(probabilities) - 1.0) <= 0.020000000001

    if valid, do: {:ok, Enum.sort(values)}, else: {:error, :invalid_ordinal_distribution}
  end

  defp calibration(cases, bins) when is_integer(bins) and bins in 2..100 do
    grouped =
      cases
      |> Enum.group_by(fn item -> min(trunc(item.confidence * bins), bins - 1) end)
      |> Enum.sort_by(&elem(&1, 0))

    rows =
      Enum.map(grouped, fn {index, items} ->
        confidence = mean(items, & &1.confidence)
        support = mean(items, & &1.support)

        %{
          "bin" => index,
          "lower" => index / bins,
          "upper" => (index + 1) / bins,
          "count" => length(items),
          "mean_confidence" => confidence,
          "mean_human_support" => support,
          "absolute_gap" => abs(confidence - support)
        }
      end)

    ece = Enum.sum(Enum.map(rows, &(&1["absolute_gap"] * &1["count"] / length(cases))))
    %{ece: ece, bins: rows}
  end

  defp calibration(cases, _), do: calibration(cases, 10)

  defp abstention(cases, thresholds) when is_list(thresholds) do
    thresholds
    |> Enum.filter(&(is_number(&1) and &1 >= 0 and &1 <= 1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn threshold ->
      retained = Enum.filter(cases, &(&1.confidence >= threshold))

      %{
        "threshold" => threshold,
        "retained" => length(retained),
        "coverage" => length(retained) / length(cases),
        "mean_human_support" => if(retained == [], do: nil, else: mean(retained, & &1.support))
      }
    end)
  end

  defp selected(distribution) do
    distribution
    |> Enum.sort_by(fn {label, probability} -> {-probability, label} end)
    |> hd()
    |> elem(0)
  end

  defp valid_distribution?(distribution)
       when is_map(distribution) and map_size(distribution) >= 2 do
    values = Map.values(distribution)

    Enum.all?(Map.keys(distribution), &is_binary/1) and
      Enum.all?(values, &(is_number(&1) and &1 >= 0 and &1 <= 1)) and
      abs(Enum.sum(values) - 1.0) <= 0.020000000001
  end

  defp valid_distribution?(_), do: false
  defp mean(values, fun), do: Enum.sum(Enum.map(values, fun)) / length(values)
end
