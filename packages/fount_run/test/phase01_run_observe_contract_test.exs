defmodule FountRun.Phase01RunObserveContractTest do
  use ExUnit.Case, async: true

  alias FountRun.WorkshopIntegration

  test "R03 durable analysis is enabled only when a trusted Observe provider is present" do
    claim = %{"screenplay_id" => "95e713a1-27c9-43f9-8a40-a7cefa3a1a5e"}
    base = [operation_key: "phase01:test"]

    assert WorkshopIntegration.durable_analysis_options(base, claim, []) == base

    options =
      WorkshopIntegration.durable_analysis_options(base, claim, observe: :sandbox_fixture)

    assert options[:durable_analysis] == true
    assert is_binary(options[:analysis_privacy_namespace])
    assert options[:analysis_privacy_namespace] == WorkshopIntegration.privacy_namespace(claim)
    refute options[:analysis_privacy_namespace] =~ claim["screenplay_id"]
  end

  test "R01 Worker preserves Observe in the explicit ActorContext step options" do
    observe = make_ref()

    assert {:ok, state} =
             FountRun.Worker.init(
               repo: :repo_fixture,
               run_id: "run-fixture",
               context: :actor_context_fixture,
               step_opts: [observe: observe, lease_ms: 5_000]
             )

    assert state.step_opts[:observe] == observe
    assert state.step_opts[:lease_ms] == 5_000
    assert is_binary(state.step_opts[:worker_id])
    assert_receive :poll
  end

  test "R07 fount_run source has no direct System One SDK dependency or native API usage" do
    package_root = Path.expand("..", __DIR__)
    mix_source = File.read!(Path.join(package_root, "mix.exs"))

    refute mix_source =~ "system_one_sdk"
    refute mix_source =~ "SystemOneSDK"

    package_root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      source = File.read!(path)
      refute source =~ "SystemOneSDK", "direct SystemOneSDK reference in #{path}"
      refute source =~ ":system_one_sdk", "direct :system_one_sdk dependency in #{path}"
    end)
  end
end
