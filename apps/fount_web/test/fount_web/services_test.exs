defmodule FountWeb.ServicesTest do
  use ExUnit.Case, async: false

  setup do
    original = Application.get_env(:fount_web, :observe)

    on_exit(fn ->
      if is_nil(original),
        do: Application.delete_env(:fount_web, :observe),
        else: Application.put_env(:fount_web, :observe, original)
    end)

    :ok
  end

  test "configured System One mode uses the Observe provider boundary and hides credentials" do
    secret = "phase03-secret-canary"

    Application.put_env(:fount_web, :observe,
      mode: :system_one,
      provider_opts: [
        endpoint_kind: :endpoint,
        base_url: "https://system-one.invalid/root",
        model: "phase03-model",
        api_key: secret
      ]
    )

    assert {:ok, provider} = FountWeb.Services.observe_provider(Fount.ID.v4(), %{})
    assert Fount.Observe.Provider.sensor_id(provider) == "system_one"
    refute inspect(provider) =~ secret
    assert FountWeb.Services.analysis_service_summary()["mode"] == "system_one"
  end

  test "invalid provider configuration fails closed with a secret-free host error" do
    Application.put_env(:fount_web, :observe,
      mode: :system_one,
      provider_opts: [endpoint_kind: :endpoint, base_url: "not-a-url", model: "phase03-model"]
    )

    assert {:error, :observe_provider_invalid} =
             FountWeb.Services.observe_provider(Fount.ID.v4(), %{})
  end

  test "invalid host mode is visible and refuses worker provider construction" do
    Application.put_env(:fount_web, :observe, mode: :unknown)

    assert FountWeb.Services.analysis_service_summary() == %{
             "mode" => "invalid",
             "label" => "Invalid analysis configuration",
             "configured" => false
           }

    assert {:error, :observe_configuration_invalid} =
             FountWeb.Services.observe_provider(Fount.ID.v4(), %{})
  end

  test "compatibility mode is explicit and does not inject Observe" do
    Application.put_env(:fount_web, :observe, mode: :compatibility)

    assert {:ok, opts} =
             FountWeb.Services.worker_step_opts(
               "test-owner",
               Fount.ID.v4(),
               %{"id" => Fount.ID.v4(), "policy" => %{"policy" => %{"approver" => nil}}}
             )

    refute Keyword.has_key?(opts, :observe)
    assert FountWeb.Services.analysis_service_summary()["mode"] == "compatibility"
  end
end
