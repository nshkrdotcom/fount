defmodule FountRun.StorageConstraintsIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  test "migration source declares all ten Run tables and append-only guards" do
    path = Path.join(FountRun.migrations_path(), "20260928010000_create_run_foundation.exs")
    source = File.read!(path)

    for table <-
          ~w(fount_runs fount_run_plans fount_run_policies fount_run_steps fount_run_attempts fount_run_events fount_run_decisions fount_run_approval_attempts fount_run_usage fount_run_deliveries) do
      assert source =~ "CREATE TABLE #{table}"
    end

    assert source =~ "DEFERRABLE INITIALLY DEFERRED"
    assert source =~ "fount_run_reject_snapshot_mutation"
    assert source =~ "fount_run_guard_approval_immutable"
  end
end
