defmodule FountProbe.CatalogContinuationTest do
  use ExUnit.Case, async: true
  test "invalid requests fail before any service is present" do
    model = Fount.Screenplay.new()
    assert {:error, :unknown_probe_tool} = FountProbe.run(model, "shell", %{})
    assert {:error, _} = FountProbe.run(model, "search", %{"query" => "key", "quality_rank" => true})
    assert {:error, _} = FountProbe.run(model, "scene_lift", %{"scene_ids" => [], "constraints" => []})
  end
  test "shared limits reserve retries and never overspend" do
    budget = FountProbe.Budget.new(max_inference_calls: 2, max_jev_states: 3)
    assert FountProbe.Budget.take(budget, :inference, 1) == 1
    assert FountProbe.Budget.take(budget, :inference, 2) == 1
    assert FountProbe.Budget.take(budget, :inference, 1) == 0
    assert FountProbe.Budget.take(budget, :jev_states, 5) == 3
    assert FountProbe.Budget.snapshot(budget) == %{"inference" => 2, "jev_states" => 3}
  end
end
