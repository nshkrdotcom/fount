# FountRun

FountRun is the durable orchestration layer for bounded Fount work. Phase 02 established trusted Run identity and storage. Phase 03 adds the reusable execution engine for **one explicit operation at a time**: enqueue, claim, heartbeat, fence, execute, checkpoint, reconcile and inspect.

The engine deliberately does not schedule the intake → investigate → plan → write → check screenplay pipeline. That orchestration and strategy-decision flow is Phase 04. Writer steering APIs, approval/acceptance and delivery remain later phases.

## Shared Repo and migration order

The host owns the Ecto Repo. Run and Workshop use the same PostgreSQL database as Core; no second storage system is started.

```elixir
Ecto.Migrator.run(MyRepo, Fount.Persistence.migrations_path(), :up, all: true)
Ecto.Migrator.run(MyRepo, FountRun.migrations_path(), :up, all: true)
```

Core migrations add idempotent Workshop session/candidate operation keys without importing Run. Run migrations add provider-intent/reconciliation records and execution counters on top of the Phase 02 tables.

## One durable operation

Construct `FountRun.ActorContext` only after host authentication/authorization, create a run, then explicitly enqueue one step. A host may call `FountRun.step/4` directly or configure `FountRun.Worker` pollers.

For the Phase 03 real-domain lane, the closed registry maps `write` to `FountRun.WorkshopHandler`. It opens and links a Workshop session before provider work, resumes it with Run-owned budgets/retry allowances, and saves candidates through Core's ordinary candidate path under a fencing guard. Candidate generation does not advance canon.

Provider dispatch records intent and reserves resource budget before the call. A saved success is reused after restart. A dispatched response whose outcome cannot be recovered becomes `unknown`; its reservation remains charged/reserved and Run does not replay it blindly.

`FountRun.progress/3` exposes run, step, usage and provider-status metadata without returning prompts or provider response bodies.

See `guides/architecture.md` and `guides/storage.md`.
