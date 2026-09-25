defmodule FountProbe.Budget do
  @moduledoc "Shared per-invocation resource counters, including retries and partial failures. No provider call is a free fallback."
  def new(opts \\ []) do
    counter = :atomics.new(2, signed: false)
    spent = Keyword.get(opts, :spent, %{})
    :atomics.put(counter, 1, Map.get(spent, "inference", 0))
    :atomics.put(counter, 2, Map.get(spent, "jev_states", 0))

    %{
      counter: counter,
      limits: %{
        inference: Keyword.get(opts, :max_inference_calls, 12),
        jev_states: Keyword.get(opts, :max_jev_states, 500)
      }
    }
  end

  def take(nil, _, n), do: n

  def take(budget, kind, n) when is_integer(n) and n >= 0 do
    index = if kind == :inference, do: 1, else: 2
    current = :atomics.get(budget.counter, index)
    accepted = min(n, max(budget.limits[kind] - current, 0))

    case :atomics.compare_exchange(budget.counter, index, current, current + accepted) do
      :ok -> accepted
      _ -> take(budget, kind, n)
    end
  end

  def snapshot(budget),
    do: %{
      "inference" => :atomics.get(budget.counter, 1),
      "jev_states" => :atomics.get(budget.counter, 2)
    }
end
