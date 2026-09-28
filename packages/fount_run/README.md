# FountRun

FountRun is the durable orchestration/storage layer for Fount. Phase 02 establishes the Run package, shared-database migrations, trusted actor boundary, immutable plan/policy snapshots, durable decision and approval-attempt records, usage accounting identities, future-worker step/lease/attempt storage, events and delivery identities.

It does **not** execute providers, claim/reclaim work, generate screenplay pages, dispatch approval callbacks, accept Core canon or export files yet. Those behaviors are implemented in later phases instead of appearing here as successful no-ops.

## Shared Repo

A caller owns and starts the Ecto Repo. Run uses the same PostgreSQL database as Fount Core and never starts a second Repo.

```elixir
Ecto.Migrator.run(MyRepo, Fount.Persistence.migrations_path(), :up, all: true)
Ecto.Migrator.run(MyRepo, FountRun.migrations_path(), :up, all: true)
```

Construct `FountRun.ActorContext` only after host authentication/authorization. `FountRun.start_run/4` validates a closed plan/policy, verifies the base revision, then atomically writes run + plan version 1 + policy version 1. The caller-supplied idempotency key replays the original run only for the same normalized input and authenticated calling principal. Phase 02 accepts no start options beyond the default empty list; later phases add options only when they have real behavior.

See `guides/architecture.md` and `guides/storage.md`.
