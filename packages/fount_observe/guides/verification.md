# Verification

The source-writing delivery did not run Elixir or providers. The subsequent Phase 2 runtime QC did; see the docset's `handoffs/PHASE_02_RUNTIME_QC_REPORT.md` for actual commands and results. Do not interpret an offline source/ZIP check as runtime success.

From the repository root, configure the actual SDK source if needed, then use `mix setup`, `mix test`, and `mix fount.architecture`. Package-local checks are `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, `mix credo --strict`, `mix dialyzer`, `mix docs --warnings-as-errors`, and `mix hex.build` where package assets are present. Runtime QC must inspect lockfile changes rather than copy invented dependency hashes.

The architecture task checks source ASTs and compiled dependencies; its `--source-only` result is explicitly weaker. All five libraries must have been compiled for a complete gate. The source gate rejects leftover removed-package files as well as package dependencies.

The Phase 1 QC handoff supplies the complete ladder, source-input caveat, writer demonstration, database/PDF prerequisites, preservation audit and exit criteria. Live checks require explicit authorization, actual credentials, small synthetic/authorized inputs, and recorded results. A fixture is not a live verification or human evaluation.

## Phase 2 focused runtime checks

```bash
mix format
mix compile --warnings-as-errors
mix test test/phase_two_contracts_test.exs test/phase_two_execution_test.exs test/phase_two_sources_test.exs test/phase_two_provider_test.exs test/phase_two_scene_question_test.exs
mix test
mix run examples/phase_two.exs
mix run examples/fixture_file.exs
```

Then run the entire workspace's architecture/CI gates, database integrations and
preserved writer examples. The new tests include real-SDK transport stubs; they
are not live-provider calls. Explicitly authorize and run `examples/live.exs`
separately. Codex must inspect timeout cleanup, returned usage and exact source
evidence, not just an exit code. These commands were unrun in the offline
source-writing environment and executed during runtime QC.