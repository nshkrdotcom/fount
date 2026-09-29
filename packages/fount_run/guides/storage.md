# Run storage

Run migrations are separate from Core migrations and run second on the same Repo/database. `FountRun.migrations_path/0` exposes the directory.

Phase 02 tables remain authoritative: runs, plans, policies, steps, attempts, events, decisions, approval attempts, usage and deliveries. Phase 03 adds provider-intent/reconciliation records and durable execution counters. Phase 04 uses those records for the screenplay pipeline. Phase 05 adds only the storage needed to make steering/replay and approval lineage exact: plan/policy `command_key` plus `command_fingerprint`, and nullable `parent_attempt_id` on approval attempts.

## Snapshot and control history

Plan/policy rows are append-only. Public updates require an expected current version and a caller command id. The stored command fingerprint includes the command id, expected version and complete payload, so an identical retry replays while a same-id/different-request retry conflicts.

A same-base/same-scope plan update advances the existing run. A base/scope change creates a successor and records `parent_run_id` / `superseding_run_id`; previous candidates, decisions, attempts and usage are retained. Usage queries include the parent chain so budget counters do not reset.

Pause/stop are durable timestamps on the run. Stop fences open approval attempts and running steps but leaves candidate/revision rows available for export.

## Approval attempts

Approval attempts bind run, screenplay, step/decision, optional parent attempt, plan and policy version/fingerprint, candidate, base, content hash, check set, review packet/reference, reviewer, approver, callback operation id and fencing token. That identity is immutable.

The review payload/recommendation becomes immutable once saved. The Core approval id/payload/hash becomes immutable once constructed. Terminal outcomes (`accepted`, `rejected`, `invalid`, `fenced`, `failed`) cannot be rewritten. A fallback human attempt is a new row linked through `parent_attempt_id`, so a failed automated review cannot be laundered into a different origin.

## Delivery rows

Each format is a distinct immutable delivery identity bound to either a candidate or accepted revision. Mutable result fields record `pending|ready|failed`, checksum, relative output location and safe error code. A ready row is reusable only if its file exists inside the configured artifact root and the bytes hash to the stored checksum.

Retries never rewrite a failed identity. They create a new row with `retry_index` and `retry_of` in options. This lets, for example, a PDF renderer fail while Fountain/FDX/review artifacts remain ready and allows only PDF to retry later.

`FountRun.progress/3` exposes safe approval-attempt, delivery, usage and provider status metadata while omitting provider response bodies and approval payload bodies.
