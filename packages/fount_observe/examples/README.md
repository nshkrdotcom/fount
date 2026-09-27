# Observe examples

Run `mix run examples/sandbox.exs` from `packages/fount_observe` after dependency setup. It prints a real Observe batch from fixed synthetic fixture answers, including source references and measurement/observation identities. It needs no credentials, database or live service. Execution is pending runtime QC.

For a live measurement use the same request/question and replace Sandbox with `Fount.Observe.provider/1` as shown in [usage](../guides/usage.md). Do not send a private screenplay without its owner's authorization.

## Phase 2 examples

From this package directory:

```bash
mix run examples/phase_two.exs
mix run examples/fixture_file.exs
```

The first returns a scene-question packet, verifies private-note exclusion and
source preservation, and shows an unavailable-provider packet. The second loads
the installed, input-bound JSON fixture through the public loader. Neither uses
credentials or a database. Both still require runtime execution by Codex.

The separate `live.exs` sends one synthetic scene with noul, ordered choice and
score questions. It is disabled unless `FOUNT_OBSERVE_LIVE=1`. Configure
`FOUNT_OBSERVE_ENDPOINT_KIND` (`typesafe` or `endpoint`) and optional
`FOUNT_OBSERVE_API_KEY`, `FOUNT_OBSERVE_BASE_URL`, `FOUNT_OBSERVE_MODEL`. A generic
endpoint may be keyless. Defaults are resolved by the actual SDK, not hardcoded
provider/model guesses. No key is printed. Authorize live use before running:

```bash
FOUNT_OBSERVE_LIVE=1 mix run examples/live.exs
```

This path has one request, retries disabled, a 16 KiB wire cap and a 30-second
acquisition cap. Record actual model/request/resource metadata and failures; a
synthetic fixture is not a substitute for this live check.
