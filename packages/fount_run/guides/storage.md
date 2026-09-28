# Run storage

Run migrations are separate from Core migrations and must be run second on the same Repo/database. `FountRun.migrations_path/0` exposes the directory.

Tables are prefixed `fount_run_`: runs, plans, policies, steps, attempts, events, decisions, approval attempts, usage and deliveries. Composite FKs retain screenplay/run identity; plan/policy bindings retain the exact historical version used by later work. There are no cascade deletes from Run into canonical Core records.

`start_run` creates version-1 plan/policy snapshots in one transaction and emits `run_started`. Reusing the owner/client idempotency key with the same normalized input returns the original row; changed content conflicts. Read/list are restricted to the screenplay and owner carried by trusted actor context.

Public persistence primitives can append snapshots/events, persist/resolve a decision once, retain immutable received approval material, reserve/settle usage once, and create durable delivery identities. They do not implement worker policy or canonical acceptance. Runtime PostgreSQL integration is required before Phase 02 can be certified.
