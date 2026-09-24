defmodule FountProbe.Writing.DecisionPolicy do
  @moduledoc """
  Interprets typed probability distributions without inventing confidence.

  Thresholds are review defaults, not claims of calibration or artistic quality.
  Unavailable values remain unavailable and never enter a denominator as zero.
  """

  def noul(p, opts \\ []) do
    with :ok <- probability(p) do
      supported = Keyword.get(opts, :supported, 0.8)
      unsupported = Keyword.get(opts, :unsupported, 0.2)
      complete? = Keyword.get(opts, :complete_context, true)

      status =
        cond do
          p >= supported -> "supported"
          p <= unsupported and complete? -> "not_supported"
          p <= unsupported -> "insufficient_evidence"
          true -> "uncertain"
        end

      {:ok, %{"probability" => p, "status" => status}}
    end
  end

  def semantic_noul(p, expected, opts \\ [])

  def semantic_noul(p, expected, opts) when is_boolean(expected) do
    with :ok <- probability(p) do
      mass = if expected, do: p, else: 1 - p
      {:ok, %{"probability" => p, "allowed_mass" => mass, "status" => mass_status(mass, opts)}}
    end
  end

  def semantic_noul(_, _, _), do: {:error, :invalid_expectation}

  def semantic_distribution(distribution, allowed, confidence, opts \\ [])

  def semantic_distribution(distribution, allowed, confidence, opts)
      when is_map(distribution) and is_list(allowed) do
    with :ok <- distribution(distribution),
         :ok <- probability(confidence),
         :ok <- allowed_keys(distribution, allowed) do
      mass = Enum.reduce(Enum.uniq(allowed), 0.0, &(&2 + Map.fetch!(distribution, &1)))
      minimum = Keyword.get(opts, :minimum_confidence, 0.7)

      {:ok,
       %{
         "probabilities" => distribution,
         "confidence" => confidence,
         "allowed_mass" => mass,
         "status" => if(confidence < minimum, do: "uncertain", else: mass_status(mass, opts))
       }}
    end
  end

  def semantic_distribution(_, _, _, _), do: {:error, :invalid_distribution}

  def choice(distribution, order, confidence, opts \\ []) do
    with :ok <- distribution(distribution),
         :ok <- probability(confidence),
         true <-
           is_list(order) and length(order) >= 2 and
             MapSet.new(order) == MapSet.new(Map.keys(distribution)) and
             length(order) == map_size(distribution) do
      ranked = Enum.sort_by(order, &(-Map.fetch!(distribution, &1)))
      [first, second | _] = ranked
      margin = distribution[first] - distribution[second]

      usable =
        confidence >= Keyword.get(opts, :minimum_confidence, 0.7) and
          margin >= Keyword.get(opts, :minimum_margin, 0.15)

      {:ok,
       %{
         "choice" => first,
         "probabilities" => distribution,
         "option_order" => order,
         "confidence" => confidence,
         "margin" => margin,
         "status" => if(usable, do: "supported", else: "uncertain")
       }}
    else
      false -> {:error, :invalid_option_order}
      {:error, _} = error -> error
    end
  end

  def score_keys(distribution, level_count)
      when is_map(distribution) and is_integer(level_count) and level_count >= 2 do
    Enum.reduce_while(distribution, {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      parsed =
        cond do
          is_integer(key) -> {key, ""}
          is_binary(key) -> Integer.parse(key)
          true -> :error
        end

      case parsed do
        {index, ""} when index >= 0 and index < level_count ->
          if Map.has_key?(normalized, index) do
            {:halt, {:error, :duplicate_score_level}}
          else
            {:cont, {:ok, Map.put(normalized, index, value)}}
          end

        _ ->
          {:halt, {:error, {:invalid_score_level, key}}}
      end
    end)
  end

  def score_keys(_, _), do: {:error, :invalid_score_distribution}

  def boundary(curve, threshold \\ 0.8) when is_list(curve) do
    cond do
      curve == [] ->
        {:error, :empty_curve}

      Enum.any?(curve, &(not is_number(&1["probability"]))) ->
        {:ok, %{"status" => "incomplete", "curve" => curve, "first_crossing" => nil}}

      true ->
        pairs = Enum.chunk_every(curve, 2, 1, :discard)

        crossings =
          for [before, after_point] <- pairs,
              before["probability"] < threshold,
              after_point["probability"] >= threshold,
              do: after_point["point"]

        drops =
          for [before, after_point] <- pairs,
              before["probability"] >= threshold,
              after_point["probability"] < threshold,
              do: after_point["point"]

        {:ok,
         %{
           "status" =>
             if(hd(curve)["probability"] >= threshold,
               do: "already_supported_at_entry",
               else: "complete"
             ),
           "curve" => curve,
           "first_crossing" => List.first(crossings),
           "crossings" => crossings,
           "drops" => drops
         }}
    end
  end

  defp probability(value) when is_number(value) and value >= 0 and value <= 1, do: :ok
  defp probability(_), do: {:error, :missing_or_invalid_probability}

  defp distribution(values) when is_map(values) and map_size(values) > 0 do
    if Enum.all?(Map.values(values), &(probability(&1) == :ok)),
      do: :ok,
      else: {:error, :invalid_distribution}
  end

  defp distribution(_), do: {:error, :invalid_distribution}

  defp allowed_keys(values, allowed) do
    if allowed != [] and Enum.all?(allowed, &Map.has_key?(values, &1)),
      do: :ok,
      else: {:error, :unknown_or_empty_allowed_region}
  end

  defp mass_status(mass, opts) do
    cond do
      mass >= Keyword.get(opts, :pass_mass, 0.8) -> "pass"
      mass <= Keyword.get(opts, :fail_mass, 0.2) -> "fail"
      true -> "uncertain"
    end
  end
end
