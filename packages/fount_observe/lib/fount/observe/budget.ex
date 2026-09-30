defmodule Fount.Observe.Budget do
  @moduledoc "A shared atomic cap on scheduled measurement states, independent of generation budgets."
  @enforce_keys [:counter, :limit]
  defstruct [:counter, :limit, :reservation_hook]
  @type t :: %__MODULE__{}

  def new(opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)
    spent = Keyword.get(opts, :spent, 0)

    unless is_integer(limit) and limit >= 0 and is_integer(spent) and spent >= 0,
      do: raise(ArgumentError, "measurement budget needs non-negative integer limit and spent")

    counter = :atomics.new(1, signed: false)
    :atomics.put(counter, 1, spent)

    %__MODULE__{
      counter: counter,
      limit: limit,
      reservation_hook: Keyword.get(opts, :reservation_hook)
    }
  end

  def take(nil, count) when is_integer(count) and count >= 0, do: count

  def take(%__MODULE__{} = budget, count) when is_integer(count) and count >= 0 do
    current = :atomics.get(budget.counter, 1)
    granted = min(count, max(budget.limit - current, 0))

    case :atomics.compare_exchange(budget.counter, 1, current, current + granted) do
      :ok -> reserve(budget, granted)
      _ -> take(budget, count)
    end
  end

  defp reserve(%__MODULE__{reservation_hook: nil}, granted), do: granted

  defp reserve(%__MODULE__{reservation_hook: hook, counter: counter}, granted) do
    allowed =
      case hook.(:measurement_states, granted) do
        {:ok, n} when is_integer(n) and n >= 0 and n <= granted -> n
        _ -> 0
      end

    :atomics.sub(counter, 1, granted - allowed)
    allowed
  end

  def spent(%__MODULE__{counter: counter}), do: :atomics.get(counter, 1)
  def snapshot(nil), do: nil
  def snapshot(%__MODULE__{} = budget), do: %{"limit" => budget.limit, "spent" => spent(budget)}
end
