# FountRun

FountRun is the durable orchestration layer for controlled Fount work. Phase 02 established trusted Run identity and storage; Phase 03 added the reusable fenced execution engine. Phase 04 composes that engine into the headless screenplay pipeline: intake/preflight → investigate → saved dramatic routes → exact strategy decision → write → check → limited iteration.

The Phase 04 pipeline stops at a saved candidate/check decision boundary. It does not accept canon, deliver artifacts, or expose the later writer-control/web surfaces reserved for Phases 05–06.

## Shared Repo and migration order

The host owns the Ecto Repo. Run and Workshop use the same PostgreSQL database as Core; no second storage system is started.

```elixir
Ecto.Migrator.run(MyRepo, Fount.Persistence.migrations_path(), :up, all: true)
Ecto.Migrator.run(MyRepo, FountRun.migrations_path(), :up, all: true)
```

Core migrations add idempotent Workshop session/candidate operation keys without importing Run. Run migrations add provider-intent/reconciliation records and execution counters on top of the Phase 02 tables.

The Core operation-key migration is version `20260928011000`, distinct from the existing Run foundation migration at `20260928010000`. This lets a populated Phase 02 database apply both new Core and Run migrations without re-running the foundation schema.

## Headless screenplay pipeline

`FountRun.StageRegistry` now closes over the Phase 04 stages `intake`, `investigate`, `plan`, `write`, `check` and `iterate`. Intake performs provider-free Workshop preflight. Investigation persists report/evidence/uncertainty context. Planning reuses that saved investigation and persists three closed routes without materializing pages. When policy requires a human route gate, `FountRun.submit_decision/4` must resolve the exact saved strategy checkpoint before `write` can run; exact response replay is idempotent while competing or stale submissions conflict.

Selected-route writing uses `FountWorkshop.Strategy.materialize/4`. Checks bind candidate, canonical base, authorized scope and protected material. Failed required checks may enqueue a separate durable `iterate` step up to `max_iterations`; the inner Workshop creative repair loop remains disabled. Every candidate remains rooted in the immutable canonical base and carries parent-candidate/report lineage. Canon is never advanced by these stages.

`FountRun.progress/3` exposes run, step, decision, usage and provider-status metadata without provider response bodies. Candidate review/acceptance and delivery are intentionally not registered in Phase 04.

## One durable operation

Construct `FountRun.ActorContext` only after host authentication/authorization, create a run, then explicitly enqueue one step. A host may call `FountRun.step/4` directly or configure `FountRun.Worker` pollers.

For the Phase 03 real-domain lane, the closed registry maps `write` to `FountRun.WorkshopHandler`. It opens and links a Workshop session before provider work, resumes it with Run-owned budgets/retry allowances, and saves candidates through Core's ordinary candidate path under a fencing guard. Candidate generation does not advance canon.

Provider dispatch records intent and reserves resource budget before the call. A saved success is reused after restart. A dispatched response whose outcome cannot be recovered becomes `unknown`; its reservation remains charged/reserved and Run does not replay it blindly.

When policy sets a money ceiling, supply a same-currency estimate to `step/4` as `reserved_cost_microunits:` and `currency:`. Dispatch fails closed without an estimate. If the provider returns `usage.cost_microunits` and `usage.currency`, Run settles the actual cost. An overrun or unknown actual cost retains the charge and pauses further dispatch.

`FountRun.progress/3` exposes run, step, usage and provider-status metadata without returning prompts or provider response bodies.

See `guides/architecture.md` and `guides/storage.md`.
