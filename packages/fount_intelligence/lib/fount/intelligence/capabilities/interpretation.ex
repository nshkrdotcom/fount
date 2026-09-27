defmodule Fount.Intelligence.Capabilities.Interpretation do
  @moduledoc "Pure, explicitly uncalibrated review policies over Observe distributions. Acquisition failures are not evidence of absence."
  alias Fount.Intelligence.Capabilities.DecisionPolicy
  alias Fount.Observe.Distribution

  def answer(value, opts \\ [])
  def answer(%Distribution{kind: :noul} = value, opts) do
    with :ok <- Distribution.validate(value),
         {:ok, policy} <- DecisionPolicy.noul(Map.new(value.values)["true"], opts) do
      Map.merge(policy, %{"type" => "noul"})
    else
      _ -> invalid("invalid_noul")
    end
  end
  def answer(%Distribution{kind: :choice} = value, opts) do
    with :ok <- Distribution.validate(value),
         {:ok, policy} <- DecisionPolicy.choice(Map.new(value.values), Enum.map(value.values, &elem(&1, 0)), value.confidence, opts) do
      Map.merge(policy, %{"type" => "choice", "provider_choice" => value.selected})
    else
      _ -> invalid("invalid_choice")
    end
  end
  def answer(%Distribution{kind: :score} = value, _opts) do
    case Distribution.validate(value) do
      :ok -> Map.put(Distribution.to_map(value), "status", "complete")
      _ -> invalid("invalid_score_distribution")
    end
  end
  def answer(_, _), do: invalid("missing_or_unknown_answer")

  def threshold_options(%{"interpretation_policy" => thresholds}) when is_map(thresholds) do
    [supported: thresholds["support_probability"], unsupported: thresholds["unsupported_probability"],
      minimum_confidence: thresholds["minimum_confidence"], minimum_margin: thresholds["minimum_margin"],
      pass_mass: thresholds["pass_mass"], fail_mass: thresholds["fail_mass"]]
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
  end
  def threshold_options(_), do: []
  defp invalid(reason), do: %{"status" => "error", "reason" => reason}
end
