# Architecture

FountRun sits above Core and Workshop. Core still never imports Run. Phase 03 adds a Run → Workshop dependency because Run now executes one real Workshop operation; provider/host dependencies remain owned by Workshop and are not direct Run dependencies.

The host supplies one shared Repo and trusted `FountRun.ActorContext`. Request JSON cannot choose its own actor or owner. `FountRun.Engine.step/4` performs a short claim transaction, releases database locks, then executes the stage handler. Heartbeats and commits use fresh short transactions. External model work never runs while the Run row lock is held.

## Claims and fencing

PostgreSQL `now()` is the lease clock. Active-step assignment/reclaim is serialized under the run/step row locks. Every successful claim increments `current_fencing_token`; heartbeat, provider dispatch and completion require the current live owner/token. Core session/candidate writes receive a generic transaction-local guard that rechecks that same Run lease/fence without adding a Core → Run dependency.

The default stage registry is intentionally closed: only `write` has a real Phase 03 handler. Later stages return `{:stage_handler_unavailable, stage}` rather than being recorded as successful placeholders.

## Provider recovery

A logical provider call has durable operation identity derived from the immutable Run operation key, request fingerprint, response mode, dispatch index and transport-retry index. Run reserves inference budget and persists `intended` before dispatch, changes it to `dispatched` immediately before the call, then stores a redacted/reusable response record after return.

On restart, `succeeded` is reused. `intended` may proceed. `dispatched`/`unknown` is ambiguous and blocks replay. A late result may still reconcile the provider record and usage even after the worker has been fenced, so paid usage is not lost.

Phase 04 owns multi-stage screenplay scheduling and creative iteration. Phase 05 owns public pause/stop steering and approval/completion commands.
