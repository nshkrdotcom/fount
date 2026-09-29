# Run storage

Run migrations are separate from Core migrations and run second on the same Repo/database. `FountRun.migrations_path/0` exposes the directory.

Phase 02 tables remain authoritative: runs, plans, policies, steps, attempts, events, decisions, approval attempts, usage and deliveries. Phase 03 adds `fount_run_provider_requests` plus step result/retry/dispatch/measurement counters. Core separately adds nullable unique `operation_key` columns to `writing_sessions` and `writing_candidates`; those keys make Workshop open/candidate materialization idempotent without changing standalone APIs.

## Durable execution records

- Steps bind the exact plan version, policy version, request fingerprint and input IDs.
- Attempts retain monotonic fencing token and terminal outcome.
- Provider requests persist intent, dispatch state, response identity/status and safe usage metadata.
- Usage reservations are idempotent by operation/resource and enforce global inference/measurement limits atomically under the Run lock.
- Malformed-output repair and transport-retry counters are distinct and durable.
- Successful step results are hashed and stored with output candidate/revision/report IDs.

An unknown paid response is not released and is not automatically replayed. A later recovered response can settle that same usage record. A configured hard money ceiling requires a known same-currency estimate before dispatch; Phase 03 does not invent model pricing.

`FountRun.progress/3` intentionally omits provider request/response bodies. Runtime PostgreSQL recovery/concurrency tests remain required before Phase 03 can be marked complete.
