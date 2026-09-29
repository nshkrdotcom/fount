# Control, approval and delivery

## Trusted runtime construction

Construct `FountRun.ActorContext` only after host authentication. Register agent/service approvers explicitly in that trusted context. Human owner identity is always allowed for its own run; arbitrary human identities cannot be injected through input JSON.

For `FountRun.step/4`, pass trusted services such as:

```elixir
services = %{
  actor_context: owner_context,
  inference: inference_client,
  observe: observe_provider,
  approval_context: configured_approver_context,
  approval_callback: &MyReviewer.review/1,
  approval_reconciler: &MyReviewer.reconcile/2
}

FountRun.step(MyRepo, run_id, services)
```

Only the closed service-key set is accepted. `:observe` is host-owned and optional; Run passes it to Workshop without importing or constructing System One SDK types. Observe-backed Run sessions enable the existing durable Intelligence path under a deterministic screenplay privacy namespace. Provider objects and credentials are never copied into Run claims, plans, step results, or candidate metadata. With no Observe service, analysis remains explicit `not_run` rather than being treated as semantic success. The reconciler is used for a previously dispatched reviewer call whose durable outcome is unknown; it receives the existing callback operation id and packet and must not trigger a second original review operation.

Run progress projects only analysis identity/status required by a host: writer/revision packet IDs, durable analysis-run IDs, source revision, playbook/status, limited acquisition counters, and Run-level inference/measurement limits/consumption. Full semantic packets remain in Workshop/Intelligence provenance and durable analysis storage. `check` remains store-only and reuses the candidate's persisted Revision Intelligence; it never invokes Observe merely because a check step starts. Required deterministic scope/protected-material checks continue to control iteration separately from advisory semantic checks.

Measurement admission is global to the Run lineage and survives lease reclaim. Durable Observe cache hits may avoid a new measurement reservation only when the existing fingerprint contract proves the result reusable. Immutable Sandbox fixtures are used for deterministic cache tests. A newly constructed System One provider is not assumed to hit a prior durable cache while its current identity remains session-bearing, and the runtime does not claim exactly-once remote dispatch across a crash before a response is durably recorded.

## Exact writer approval

Get progress/decisions, render the exact decision to the writer, then submit its bindings unchanged:

```json
{
  "decision_id": "...",
  "context_fingerprint": "...",
  "plan_version": 3,
  "policy_version": 2,
  "findings": [],
  "overrides": []
}
```

`FountRun.approve_run/4` always means choice `approve`. To reject or replace, call `submit_decision/4` with the decision id. Replacement additionally supplies `replacement_fountain` and becomes a new candidate followed by a fresh check.

## Plan and policy steering

A public plan/policy update is a complete effective snapshot, not a patch. Both require:

```elixir
FountRun.update_plan(repo, run_id, full_plan, context,
  expected_version: 3,
  command_id: "writer-plan-2026-09-29T0402Z"
)
```

The same command id may be retried only with the same expected version and payload. New limits are therefore explicit history; no hidden reset occurs.

## CLI examples

```text
mix fount.run start --input run.json
mix fount.run show RUN_ID
mix fount.run step RUN_ID
mix fount.run decisions RUN_ID
mix fount.run decide DECISION_ID --input response.json
mix fount.run plan RUN_ID --input full-plan.json --expected-version 2 --command-id plan-2
mix fount.run pause RUN_ID
mix fount.run resume RUN_ID
mix fount.run stop RUN_ID
mix fount.run policy RUN_ID --input full-policy.json --expected-version 2 --command-id policy-2
mix fount.run approve RUN_ID --input exact-approval.json
mix fount.run export RUN_ID --destination deliveries/run-123 --pdf --table-read
```

CLI runtime configuration comes from the host application (`config :fount_run, :cli, ...`), not the command document. Exit codes are 2 usage/input, 3 trusted config/auth, 4 conflict/stale/fenced state, 5 execution/runtime.

## Export truthfulness

Without `--pdf`, the standard bundle does not invoke a PDF runtime. With `--pdf`, Workshop's configured PDF exporter is called and its result gets an independent delivery row. A PDF failure leaves a partial manifest and a failed PDF row while already-written formats stay ready. The next identical export reuses checksum-valid ready files and creates a retry identity only for failed/missing formats.
