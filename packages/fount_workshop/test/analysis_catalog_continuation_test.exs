defmodule FountWorkshop.AnalysisCatalogContinuationTest do
  alias FountWorkshop.Writing.Budget
  use ExUnit.Case, async: true

  test "invalid requests fail before any service is present" do
    model = Fount.Screenplay.new()
    assert {:error, :unknown_playbook} = Fount.Intelligence.run(model, "shell", %{})

    assert {:error, _} =
             Fount.Intelligence.run(model, "search", %{"query" => "key", "quality_rank" => true})

    assert {:error, _} =
             Fount.Intelligence.run(model, "scene_lift", %{"scene_ids" => [], "constraints" => []})
  end

  test "shared limits reserve retries and never overspend" do
    budget = Budget.new(max_inference_calls: 2, max_measurement_states: 3)
    assert Budget.take(budget, :inference, 1) == 1
    assert Budget.take(budget, :inference, 2) == 1
    assert Budget.take(budget, :inference, 1) == 0
    assert Budget.take(budget, :measurement_states, 5) == 3

    assert Budget.snapshot(budget) == %{
             "inference" => 2,
             "measurement_states" => 3
           }
  end
end
