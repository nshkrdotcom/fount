defmodule FountRun.Transition do
  @moduledoc "Pure durable-execution transition checks shared by claim and commit paths."

  @terminal ~w(succeeded failed cancelled fenced)

  def evaluate(run, step, phase) when phase in [:claim, :dispatch, :commit] do
    cond do
      run["pause_requested_at"] && phase != :commit -> {:halt, :pause_requested}
      run["stop_requested_at"] -> {:halt, :stop_requested}
      step["plan_version"] != run["current_plan_version"] -> {:halt, :plan_invalidated}
      step["policy_version"] != run["current_policy_version"] -> {:halt, :policy_invalidated}
      step["status"] in @terminal and phase != :commit -> {:halt, :terminal_step}
      true -> :continue
    end
  end

  def evaluate(_, _, _), do: {:halt, :invalid_transition}
end
