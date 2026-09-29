# Changelog

## Unreleased

- Add Phase 03 durable execution: PostgreSQL-clock claims, lease heartbeat/reclaim, monotonic fencing, closed stage registry, configurable workers and one-operation progress inspection.
- Add idempotent Workshop open/link/candidate seams, provider intent/reconciliation, durable retry counters and atomic Run usage reservations; ambiguous paid outcomes stop instead of blind replay.
- Add a real scripted Workshop operation plus fault/concurrency/budget/control integration coverage while leaving Phase 04 pipeline scheduling and canonical acceptance absent.
- Verify the Phase 03 migration upgrade from populated Phase 02 storage, account for failed provider dispatches, and pause on unknown or over-budget monetary settlement.

- Add the Phase 02 Run foundation: shared-Repo migrations, trusted actor context, immutable plan/policy snapshots, idempotent run creation/read/list, append-only events and storage primitives for decisions, approval attempts, future worker leases, usage and delivery identities.
- Keep provider execution, worker claiming/recovery, screenplay orchestration and canonical approval dispatch out of this phase.
