defmodule Fount.Observe.PhaseTwoProviderTest do
  use ExUnit.Case, async: true
  alias Fount.Observe.{Cache, Provider, Question, Request}
  alias SystemOneSDK.Test, as: SDKTest

  defp handle(client),
    do: %Provider{
      sensor_id: "system_one",
      state: %{client: client},
      fingerprint: %{
        "provider" => "fixture-transport",
        "model" => "fixture",
        "stability" => "immutable_exact"
      }
    }

  defp body,
    do: %{
      "model" => "fixture",
      "usage" => %{"input_tokens" => 3, "output_tokens" => 2},
      "answers" => %{"visible" => %{"type" => "noul", "noul" => 0.9}}
    }

  defp requests do
    for id <- ["a", "b"] do
      {:ok, request} = Request.new(Fount.Screenplay.new(), id, %{"passage" => id <> " waits."})
      request
    end
  end

  test "official and generic endpoint construction keeps credentials inside opaque handles" do
    for kind <- [:typesafe, :endpoint] do
      opts = [endpoint_kind: kind, api_key: "synthetic-test-key", model: "fixed-model"]

      opts =
        if kind == :endpoint,
          do: Keyword.put(opts, :base_url, "https://example.test/v1"),
          else: opts

      assert {:ok, provider} = Fount.Observe.provider(opts)
      assert Provider.sensor_id(provider) == "system_one"
      assert provider.fingerprint["endpoint_kind"] == to_string(kind)
      assert provider.fingerprint["model"] == "fixed-model"
      assert is_binary(provider.fingerprint["endpoint_sha256"])
      refute inspect(provider) =~ "synthetic-test-key"
      refute inspect(provider.fingerprint) =~ "synthetic-test-key"
    end
  end

  test "completed results survive total timeout and can be reused while failed states stay unavailable" do
    parent = self()
    {:ok, count} = Agent.start_link(fn -> 0 end)
    on_exit(fn -> if Process.alive?(count), do: Agent.stop(count) end)

    client =
      SDKTest.client()
      |> SDKTest.stub_callback(fn _request ->
        n = Agent.get_and_update(count, fn n -> {n + 1, n + 1} end)

        if n == 1 do
          {:response, body()}
        else
          send(parent, {:slow_started, self()})

          receive do
            :release -> {:response, body()}
          after
            5_000 -> {:response, body()}
          end
        end
      end)

    on_exit(fn -> SDKTest.close(client) end)
    {:ok, cache} = Cache.ETS.start_link(max_entries: 10)
    on_exit(fn -> if Process.alive?(cache), do: GenServer.stop(cache) end)
    reqs = requests()

    opts = [
      total_timeout_ms: 1_000,
      max_concurrency: 1,
      retry: false,
      cache: {Cache.ETS, cache},
      privacy_namespace: "timeout-test"
    ]

    task =
      Task.async(fn ->
        Fount.Observe.evaluate(handle(client), reqs, [visible: Question.noul("Visible?")], opts)
      end)

    assert_receive {:slow_started, worker}, 2_000
    assert {:ok, batch} = Task.await(task, 3_000)
    assert [first, last] = batch.entries
    assert first.status == :complete
    assert last.error.class == :provider_timeout
    assert last.observations == []
    assert hd(first.observations).result.provider_fingerprint["reported_model"] == "fixture"
    send(worker, :release)

    assert {:ok, reused} =
             Fount.Observe.evaluate(
               handle(client),
               Enum.take(reqs, 1),
               [visible: Question.noul("Visible?")],
               opts
             )

    assert reused.cache_hits == 1
    assert reused.scheduled == 0
  end

  test "finite provider request cap disables retries and prevents a second dispatch" do
    client = SDKTest.client() |> SDKTest.stub_response(body())
    on_exit(fn -> SDKTest.close(client) end)

    assert {:ok, batch} =
             Fount.Observe.evaluate(
               handle(client),
               requests(),
               [visible: Question.noul("Visible?")],
               max_provider_requests: 1
             )

    assert batch.scheduled == 1
    assert hd(Enum.drop(batch.entries, 1)).error.class == :budget_exhausted
    assert length(SDKTest.requests(client)) == 1

    assert {:error, %{class: :invalid_request}} =
             Fount.Observe.evaluate(
               handle(client),
               requests(),
               [visible: Question.noul("Visible?")],
               max_provider_requests: 1,
               retry: true
             )
  end

  test "wire request size failures are neutral, contain no raw request and spend no remote call" do
    client = SDKTest.client() |> SDKTest.stub_response(body())
    on_exit(fn -> SDKTest.close(client) end)

    assert {:ok, batch} =
             Fount.Observe.evaluate(
               handle(client),
               Enum.take(requests(), 1),
               [visible: Question.noul("Visible?")],
               max_request_bytes: 1
             )

    assert hd(batch.entries).error.class == :state_too_large
    assert hd(batch.entries).observations == []
    assert SDKTest.requests(client) == []
    refute inspect(batch.errors) =~ "a waits."
  end
end
