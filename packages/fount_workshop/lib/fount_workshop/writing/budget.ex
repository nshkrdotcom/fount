defmodule FountWorkshop.Writing.Budget do
  @moduledoc false
  alias Fount.Intelligence.Runner.Resources

  def new(opts \\ []) do
    spent = Keyword.get(opts, :spent, %{})
    used = Map.get(spent, "inference", 0)
    limit = Keyword.get(opts, :max_inference_calls, 12)

    if not (is_integer(used) and used >= 0 and is_integer(limit) and limit >= 0),
      do: raise(ArgumentError, "budget limits and spent values must be non-negative integers")

    counter = :atomics.new(1, signed: false)
    :atomics.put(counter, 1, used)

    %{
      counter: counter,
      limits: %{inference: limit},
      reservation_hook: Keyword.get(opts, :reservation_hook),
      analysis:
        Resources.new(
          max_measurement_states: Keyword.get(opts, :max_measurement_states, 500),
          spent: Map.get(spent, "measurement_states", 0)
        )
    }
  end

  def take(nil, _kind, n) when is_integer(n) and n >= 0, do: n

  def take(budget, :measurement_states, n) when is_integer(n) and n >= 0 do
    allowed = reserve(budget.reservation_hook, :measurement_states, n)
    Resources.take(budget.analysis, allowed)
  end

  def take(budget, :inference, n) when is_integer(n) and n >= 0 do
    current = :atomics.get(budget.counter, 1)
    granted = min(n, max(budget.limits.inference - current, 0))

    case :atomics.compare_exchange(budget.counter, 1, current, current + granted) do
      :ok -> granted
      _ -> take(budget, :inference, n)
    end
  end

  def snapshot(budget),
    do: %{
      "inference" => :atomics.get(budget.counter, 1),
      "measurement_states" => Resources.spent(budget.analysis)
    }

  defp reserve(nil, _kind, n), do: n

  defp reserve(hook, kind, n) when is_function(hook, 2) do
    case hook.(kind, n) do
      {:ok, granted} when is_integer(granted) and granted >= 0 and granted <= n -> granted
      {:error, _reason} -> 0
      _ -> 0
    end
  end
end
