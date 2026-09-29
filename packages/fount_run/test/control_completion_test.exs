defmodule FountRun.ControlCompletionTest do
  use ExUnit.Case, async: true

  alias Fount.ID
  alias Fount.Writing.Principal
  alias FountRun.{ActorContext, ApprovalAttempt, CLI, StageRegistry}

  test "C07 CLI parser exposes the complete headless command set with stable usage failures" do
    id = ID.v4()

    assert {:ok, %{command: "start", input: "run.json"}} = strip_help(CLI.parse(["start", "--input", "run.json"]))
    assert {:ok, %{command: "show", run_id: ^id}} = strip_help(CLI.parse(["show", id]))
    assert {:ok, %{command: "step", run_id: ^id}} = strip_help(CLI.parse(["step", id]))
    assert {:ok, %{command: "decisions", run_id: ^id}} = strip_help(CLI.parse(["decisions", id]))
    assert {:ok, %{command: "decide", decision_id: ^id, input: "decision.json"}} = strip_help(CLI.parse(["decide", id, "--input", "decision.json"]))

    assert {:ok, %{command: "plan", run_id: ^id, expected_version: 2, command_id: "cmd-plan"}} =
             strip_help(CLI.parse(["plan", id, "--input", "plan.json", "--expected-version", "2", "--command-id", "cmd-plan"]))

    assert {:ok, %{command: "policy", run_id: ^id, expected_version: 3, command_id: "cmd-policy"}} =
             strip_help(CLI.parse(["policy", id, "--input", "policy.json", "--expected-version", "3", "--command-id", "cmd-policy"]))

    for command <- ~w(pause resume stop) do
      assert {:ok, %{command: ^command, run_id: ^id}} = strip_help(CLI.parse([command, id]))
    end

    assert {:ok, %{command: "approve", run_id: ^id, input: "approval.json"}} =
             strip_help(CLI.parse(["approve", id, "--input", "approval.json"]))

    assert {:ok, %{command: "export", run_id: ^id, destination: "delivery", pdf: true, table_read: true}} =
             strip_help(CLI.parse(["export", id, "--destination", "delivery", "--pdf", "--table-read"]))

    assert {:error, :expected_version_required} = CLI.parse(["plan", id, "--input", "plan.json", "--command-id", "x"])
    assert {:error, :command_id_required} = CLI.parse(["policy", id, "--input", "policy.json", "--expected-version", "1"])
    assert {:error, :duplicate_options} = CLI.parse(["show", id, "--help", "--help"])
    assert {2, %{"exit_code" => 2}} = CLI.run(["unknown"])
  end

  test "C07 trusted actor context remains mandatory; actor strings are not a writable compatibility path" do
    assert_raise FunctionClauseError, fn ->
      FountRun.start_run(nil, %{}, "legacy-actor")
    end
  end

  test "C01/C04 approval-attempt validation includes parent lineage and exact packet identity" do
    candidate = ID.v4()
    base = ID.v4()
    parent = ID.v4()
    {:ok, human} = Principal.new(:human, "writer")

    attrs = %{
      "step_id" => nil,
      "decision_id" => ID.v4(),
      "parent_attempt_id" => parent,
      "candidate_id" => candidate,
      "base_revision_id" => base,
      "content_hash" => String.duplicate("a", 64),
      "check_set_fingerprint" => String.duplicate("b", 64),
      "packet" => %{"candidate_id" => candidate},
      "packet_artifact_ref" => nil,
      "reviewer" => Principal.to_map(human),
      "approver" => Principal.to_map(human),
      "callback_operation_id" => "human-final:#{ID.v4()}",
      "fencing_token" => 7
    }

    assert {:ok, attempt} = ApprovalAttempt.validate(attrs)
    assert attempt.parent_attempt_id == parent
    assert attempt.fencing_token == 7
    assert {:error, :invalid_approval_attempt} = ApprovalAttempt.validate(Map.put(attrs, "parent_attempt_id", "wrong"))
  end

  test "C03/C07 decide and deliver use registered headless handlers without a web dependency" do
    assert {:ok, registry} = StageRegistry.new()
    assert {:ok, FountRun.CompletionHandler} = StageRegistry.fetch(registry, "decide")
    assert {:ok, FountRun.DeliveryHandler} = StageRegistry.fetch(registry, "deliver")
    refute Code.ensure_loaded?(Phoenix.LiveView)
  end

  test "C03 agent/service approvers can be registered only in a trusted ActorContext" do
    screenplay = ID.v4()
    {:ok, owner} = Principal.new(:human, "owner")
    {:ok, service} = Principal.new(:service, "review-service")
    {:ok, context} = ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run], approvers: [service])
    assert ActorContext.allowed_approver?(context, service)

    assert {:error, :invalid_approver_registry} =
             ActorContext.new(owner, owner, screenplay, [:read_run, :manage_run], approvers: [owner])
  end

  defp strip_help({:ok, map}), do: {:ok, Map.delete(map, :help)}
  defp strip_help(other), do: other
end
