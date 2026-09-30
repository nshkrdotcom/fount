defmodule Fount.Observe.PhaseTwoExecutionTest do
  use ExUnit.Case, async: true
  alias Fount.Observe.{Budget, Cache, Context, Lens, Question, Request, Resources, Sandbox}

  defp request(text \\ "Mara waits.") do
    {:ok, request} = Request.new(Fount.Screenplay.new(), "scene", %{"passage" => text})
    request
  end

  defp questions, do: [q: Question.noul("Is there observable action?")]
  defp provider, do: Sandbox.new!(%{"scene" => %{"q" => 0.8}})
  defp result(batch), do: hd(hd(batch.entries).observations).result

  test "ETS cache supports capped LRU storage, clear and expiry" do
    {:ok, cache} = Cache.ETS.start_link(max_entries: 2, ttl_ms: 60_000)
    on_exit(fn -> if Process.alive?(cache), do: GenServer.stop(cache) end)
    :ok = Cache.ETS.put(cache, "a", [1])
    :ok = Cache.ETS.put(cache, "b", [2])
    assert {:hit, [1]} = Cache.ETS.get(cache, "a")
    :ok = Cache.ETS.put(cache, "c", [3])
    assert :miss = Cache.ETS.get(cache, "b")
    assert Cache.ETS.size(cache) == 2
    :ok = Cache.ETS.clear(cache)
    assert Cache.ETS.size(cache) == 0
    {:ok, expiring} = Cache.ETS.start_link(max_entries: 2, ttl_ms: 1)
    on_exit(fn -> if Process.alive?(expiring), do: GenServer.stop(expiring) end)
    :ok = Cache.ETS.put(expiring, "x", 1)
    Process.sleep(5)
    assert :miss = Cache.ETS.get(expiring, "x")
    assert {:error, _} = Cache.ETS.start_link(max_entries: 0)
    {:ok, small} = Cache.ETS.start_link(max_entries: 2, max_entry_bytes: 8)
    on_exit(fn -> if Process.alive?(small), do: GenServer.stop(small) end)
    assert {:error, :entry_too_large} = Cache.ETS.put(small, "large", String.duplicate("x", 100))
    assert Cache.ETS.size(small) == 0
  end

  test "cache poison in either contract or raw payload is reacquired" do
    {:ok, cache} = Cache.ETS.start_link(max_entries: 10)
    on_exit(fn -> if Process.alive?(cache), do: GenServer.stop(cache) end)
    opts = [cache: {Cache.ETS, cache}, privacy_namespace: "project"]
    req = request()
    assert {:ok, first} = Fount.Observe.evaluate(provider(), [req], questions(), opts)
    measurement = result(first)
    key = measurement.metadata["cache_key"]
    assert is_binary(key)

    for corrupted <- [
          %{measurement | output_contract_sha256: String.duplicate("0", 64)},
          %{measurement | normalized_raw: %{"false" => 1}}
        ] do
      :ok = Cache.ETS.put(cache, key, [corrupted])
      assert {:ok, checked} = Fount.Observe.evaluate(provider(), [req], questions(), opts)
      assert checked.cache_hits == 0
      assert result(checked).normalized_raw == measurement.normalized_raw
    end
  end

  test "changing context changes measurement identity but changing revision does not" do
    {:ok, _, asset} = Lens.compile(questions())

    lens =
      asset
      |> Map.delete("sha256")
      |> put_in(["context_contract", "optional"], %{"intent" => %{"type" => "literal"}})

    {:ok, cache} = Cache.ETS.start_link(max_entries: 10)
    on_exit(fn -> if Process.alive?(cache), do: GenServer.stop(cache) end)
    opts = [lens: lens, cache: {Cache.ETS, cache}, privacy_namespace: "project"]
    a = %{request() | context: %Context{slots: %{"intent" => "conceal"}}}
    b = %{request() | context: a.context}
    c = %{b | context: %Context{slots: %{"intent" => "confess"}}}
    {:ok, first} = Fount.Observe.evaluate(provider(), [a], questions(), opts)
    {:ok, reused} = Fount.Observe.evaluate(provider(), [b], questions(), opts)
    {:ok, changed} = Fount.Observe.evaluate(provider(), [c], questions(), opts)
    assert reused.cache_hits == 1
    assert result(first).id == result(reused).id
    assert hd(hd(reused.entries).observations).target == b.target
    assert changed.cache_hits == 0
    refute result(changed).id == result(first).id
  end

  test "lens resource requests cannot raise host caps or spend budget at preflight" do
    {:ok, _, asset} = Lens.compile(questions())

    lens =
      asset |> Map.delete("sha256") |> Map.put("resource_policy_request", %{"max_states" => 900})

    budget = Budget.new(limit: 2)
    opts = [lens: lens, max_states: 0, budget: budget]
    assert {:ok, preflight} = Fount.Observe.preflight([request()], questions(), opts)
    assert preflight["caps"]["max_states"] == 0
    assert preflight["targets"] == 1
    assert Budget.snapshot(budget)["spent"] == 0
    {:ok, batch} = Fount.Observe.evaluate(provider(), [request()], questions(), opts)
    assert batch.scheduled == 0
    assert batch.resource_usage["actual"]["provider_requests"] == 0
    assert hd(batch.entries).error.class == :budget_exhausted
  end

  test "remote request count stays unknown when a scheduled call has no completion metadata" do
    actual = Resources.actual(%{sensor_id: "system_one"}, [], 1, nil)
    assert actual["initial_provider_requests_scheduled"] == 1
    assert actual["provider_requests"] == nil
    assert actual["reported_retries"] == nil

    assert Resources.actual(%{sensor_id: "system_one"}, [], 0, nil)[
             "provider_requests"
           ] == 0
  end

  test "state and question caps fail before dispatch" do
    {:ok, batch} =
      Fount.Observe.evaluate(provider(), [request(String.duplicate("x", 500))], questions(),
        max_context_bytes: 50
      )

    assert batch.scheduled == 0
    assert hd(batch.entries).error.class == :state_too_large

    assert {:error, %{class: :state_too_large}} =
             Fount.Observe.evaluate(provider(), [request()], questions(), max_question_bytes: 5)
  end

  test "mutable aliases cannot be promoted to durable identity by their spelling" do
    unstable = %{
      provider()
      | fingerprint: %{
          "provider" => "sandbox",
          "model" => "jev-1.13.0",
          "stability" => "mutable_alias_or_unknown"
        }
    }

    {:ok, cache} = Cache.ETS.start_link(max_entries: 10)
    on_exit(fn -> if Process.alive?(cache), do: GenServer.stop(cache) end)
    opts = [cache: {Cache.ETS, cache}, privacy_namespace: "private", cache_policy: :durable]
    {:ok, batch} = Fount.Observe.evaluate(unstable, [request()], questions(), opts)
    assert hd(batch.entries).error.class == :unstable_model_identity_for_durable_cache
    assert batch.scheduled == 0
  end

  test "credential-like transport extras are rejected, not persisted" do
    for extra <- [
          %{"api_key" => "never-store"},
          %{"headers" => %{"Authorization" => "never-store"}}
        ] do
      assert {:error, error} =
               Fount.Observe.evaluate(provider(), [request()], questions(), extra_body: extra)

      refute inspect(error) =~ "never-store"
    end
  end

  test "raw measurements, separate calibration, resources and exact model metadata survive" do
    calibration = %{
      "id" => "project.raw",
      "method" => "identity",
      "validation" => "identity_not_empirical"
    }

    {:ok, batch} =
      Fount.Observe.evaluate(provider(), [request()], questions(), calibration: calibration)

    measured = result(batch)
    assert measured.normalized_raw == measured.value
    assert measured.calibration["validation"] == "identity_not_empirical"

    assert hd(hd(batch.entries).observations).calibration_sha256 ==
             measured.calibration["asset_sha256"]

    assert batch.resource_usage["actual"]["scheduled_states"] == 1
    assert batch.resource_usage["actual"]["provider_requests"] == 0
    assert batch.resource_usage["actual"]["hosted_cost"] == nil
  end

  test "configured normalization tolerance applies to Sandbox as well as the SDK" do
    p =
      Sandbox.new!(%{
        "scene" => %{
          "q" => %{
            "choice" => "a",
            "confidence" => 0.3,
            "probabilities" => %{"a" => 0.5, "b" => 0.49}
          }
        }
      })

    q = [q: Question.choice("Which?", a: "A", b: "B")]
    {:ok, permissive} = Fount.Observe.evaluate(p, [request()], q)
    assert permissive.status == :complete
    {:ok, strict} = Fount.Observe.evaluate(p, [request()], q, probability_tolerance: 0.001)
    assert hd(strict.entries).error.class == :invalid_provider_response
  end

  test "shared Observe scheduling uses the durable reservation grant exactly once" do
    parent = self()

    budget =
      Budget.new(
        limit: 7,
        reservation_hook: fn :measurement_states, requested ->
          send(parent, {:reserved, requested})
          {:ok, min(requested, 2)}
        end
      )

    assert Budget.take(budget, 5) == 2
    assert_receive {:reserved, 5}
    refute_receive {:reserved, _}
    assert Budget.spent(budget) == 2

    denied =
      Budget.new(
        limit: 7,
        reservation_hook: fn :measurement_states, _ ->
          {:error, :stale_claim}
        end
      )

    assert Budget.take(denied, 5) == 0
    assert Budget.spent(denied) == 0
  end

  test "atomic reservations cannot overspend one shared state budget" do
    budget = Budget.new(limit: 7)

    granted =
      1..50
      |> Task.async_stream(fn _ -> Budget.take(budget, 1) end, max_concurrency: 10)
      |> Enum.map(fn {:ok, count} -> count end)
      |> Enum.sum()

    assert granted == 7
    assert Budget.snapshot(budget)["spent"] == 7
  end

  test "a cache entry cannot smuggle unrecognized provider metadata into a new observation" do
    cache = start_supervised!({Cache.ETS, max_entries: 10})
    opts = [cache: {Cache.ETS, cache}, privacy_namespace: "metadata-test"]
    req = request()
    {:ok, first} = Fount.Observe.evaluate(provider(), [req], questions(), opts)
    original = result(first)
    poisoned = put_in(original.metadata["provider"]["api_key"], "never-export-this")
    :ok = Cache.ETS.put(cache, original.metadata["cache_key"], [poisoned])
    {:ok, checked} = Fount.Observe.evaluate(provider(), [req], questions(), opts)
    assert checked.cache_hits == 0
    refute inspect(checked) =~ "never-export-this"
  end
end
