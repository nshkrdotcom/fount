defmodule FountWorkshop.PhaseSixteenAcceptanceMatrixTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../..", __DIR__)
  @matrix Path.join(
            @root,
            "packages/fount_workshop/examples/phase_sixteen/acceptance_matrix.json"
          )

  test "final acceptance matrix owns every W01-W12 and A01-A12 evidence path" do
    matrix = @matrix |> File.read!() |> Jason.decode!()

    assert matrix["phase"] == 16
    assert matrix["phase16_execution_status"] in ["NOT_RUN", "PASS", "PARTIAL", "FAIL"]

    workflows = Map.new(matrix["workflows"], &{&1["id"], &1})
    scenarios = Map.new(matrix["scenarios"], &{&1["id"], &1})

    assert Map.keys(workflows) |> Enum.sort() == Enum.map(1..12, &"W#{pad(&1)}")
    assert Map.keys(scenarios) |> Enum.sort() == Enum.map(1..12, &"A#{pad(&1)}")

    for {_id, record} <- workflows,
        path <- record["evidence_paths"] do
      assert File.regular?(Path.join(@root, path)), path
    end

    for {_id, record} <- scenarios do
      assert record["phase16_execution_status"] in ["NOT_RUN", "PASS", "PARTIAL", "FAIL"]
      assert is_binary(record["source_revision"]) and record["source_revision"] != ""
      assert is_list(record["assertions"]) and record["assertions"] != []
      assert is_binary(record["invoked_public_operation_or_command"])

      for path <- record["evidence_paths"] do
        assert File.regular?(Path.join(@root, path)), path
      end
    end
  end

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")
end
