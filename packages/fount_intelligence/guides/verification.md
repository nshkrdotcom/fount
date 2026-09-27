# Verification

This delivery did not run Elixir, Mix, PostgreSQL, hosted providers, PDF rendering or speech. The source contains tests for Codex to execute and repair. Do not interpret an offline source/ZIP check as runtime success.

From the repository root, configure the actual SDK source if needed, then use `mix setup`, `mix test`, and `mix fount.architecture`. Package-local checks are `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, `mix credo --strict`, `mix dialyzer`, `mix docs --warnings-as-errors`, and `mix hex.build` where package assets are present. Runtime QC must inspect lockfile changes rather than copy invented dependency hashes.

The architecture task checks source ASTs and compiled dependencies; its `--source-only` result is explicitly weaker. All four packages must have been compiled for a complete gate. The source gate rejects leftover removed-package files as well as package dependencies.

The Phase 1 QC handoff supplies the complete ladder, source-input caveat, writer demonstration, database/PDF prerequisites, preservation audit and exit criteria. Live checks require explicit authorization, actual credentials, small synthetic/authorized inputs, and recorded results. A fixture is not a live verification or human evaluation.
