# FountRun

> **Current workspace status:** FountRun remains the headless durable orchestration boundary. The six-phase Run program is already complete; System One reintegration Phases 01 and 02 are runtime-certified, while Phase 03 host integration is implemented; runtime QC and final certification are recorded in the operational docset. The Phoenix host remains `apps/fount_web`; it supplies authenticated identity, Repo/services and supervision without moving Run state, System One SDK types, or approval semantics into Run/LiveView.

> **System One Run reintegration:** the first-party host now constructs an Observe provider and passes it through the existing `:observe` service key. Run remains provider-neutral: it does not depend on, import, construct, persist or call native System One SDK types. Deterministic host acceptance uses Sandbox; configured production uses the Observe provider factory; explicit host compatibility mode omits Observe and therefore leaves analysis `not_run`.

FountRun is the durable orchestration layer for controlled Fount work. Phase 05 completes the **headless** screenplay product: the Phase 04 intake/investigate/plan/write/check pipeline is followed by exact steering and approval decisions, plan/policy updates, pause/resume/stop, stale-base rebase, canonical acceptance through Core, candidate-only completion, and durable exports.

Phase 06 owns the web application. Nothing in FountRun starts Phoenix/LiveView or trusts browser/request JSON with Repo modules, identities, provider clients, credentials, or artifact roots.

## Shared Repo and migration order

The host owns the Ecto Repo. Run and Workshop use the same PostgreSQL database as Core; no second storage system is started.

```elixir
Ecto.Migrator.run(MyRepo, Fount.Persistence.migrations_path(), :up, all: true)
Ecto.Migrator.run(MyRepo, FountRun.migrations_path(), :up, all: true)
```

Phase 05 adds exact command replay identity for plan/policy updates and parent approval-attempt lineage. Historical rows remain immutable.

## Public headless API

The writer-facing Run surface is:

```elixir
FountRun.start_run(repo, attrs, actor_context, opts \\ [])
FountRun.get_run(repo, run_id, actor_context)
FountRun.list_runs(repo, filter, actor_context)
FountRun.step(repo, run_id, services, opts \\ [])
FountRun.submit_decision(repo, decision_id, response, actor_context)
FountRun.update_plan(repo, run_id, plan, actor_context, opts \\ [])
FountRun.update_policy(repo, run_id, policy, actor_context, opts \\ [])
FountRun.pause_run(repo, run_id, actor_context)
FountRun.resume_run(repo, run_id, actor_context)
FountRun.stop_run(repo, run_id, actor_context)
FountRun.approve_run(repo, run_id, exact_response, actor_context)
FountRun.deliver(repo, run_id, destination, actor_context, opts \\ [])
```

`approve_run/4` is only a convenience wrapper over the exact persisted final-approval decision. It requires the decision id, context fingerprint, plan version, and policy version and then delegates to the same `submit_decision` implementation. It never chooses “the pending approval” implicitly.

`step/4` accepts a trusted services map containing `:actor_context` and closed service keys. `:observe` is an optional trusted provider service alongside `:inference`; Run never constructs System One SDK clients or native SDK questions. When Observe is supplied, Run preserves it through Workshop, enables Workshop/Intelligence durable analysis with a screenplay-derived privacy namespace, and keeps analysis advisory. Without Observe, generation remains compatible and analysis stays explicitly `not_run`. The older explicit `%ActorContext{}` call form remains valid for workers and forwards the same trusted keyword services. An actor string is not a writable compatibility path.

Observe-backed semantic work uses the existing Run `measurement_states` reservation ledger. Durable cache hits are resolved by Intelligence/Observe before new measurement admission, so a valid hit does not spend a new Run measurement state; a miss reserves through Run and remains charged across worker restart. `progress/3` exposes a safe `resources` summary and an `analysis` lineage projection containing packet/analysis-run IDs, status and limited resource counters. It deliberately does not copy evidence, diagnoses, prompts, provider handles or native System One payloads into Run state.

Durable cache reuse is only as strong as the provider fingerprint. The deterministic Sandbox provider has an immutable fingerprint and is suitable for replay/cache acceptance tests. The current System One provider identity includes a session component when its model identity is not stable enough for durable reuse, so constructing a fresh System One provider must not be treated as proof of a cross-session cache hit. Likewise, a process crash after remote dispatch but before durable persistence is not an exactly-once guarantee; Run recovers by bounded/fenced replay and keeps ambiguous provider outcomes explicit.

## Completion and acceptance

A checked candidate is revalidated against the current plan/policy/head before completion. Candidate-only policy completes without moving canonical head. Accepting policy creates either an exact human final-approval decision or a durable agent/service approval attempt.

Automated approval records callback intent before dispatch, persists the exact review before constructing an approval, saves a stable approval id/payload before Core acceptance, and rechecks authorization/fencing immediately before acceptance. Core remains the only canonical acceptance implementation. A failed/ambiguous callback, plan/policy change, pause/stop, or stale head cannot silently advance canon.

A stale canonical head opens an explicit rebase decision. Rebase creates a linked successor run/candidate and requires fresh checks; it does not mutate an already reviewed candidate. Writer replacement Fountain likewise becomes a new candidate and returns to `check`.

## Delivery

`FountRun.deliver/5` writes under a host-configured artifact root. Standard bundles include Fountain, FDX, exact review JSON, review Markdown, source diff, structural diff, resource/check summary, provenance, and a manifest written last. PDF and table-read JSON/HTML are optional and use the existing Workshop exporters when requested.

Every format has an immutable durable delivery row and checksum. A ready file is reused only when the bytes still match its recorded digest. Failed or missing formats retry independently with a new delivery identity. Candidate-only exports are labeled as candidates; accepted exports bind the stored accepted revision even if canonical head later moves.

## CLI

`mix fount.run` exposes `start`, `show`, `step`, `decisions`, `decide`, `plan`, `pause`, `resume`, `stop`, `policy`, `approve`, and `export`.

The host configures trusted runtime objects, for example:

```elixir
config :fount_run, :cli,
  repo: MyApp.Repo,
  actor_context: trusted_actor_context,
  services: %{inference: inference_client, observe: observe_provider},
  artifact_root: "/srv/fount/artifacts",
  step_options: [lease_ms: 30_000],
  pdf_options: []
```

Command JSON contains only work data. `plan` and `policy` require `--expected-version` and `--command-id`. `approve` requires an exact approval response JSON. `export` accepts a relative destination under the configured root and optional `--pdf` / `--table-read`.

CLI exit classes are stable: `2` usage/input, `3` trusted runtime/auth configuration, `4` conflict/stale/fenced control state, and `5` execution/runtime failure. Success is `0`.

See `guides/architecture.md`, `guides/storage.md`, and `guides/control-and-delivery.md`.

## Phase 06 host integration

The repository now includes the one-owner Phoenix LiveView host at `apps/fount_web`. FountRun remains headless and has no Phoenix dependency. The host starts the shared `Fount.Repo`, runs migrations in Core -> Run -> host order, derives trusted `ActorContext` values from its signed owner session, supervises `FountRun.Worker` processes, and renders durable `FountRun.progress/3` state. Browser forms submit exact decision bindings but never principal or Repo/provider objects. Delivery destinations and artifact roots remain server configuration.
