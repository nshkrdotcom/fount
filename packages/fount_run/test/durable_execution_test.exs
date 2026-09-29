defmodule FountRun.DurableExecutionTest do
  use ExUnit.Case, async: true

  alias FountRun.{StageRegistry, Transition}

  defmodule FixtureHandler do
    @behaviour FountRun.StageHandler
    @impl true
    def execute(_claim, _opts), do: {:ok, %{"ok" => true}}
  end

  test "transition evaluation fences control, immutable binding changes and terminal replay" do
    run = %{
      "current_plan_version" => 2,
      "current_policy_version" => 3,
      "pause_requested_at" => nil,
      "stop_requested_at" => nil
    }

    step = %{"plan_version" => 2, "policy_version" => 3, "status" => "running"}
    assert :continue = Transition.evaluate(run, step, :dispatch)

    assert {:halt, :pause_requested} =
             Transition.evaluate(%{run | "pause_requested_at" => "now"}, step, :dispatch)

    assert :continue = Transition.evaluate(%{run | "pause_requested_at" => "now"}, step, :commit)

    assert {:halt, :stop_requested} =
             Transition.evaluate(%{run | "stop_requested_at" => "now"}, step, :commit)

    assert {:halt, :plan_invalidated} =
             Transition.evaluate(run, %{step | "plan_version" => 1}, :dispatch)

    assert {:halt, :policy_invalidated} =
             Transition.evaluate(run, %{step | "policy_version" => 2}, :dispatch)

    assert {:halt, :terminal_step} =
             Transition.evaluate(run, %{step | "status" => "succeeded"}, :claim)
  end

  test "stage registry is closed and Phase 05 handlers are explicit" do
    assert {:ok, registry} = StageRegistry.new(%{"check" => FixtureHandler})
    assert {:ok, FountRun.PipelineHandler} = StageRegistry.fetch(registry, "intake")
    assert {:ok, FountRun.PipelineHandler} = StageRegistry.fetch(registry, "investigate")
    assert {:ok, FountRun.PipelineHandler} = StageRegistry.fetch(registry, "plan")
    assert {:ok, FountRun.WorkshopHandler} = StageRegistry.fetch(registry, "write")
    assert {:ok, FixtureHandler} = StageRegistry.fetch(registry, "check")
    assert {:ok, FountRun.PipelineHandler} = StageRegistry.fetch(registry, "iterate")

    assert {:ok, FountRun.CompletionHandler} = StageRegistry.fetch(registry, "decide")
    assert {:ok, FountRun.DeliveryHandler} = StageRegistry.fetch(registry, "deliver")

    assert {:error, {:invalid_stage, "future"}} = StageRegistry.fetch(registry, "future")
    assert {:error, :invalid_stage_registry} = StageRegistry.new(%{"future" => FixtureHandler})
  end
end
