defmodule Fount.Observe.Budget do
  @moduledoc "A shared atomic cap on scheduled measurement states, independent of generation budgets."
  @enforce_keys [:counter, :limit]
  defstruct [:counter, :limit]
  @type t :: %__MODULE__{}

  def new(opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)
    spent = Keyword.get(opts, :spent, 0)

    unless is_integer(limit) and limit >= 0 and is_integer(spent) and spent >= 0,
      do: raise(ArgumentError, "measurement budget needs non-negative integer limit and spent")

    counter = :atomics.new(1, signed: false)
    :atomics.put(counter, 1, spent)
    %__MODULE__{counter: counter, limit: limit}
  end

  def take(nil, count) when is_integer(count) and count >= 0, do: count

  def take(%__MODULE__{} = budget, count) when is_integer(count) and count >= 0 do
    current = :atomics.get(budget.counter, 1)
    granted = min(count, max(budget.limit - current, 0))

    case :atomics.compare_exchange(budget.counter, 1, current, current + granted) do
      :ok -> granted
      _ -> take(budget, count)
    end
  end

  def spent(%__MODULE__{counter: counter}), do: :atomics.get(counter, 1)
  def snapshot(%__MODULE__{} = budget), do: %{"limit" => budget.limit, "spent" => spent(budget)}
end
