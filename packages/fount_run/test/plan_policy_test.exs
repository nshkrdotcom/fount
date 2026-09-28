defmodule FountRun.PlanPolicyTest do
  use ExUnit.Case, async: true

  alias Fount.Writing.Principal
  alias FountRun.{ActorContext, Plan, Policy}

  setup do
    {:ok, owner} = Principal.new(:human, "owner-1")
    {:ok, agent} = Principal.new(:agent, "reviewer-1")
    {:ok, context} = ActorContext.new(owner, owner, "00000000-0000-4000-8000-000000000001", [:read_run, :manage_run], approvers: [agent], route_reviewers: ["route-reviewer"])
    %{owner: owner, agent: agent, context: context}
  end

  test "plan is closed and fingerprint-stable", %{owner: owner} do
    attrs = %{"screenplay_id" => "00000000-0000-4000-8000-000000000001", "base_revision_id" => "00000000-0000-4000-8000-000000000002", "goal" => "Tighten scene", "scope" => %{"scene_ids" => ["a"]}}
    assert {:ok, one} = Plan.new(attrs, owner)
    assert {:ok, two} = Plan.new(Map.put(attrs, "constraints", []), owner)
    assert one.fingerprint == two.fingerprint
    assert {:error, {:unknown_field, "surprise"}} = Plan.new(Map.put(attrs, "surprise", true), owner)
  end

  test "policy resolves only configured principals and rejects candidate acceptance", %{context: context} do
    base = %{
      "gates" => %{"investigation_scope" => "automatic", "strategy_choice" => "human", "candidate_generation" => "automatic", "iteration" => "automatic"},
      "completion" => "accept",
      "approver" => %{"type" => "human", "id" => "owner-1"},
      "fallback_approver" => nil,
      "route_choice" => %{"rule" => "pause_on_material_tradeoff"},
      "limits" => %{}
    }
    assert {:ok, policy} = Policy.new(base, context)
    assert policy.value["limits"]["max_iterations"] == 3
    assert {:error, :candidate_completion_has_approver} = Policy.new(%{base | "completion" => "candidate"}, context)
    assert {:error, {:unknown_field, "max_repair_rounds"}} = Policy.new(put_in(base, ["limits"], %{"max_repair_rounds" => 9}), context)
  end
end
