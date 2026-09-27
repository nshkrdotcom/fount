defmodule Fount.Observe.CacheIntegrityTest do
  use ExUnit.Case, async: true
  alias Fount.Observe.{Cache, Question, Request, Sandbox}
  alias Fount.Observe.Options

  test "LRU storage evicts the least recently read entry" do
    cache = start_supervised!({Cache.Memory, max_entries: 2})
    assert :ok = Cache.Memory.put(cache, "a", [:first])
    assert :ok = Cache.Memory.put(cache, "b", [:second])
    assert {:hit, [:first]} = Cache.Memory.get(cache, "a")
    assert :ok = Cache.Memory.put(cache, "c", [:third])
    assert :miss = Cache.Memory.get(cache, "b")
    assert Cache.Memory.size(cache) == 2
    assert :ok = Cache.Memory.clear(cache)
    assert Cache.Memory.size(cache) == 0
  end

  test "model-visible text, question wording and model selection invalidate reuse" do
    cache = start_supervised!({Cache.Memory, max_entries: 20})
    provider = Sandbox.new!(%{"a" => %{"q" => 0.7}})
    model = Fount.Screenplay.new()
    {:ok, first} = Request.new(model, "a", %{"text" => "Mara opens the door."})
    {:ok, changed} = Request.new(model, "a", %{"text" => "Mara locks the door."})
    opts = [cache: {Cache.Memory, cache}, privacy_namespace: "private"]
    q = [q: Question.noul("Does Mara enter?")]
    assert {:ok, initial} = Fount.Observe.evaluate(provider, [first], q, opts)
    assert initial.cache_hits == 0
    assert {:ok, repeated} = Fount.Observe.evaluate(provider, [first], q, opts)
    assert repeated.cache_hits == 1

    for {request, questions, options} <- [
          {changed, q, opts},
          {first, [q: Question.noul("Does Mara leave?")], opts},
          {first, q, Keyword.put(opts, :model, "different-model")}
        ] do
      assert {:ok, batch} = Fount.Observe.evaluate(provider, [request], questions, options)
      assert batch.cache_hits == 0
    end
  end

  test "cache configuration requires an explicit privacy namespace" do
    cache = start_supervised!({Cache.Memory, []})
    assert {:error, _} = Options.normalize(cache: {Cache.Memory, cache})
  end
end
