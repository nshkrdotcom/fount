defmodule FountRun.PlanPolicyTest do
  use ExUnit.Case, async: true

  alias Fount.Writing.Principal
  alias FountRun.{ActorContext, PipelineRequest, Plan, Policy}

  setup do
    {:ok, owner} = Principal.new(:human, "owner-1")
    {:ok, agent} = Principal.new(:agent, "reviewer-1")

    {:ok, context} =
      ActorContext.new(
        owner,
        owner,
        "00000000-0000-4000-8000-000000000001",
        [:read_run, :manage_run],
        approvers: [agent],
        route_reviewers: ["route-reviewer"]
      )

    %{owner: owner, agent: agent, context: context}
  end

  test "plan is closed and fingerprint-stable", %{owner: owner} do
    attrs = %{
      "screenplay_id" => "00000000-0000-4000-8000-000000000001",
      "base_revision_id" => "00000000-0000-4000-8000-000000000002",
      "goal" => "Tighten scene",
      "scope" => %{"scene_ids" => ["a"]}
    }

    assert {:ok, one} = Plan.new(attrs, owner)
    assert {:ok, two} = Plan.new(Map.put(attrs, "constraints", []), owner)
    assert one.fingerprint == two.fingerprint

    assert {:error, {:unknown_field, "surprise"}} =
             Plan.new(Map.put(attrs, "surprise", true), owner)
  end

  test "semantic request remains closed while admitting persisted internal runtime" do
    request = %{
      "assessment_id" => "00000000-0000-4000-8000-000000000010",
      "project_id" => "00000000-0000-4000-8000-000000000011",
      "screenplay_id" => "00000000-0000-4000-8000-000000000012",
      "revision_id" => "00000000-0000-4000-8000-000000000013",
      "source_sha256" => String.duplicate("a", 64),
      "render_sha256" => String.duplicate("b", 64),
      "schema_version" => "semantic_import_v1",
      "prompt_version" => "semantic_import_prompt_v1",
      "model" => "gpt-6.1-sol",
      "reasoning_effort" => "low",
      "provider_family" => "fixture",
      "service_key" => "deterministic_fixture",
      "command_id" => "semantic-command",
      "source_basis" => "revision_render",
      "limits" => %{"max_inference_calls" => 4}
    }

    assert {:ok, envelope} = PipelineRequest.semantic(request)
    runtime = %{"plan" => %{"chunk_count" => 1}, "extract_index" => 0}
    assert {:ok, persisted} = PipelineRequest.advance(envelope, %{"semantic_runtime" => runtime})
    assert persisted["semantic_runtime"] == runtime

    assert {:error, {:unknown_field, "surprise"}} =
             PipelineRequest.validate(Map.put(persisted, "surprise", true))

    assert {:error, :limit_exceeds_server_cap} =
             PipelineRequest.semantic(put_in(request, ["limits", "max_inference_calls"], 131))
  end

  test "policy resolves only configured principals and rejects candidate acceptance", %{
    context: context
  } do
    base = %{
      "gates" => %{
        "investigation_scope" => "automatic",
        "strategy_choice" => "human",
        "candidate_generation" => "automatic",
        "iteration" => "automatic"
      },
      "completion" => "accept",
      "approver" => %{"type" => "human", "id" => "owner-1"},
      "fallback_approver" => nil,
      "route_choice" => %{"rule" => "pause_on_material_tradeoff"},
      "limits" => %{}
    }

    assert {:ok, policy} = Policy.new(base, context)
    assert policy.value["limits"]["max_iterations"] == 3

    assert {:error, :candidate_completion_has_approver} =
             Policy.new(%{base | "completion" => "candidate"}, context)

    assert {:ok, nonmutating} =
             Policy.new(%{base | "completion" => "nonmutating", "approver" => nil}, context)

    assert nonmutating.value["completion"] == "nonmutating"
    assert nonmutating.value["approver"] == nil

    assert {:error, :nonmutating_completion_has_approver} =
             Policy.new(%{base | "completion" => "nonmutating"}, context)

    assert {:error, {:unknown_field, "max_repair_rounds"}} =
             Policy.new(put_in(base, ["limits"], %{"max_repair_rounds" => 9}), context)
  end
end
