defmodule Fount.Intelligence.Evaluation.Resources do
  @moduledoc "Longitudinal preflight-versus-actual calibration. Unknown resource dimensions stay unknown."

  @pairs [
    {"provider_requests_before_retries_estimate", "provider_requests", "provider_requests"},
    {"reuse_estimate", "cache_hits", "reuse"},
    {"hosted_cost", "hosted_cost", "hosted_cost"}
  ]

  @spec compare(map(), map()) :: {:ok, map()} | {:error, atom()}
  def compare(estimate, actual) when is_map(estimate) and is_map(actual) do
    rows =
      Enum.map(@pairs, fn {estimate_key, actual_key, name} ->
        comparison(name, estimate[estimate_key], actual[actual_key], actual)
      end)

    {:ok,
     %{
       "dimensions" => rows,
       "known_dimensions" => Enum.count(rows, &(&1["absolute_error"] != nil)),
       "unknown_dimensions" => Enum.count(rows, &(&1["absolute_error"] == nil)),
       "policy" => "unknown_is_nil_never_zero"
     }}
  end

  def compare(_, _), do: {:error, :invalid_resource_comparison}

  @spec compare_writer_packet(map()) :: {:ok, map()} | {:error, atom()}
  def compare_writer_packet(%{"preflight" => %{"estimate" => estimate}, "actual" => actual})
      when is_map(estimate) and is_map(actual) do
    base = stage_actual(actual["base"])
    contextual = stage_actual(actual["contextual"])

    flattened = %{
      "provider_requests" => add_known(base["provider_requests"], contextual["provider_requests"]),
      "cache_hits" => add_known(base["cache_hits"], contextual["cache_hits"]),
      "scheduled_states" => add_known(base["scheduled_states"], contextual["scheduled_states"]),
      "hosted_cost" => actual["hosted_cost"]
    }

    compare(estimate, flattened)
  end

  def compare_writer_packet(_), do: {:error, :invalid_writer_resource_usage}

  @spec summarize_history([map()]) :: {:ok, map()} | {:error, atom()}
  def summarize_history(history) when is_list(history) do
    usages =
      history
      |> Enum.map(&Map.get(&1, "resource_usage"))
      |> Enum.filter(&is_map/1)

    packet_comparisons =
      usages
      |> Enum.map(&compare_writer_packet/1)
      |> Enum.flat_map(fn
        {:ok, report} -> [report]
        _ -> []
      end)

    {:ok,
     %{
       "run_count" => length(history),
       "runs_with_usage" => length(usages),
       "runs_with_estimate_actual_comparison" => length(packet_comparisons),
       "provider_requests" => nested_numeric_summary(usages, "provider_requests"),
       "cache_hits" => nested_numeric_summary(usages, "cache_hits"),
       "successful_states" => nested_numeric_summary(usages, "successful_states"),
       "hosted_cost" => nested_numeric_summary(usages, "hosted_cost"),
       "estimate_actual_comparisons" => packet_comparisons,
       "raw_resource_history" => history
     }}
  end

  def summarize_history(_), do: {:error, :invalid_resource_history}

  defp comparison("reuse", estimate, actual, actual_map) do
    estimated_ratio = if is_number(estimate) and estimate >= 0 and estimate <= 1, do: estimate, else: nil
    scheduled = actual_map["scheduled_states"]
    actual_ratio =
      if is_integer(actual) and actual >= 0 and is_integer(scheduled) and scheduled > 0,
        do: actual / scheduled,
        else: nil

    numeric_comparison("reuse", estimated_ratio, actual_ratio)
  end

  defp comparison(name, estimate, actual, _actual_map), do: numeric_comparison(name, estimate, actual)

  defp numeric_comparison(name, estimate, actual) do
    if is_number(estimate) and is_number(actual) do
      %{
        "dimension" => name,
        "estimated" => estimate,
        "actual" => actual,
        "absolute_error" => abs(actual - estimate),
        "signed_error" => actual - estimate,
        "relative_error" => if(actual == 0, do: nil, else: (actual - estimate) / actual)
      }
    else
      %{
        "dimension" => name,
        "estimated" => estimate,
        "actual" => actual,
        "absolute_error" => nil,
        "signed_error" => nil,
        "relative_error" => nil
      }
    end
  end

  defp stage_actual(%{"actual" => actual}) when is_map(actual), do: actual
  defp stage_actual(_), do: %{}

  defp add_known(left, right) when is_number(left) and is_number(right), do: left + right
  defp add_known(0, nil), do: nil
  defp add_known(nil, 0), do: nil
  defp add_known(_left, _right), do: nil

  defp nested_numeric_summary(usages, "hosted_cost") do
    values =
      usages
      |> Enum.map(&get_in(&1, ["actual", "hosted_cost"]))
      |> Enum.filter(&is_number/1)

    numeric_values(values)
  end

  defp nested_numeric_summary(usages, key) do
    values =
      usages
      |> Enum.map(fn usage ->
        base = get_in(usage, ["actual", "base", "actual", key])
        contextual = get_in(usage, ["actual", "contextual", "actual", key])
        add_known(base, contextual)
      end)
      |> Enum.filter(&is_number/1)

    numeric_values(values)
  end

  defp numeric_values([]), do: nil
  defp numeric_values(values),
    do: %{
      "count" => length(values),
      "mean" => Enum.sum(values) / length(values),
      "min" => Enum.min(values),
      "max" => Enum.max(values)
    }

end
