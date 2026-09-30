defmodule FountWeb.Phase07WorkflowManagementTest do
  use ExUnit.Case, async: true

  alias FountWeb.WorkflowManagement, as: Workflow

  defp model do
    {:ok, doc} = Fount.parse(FountWeb.Journeys.fixture_fountain())
    Fount.Screenplay.from_document(doc, cast_resolution: :literal_cues)
  end

  defp valid_policy_form(overrides \\ %{}) do
    Map.merge(
      %{
        "investigation_scope" => "automatic",
        "strategy_choice" => "human",
        "candidate_generation" => "automatic",
        "iteration" => "automatic",
        "completion" => "accept",
        "approver" => "owner",
        "route_choice" => "pause_on_material_tradeoff",
        "max_iterations" => "3",
        "max_malformed_repairs_per_call" => "1",
        "max_transient_retries" => "2",
        "max_inference_calls" => "12",
        "max_measurement_states" => "500",
        "money_enabled" => "true",
        "currency" => "USD",
        "max_microunits" => "2500000"
      },
      overrides
    )
  end

  test "W01 validates every exposed gate, trusted principal, money units and preset compatibility" do
    screenplay = model()
    {:ok, context} = FountWeb.Actors.owner_context("test-owner", screenplay.id)

    assert {:ok, policy, fingerprint} =
             Workflow.policy_from_form(valid_policy_form(), context, "test-owner")

    assert policy["gates"] == %{
             "investigation_scope" => "automatic",
             "strategy_choice" => "human",
             "candidate_generation" => "automatic",
             "iteration" => "automatic"
           }

    assert policy["approver"] == %{"type" => "human", "id" => "test-owner"}
    assert policy["route_choice"] == %{"rule" => "pause_on_material_tradeoff"}
    assert policy["limits"]["money"] == %{"currency" => "USD", "max_microunits" => 2_500_000}

    assert {:ok, reviewer_policy, _} =
             Workflow.policy_from_form(
               valid_policy_form(%{
                 "route_choice" => "registered_reviewer",
                 "route_reviewer_key" => "owner"
               }),
               context,
               "test-owner"
             )

    assert reviewer_policy["route_choice"] == %{
             "rule" => "registered_reviewer",
             "reviewer_id" => "test-owner"
           }

    assert {:ok, fallback_policy, _} =
             Workflow.policy_from_form(
               valid_policy_form(%{"owner_fallback_enabled" => "true"}),
               context,
               "test-owner"
             )

    assert fallback_policy["fallback_approver"] == %{"type" => "human", "id" => "test-owner"}

    assert {:error, :unauthorized_route_reviewer_selection} =
             Workflow.policy_from_form(
               valid_policy_form(%{
                 "route_choice" => "registered_reviewer",
                 "route_reviewer_key" => "browser-injected"
               }),
               context,
               "test-owner"
             )

    assert {:error, :owner_context_mismatch} =
             Workflow.policy_from_form(valid_policy_form(), context, "other-owner")

    assert is_binary(fingerprint)

    for field <-
          ~w(principal_id principal_type approver_id approver_type reviewer_id fallback_approver) do
      assert {:error, :unsupported_policy_field} =
               Workflow.policy_from_form(
                 valid_policy_form(%{field => "browser-injected"}),
                 context,
                 "test-owner"
               )
    end

    assert {:error, :unauthorized_principal_selection} =
             Workflow.policy_from_form(
               valid_policy_form(%{"approver" => "browser-injected"}),
               context,
               "test-owner"
             )

    assert {:error, :invalid_currency} =
             Workflow.policy_from_form(
               valid_policy_form(%{"currency" => "usd"}),
               context,
               "test-owner"
             )

    presets = Workflow.built_in_presets("test-owner", context)
    assert Enum.all?(presets, &(&1["version"] == 1 and &1["compatible"]))
    assert Enum.all?(presets, &is_binary(&1["fingerprint"]))
  end

  test "W02 catalog is closed and only source-verified durable actions build requests" do
    catalog = Workflow.action_catalog()

    assert Enum.map(catalog, & &1["id"]) |> Enum.sort() ==
             ~w(alternatives character develop investigate notes pass propagate recover sequence)
             |> Enum.sort()

    assert Enum.map(Workflow.enabled_actions(), & &1["id"]) |> Enum.sort() ==
             ~w(develop pass propagate)

    assert Enum.all?(catalog, &Map.has_key?(&1, "handler"))

    screenplay = model()
    selection = %{"whole_screenplay" => true}

    for action <- ~w(develop pass propagate) do
      assert {:ok, request} =
               Workflow.build_workshop_request(
                 screenplay,
                 action,
                 "Tighten this beat.",
                 selection
               )

      assert request["workflow"] == action
      assert request["base_revision_id"] == screenplay.revision.id
      assert request["selection"] == selection
    end

    assert {:error, :unsupported_run_action} =
             Workflow.build_workshop_request(screenplay, "investigate", "Inspect.", selection)
  end

  test "W03 uses the existing scene/element selection schema and rejects guessed page ids" do
    assert {:ok, %{"whole_screenplay" => true}} =
             Workflow.selection_from_params(%{"whole_screenplay" => "true"})

    assert {:ok, %{"targets" => targets}} =
             Workflow.selection_from_params(%{
               "scene_ids" => [Fount.ID.v4()],
               "element_ids" => [Fount.ID.v4()]
             })

    assert Enum.map(targets, & &1["kind"]) == ["scene", "element"]

    assert {:error, :invalid_scope_selection} =
             Workflow.selection_from_params(%{"page_ids" => ["12"]})
  end

  test "W05 exposes only truthful supported lifecycle controls" do
    active = %{"status" => "running", "pause_requested_at" => nil, "stop_requested_at" => nil}
    paused = %{active | "pause_requested_at" => DateTime.utc_now()}
    terminal = %{active | "status" => "completed_candidate"}

    assert Workflow.lifecycle(active)["pause"]
    refute Workflow.lifecycle(active)["resume"]
    assert Workflow.lifecycle(paused)["resume"]
    refute Workflow.lifecycle(paused)["pause"]
    refute Workflow.lifecycle(terminal)["pause"]
    refute Workflow.lifecycle(terminal)["stop"]
    refute Workflow.lifecycle(terminal)["update_plan"]
    refute Workflow.lifecycle(terminal)["update_policy"]
    assert Workflow.lifecycle(terminal)["reason"] =~ "restart-from-stage is not supported"
  end

  test "W07 multi-launch is finite and never silently truncates selected targets" do
    targets =
      for _ <- 1..Workflow.max_multi_launch(), do: %{"kind" => "scene", "id" => Fount.ID.v4()}

    assert length(Workflow.split_scopes(%{"targets" => targets}, true)) ==
             Workflow.max_multi_launch()

    too_many = targets ++ [%{"kind" => "scene", "id" => Fount.ID.v4()}]
    assert Workflow.split_scopes(%{"targets" => too_many}, true) == []
  end

  test "W08 notification projection is deduplicated and contains only persisted-state identities" do
    run = %{"id" => Fount.ID.v4(), "status" => "failed", "lock_version" => 7}
    decision = %{"id" => Fount.ID.v4(), "status" => "pending", "kind" => "strategy"}
    delivery = %{"id" => Fount.ID.v4(), "state" => "ready", "format" => "fountain"}
    step = %{"id" => Fount.ID.v4(), "status" => "failed", "stage" => "check"}

    progress = %{
      "decisions" => [decision, decision],
      "deliveries" => [delivery, delivery],
      "steps" => [step, step]
    }

    first = Workflow.notifications(run, progress)
    second = Workflow.notifications(run, progress)
    assert first == second
    assert length(first) == 4
    assert Enum.any?(first, &(&1["kind"] == "decision_required"))
    assert Enum.any?(first, &(&1["kind"] == "artifact_ready"))
    assert Enum.any?(first, &(&1["kind"] == "error"))
  end
end
