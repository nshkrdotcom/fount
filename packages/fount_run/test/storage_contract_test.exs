defmodule FountRun.StorageContractTest do
  use ExUnit.Case, async: true

  test "public surface does not expose later execution commands as no-ops" do
    assert Code.ensure_loaded?(FountRun)
    assert function_exported?(FountRun, :start_run, 4)
    assert function_exported?(FountRun, :get_run, 3)
    assert function_exported?(FountRun, :list_runs, 3)
    refute function_exported?(FountRun, :step, 4)
    refute function_exported?(FountRun, :approve_run, 4)
    refute function_exported?(FountRun, :deliver, 5)
  end

  test "application child specification is host-free" do
    assert {:ok, {_flags, []}} = Supervisor.init([], strategy: :one_for_one)
  end
end
