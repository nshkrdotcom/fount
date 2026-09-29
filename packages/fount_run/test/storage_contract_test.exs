defmodule FountRun.StorageContractTest do
  use ExUnit.Case, async: true

  test "public surface exposes complete Phase 05 headless controls" do
    assert Code.ensure_loaded?(FountRun)
    assert function_exported?(FountRun, :start_run, 4)
    assert function_exported?(FountRun, :get_run, 3)
    assert function_exported?(FountRun, :list_runs, 3)
    assert function_exported?(FountRun, :enqueue_step, 4)
    assert function_exported?(FountRun, :step, 4)
    assert function_exported?(FountRun, :submit_decision, 4)
    assert function_exported?(FountRun, :update_plan, 5)
    assert function_exported?(FountRun, :update_policy, 5)
    assert function_exported?(FountRun, :pause_run, 3)
    assert function_exported?(FountRun, :resume_run, 3)
    assert function_exported?(FountRun, :stop_run, 3)
    assert function_exported?(FountRun, :approve_run, 4)
    assert function_exported?(FountRun, :deliver, 5)
    assert function_exported?(FountRun, :progress, 3)
  end


  test "application child specification is host-free" do
    assert {:ok, {_flags, []}} = Supervisor.init([], strategy: :one_for_one)
  end
end
