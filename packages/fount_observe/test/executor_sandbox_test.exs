defmodule Fount.Observe.ExecutorSandboxTest do
  use ExUnit.Case, async: true

  alias Fount.Observe.Budget

  alias Fount.Observe.{
    Association,
    Cache,
    Cancellation,
    Error,
    ProviderResult,
    Question,
    Request,
    Sandbox
  }

  defp request(model, id, text \\ "Mara waits.") do
    {:ok, request} = Request.new(model, id, %{"passage" => text})
    request
  end

  test "sandbox runs without providers and reassembles shuffled responses" do
    model = Fount.Screenplay.new()

    provider =
      Sandbox.new!(%{"a" => %{"visible" => 0.8}, "b" => %{"visible" => 0.2}}, order: :reverse)

    requests = [request(model, "a"), request(model, "b", "Dan leaves.")]

    assert {:ok, batch} =
             Fount.Observe.evaluate(provider, requests,
               visible: Question.noul("Is behavior visible?")
             )

    assert Enum.map(batch.entries, & &1.request_id) == ["a", "b"]
    assert batch.status == :complete
    assert hd(hd(batch.entries).observations).result.distribution.confidence == nil
  end

  test "cache reuses measurements but binds observations to the current revision" do
    {:ok, cache} = Cache.Memory.start_link(max_entries: 10)
    on_exit(fn -> if Process.alive?(cache), do: GenServer.stop(cache) end)
    a = Fount.Screenplay.new()
    b = Fount.Screenplay.new()
    provider = Sandbox.new!(%{"a" => %{"visible" => 0.8}, "b" => %{"visible" => 0.8}})
    opts = [cache: {Cache.Memory, cache}, privacy_namespace: "test-private"]

    assert {:ok, first} =
             Fount.Observe.evaluate(
               provider,
               [request(a, "a")],
               [visible: Question.noul("Visible?")],
               opts
             )

    assert {:ok, second} =
             Fount.Observe.evaluate(
               provider,
               [request(b, "b")],
               [visible: Question.noul("Visible?")],
               opts
             )

    assert second.cache_hits == 1
    before = hd(hd(first.entries).observations)
    current = hd(hd(second.entries).observations)
    assert before.result.id == current.result.id
    assert current.target.revision_id == b.revision.id
    refute before.id == current.id

    assert {:ok, other} =
             Fount.Observe.evaluate(
               provider,
               [request(b, "b")],
               [visible: Question.noul("Visible?")],
               Keyword.put(opts, :privacy_namespace, "other-project")
             )

    assert other.cache_hits == 0
  end

  test "malformed and missing associations never become negative evidence" do
    model = Fount.Screenplay.new()
    requests = [request(model, "a"), request(model, "b")]
    result = %ProviderResult{batch_index: 0, answers: %{}}
    {entries, errors} = Association.assemble(requests, [result, result])
    assert Enum.all?(entries, fn {_request, item} -> match?(%Error{}, item.error) end)
    assert Enum.any?(errors, &(&1.class == :association_error))
  end

  test "unknown fixture and exhausted budget remain explicit acquisition errors" do
    model = Fount.Screenplay.new()
    provider = Sandbox.new!(%{})

    assert {:ok, batch} =
             Fount.Observe.evaluate(provider, [request(model, "missing")],
               q: Question.noul("Visible?")
             )

    assert hd(batch.entries).status == :error
    assert hd(batch.entries).observations == []
    budget = Budget.new(limit: 0)

    assert {:ok, limited} =
             Fount.Observe.evaluate(
               provider,
               [request(model, "a")],
               [q: Question.noul("Visible?")],
               budget: budget
             )

    assert hd(limited.entries).error.class == :budget_exhausted
    assert limited.scheduled == 0
  end

  test "pre-cancelled requests do not dispatch" do
    token = Cancellation.new()
    :ok = Cancellation.cancel(token)
    provider = Sandbox.new!(%{"a" => %{"q" => 0.8}})

    assert {:ok, batch} =
             Fount.Observe.evaluate(
               provider,
               [request(Fount.Screenplay.new(), "a")],
               [q: Question.noul("Visible?")],
               cancellation: token
             )

    assert hd(batch.entries).error.class == :provider_cancelled
    assert batch.scheduled == 0
  end
end
