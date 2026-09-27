# Measuring selected screenplay material

The complete deterministic entry point is `examples/sandbox.exs`. It creates a canonical screenplay, selects actual elements, binds exact evidence through `Request.new/4`, and executes a neutral `Question` through Sandbox. The returned `Batch.entries` preserve caller order and request IDs even when provider responses arrive out of order.

## Provider configuration

```elixir
{:ok, official} = Fount.Observe.provider(api_key: key, model: model_name)
{:ok, custom} = Fount.Observe.provider(endpoint_kind: :endpoint,
  base_url: endpoint, api_key: other_key, model: other_model)
```

Each handle owns its own configuration. The generic endpoint may omit `api_key`. Credentials stay in the opaque adapter handle; do not serialize or log its internal `state`. The public Inspect implementation omits it. Neither a default model nor a hosted release is assumed here.

`Fount.Observe.evaluate(provider, requests, questions, opts)` returns `{:ok, batch}` for a complete or partial acquisition, and `{:error, error}` for invalid batch configuration. Check `batch.status` and each entry. Failed entries contain an `Error` and no observations; they must not be treated as negative answers.

## Input and context

`Request.new(model, id, semantic_input, target: target, evidence: evidence)` checks canonical source identity. Evidence comes from `Fount.Selection.evidence/1`; manufactured excerpts, stale revisions and invalid UTF-8 spans fail. A semantic-only request may have no source evidence, in which case its observation explicitly says so.

Model-visible state and closed typed context form the exact hashed semantic envelope. Target, revision and acquisition provenance are outside that envelope. Any ID actually included in model-visible state still affects the cache identity. No semantically relevant field is silently removed to improve cache reuse.

Context slots must match the active lens contract. Installed built-in assets currently need no external slots. This baseline includes neutral context primitives; later phases expand acquisition/context contracts, not this phase.

## Limits, cancellation and caching

```elixir
{:ok, cache} = Fount.Observe.Cache.Memory.start_link(max_entries: 100)
budget = Fount.Observe.Budget.new(limit: 12)
token = Fount.Observe.Cancellation.new()
opts = [max_states: 12, max_concurrency: 2, max_pending: 4,
  task_timeout_ms: 20_000, total_timeout_ms: 30_000,
  budget: budget, cancellation: token,
  cache: {Fount.Observe.Cache.Memory, cache}, privacy_namespace: project_id]
```

A shared budget counts newly scheduled states, not cache hits. Cache use requires a caller-owned privacy namespace. Stable-only reuse is the default. Hosted mutable model aliases are not treated as immutable; explicit `cache_policy: :session` permits reuse only with the same session-scoped provider handle. Memory cache capacity is caller-controlled and is not durable storage.

`Cancellation.cancel(token)` stops the owner task. The SDK owns its internal task/transport cleanup; runtime QC must verify cancellation and timeout cleanup against the actual resolved SDK. It is not a claim that every remote server operation can be undone.

Noul has probability and no confidence field. Choice retains its declared option order. Score retains the provider-reported expected value rather than rounding it to the most likely level. Pure interpretation in Intelligence applies thresholds without changing these recorded raw values.
