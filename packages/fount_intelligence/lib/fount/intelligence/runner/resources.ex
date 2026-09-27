defmodule Fount.Intelligence.Runner.Resources do
  @moduledoc "Analytical resource ownership shared by playbooks and their host. Generation counters belong to Workshop."
  alias Fount.Observe.Budget
  def new(opts \\ []), do: Budget.new(limit: Keyword.get(opts, :max_measurement_states, 500), spent: Keyword.get(opts, :spent, 0))
  def take(budget, count), do: Budget.take(budget, count)
  def spent(budget), do: Budget.spent(budget)
  def from_options(opts) do
    case Keyword.get(opts, :analysis_budget) do
      %Budget{} = budget -> budget
      nil -> embedded(Keyword.get(opts, :budget))
      _ -> nil
    end
  end
  defp embedded(%Budget{} = budget), do: budget
  defp embedded(%{analysis: %Budget{} = budget}), do: budget
  defp embedded(_), do: nil
end
