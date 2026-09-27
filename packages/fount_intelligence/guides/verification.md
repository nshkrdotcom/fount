# Verification

This delivery did not run Elixir, Mix, PostgreSQL, hosted providers, PDF rendering or speech. The source contains tests for Codex to execute and repair. Do not interpret an offline source/ZIP check as runtime success.

From the repository root, configure the actual SDK source if needed, then use `mix setup`, `mix test`, and `mix fount.architecture`. Package-local checks are `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, `mix credo --strict`, `mix dialyzer`, `mix docs --warnings-as-errors`, and `mix hex.build` where package assets are present. Runtime QC must inspect lockfile changes rather than copy invented dependency hashes.

The architecture task checks source ASTs and compiled dependencies; its `--source-only` result is explicitly weaker. All four packages must have been compiled for a complete gate. The source gate rejects leftover removed-package files as well as package dependencies.

The Phase 4 QC handoff supplies the current Temporal/Reader ladder, source-input caveat, provider-free demonstration, preservation audit, first-reader domain-pilot debt and exit criteria. Live checks require explicit authorization, actual credentials, small synthetic/authorized inputs, and recorded results. A fixture is not a live verification or human evaluation.
## Phase 3 runtime QC

The Phase-3 source delivery adds StoryWorld compilation/query tests for non-linear time, event-qualified state, ambiguity/unknown preservation, contradiction evidence, reality-scope isolation, causal/temporal independence, deterministic replay/rendering, stale-evidence rejection, counterfactual dependency impact and pure-core architecture enforcement.

These Elixir tests and `examples/phase_three.exs` are **not run in the offline delivery environment**. Codex must execute and repair them after the overlay is applied. Phase 3 also requires the Level-A structural/factual domain pilot described by the implementation docset; that human review cannot be substituted by fixtures or source inspection and remains explicit validation debt until recorded.

## Phase 4 runtime QC

The Phase-4 source delivery adds pure Temporal and Reader tests for non-linear presentation/story-time separation, directional relationship state, resource/knowledge views, explicit setup/payoff lifecycle, future-evidence rejection, deterministic replay, private-note exclusion, Reader question lifecycle, Reader-vs-diegetic knowledge differences, presentation-suffix recomputation, and story-time connected-region recomputation.

These Elixir tests and `examples/phase_four.exs` are **not run in the offline delivery environment**. Codex must execute and repair them after the overlay is applied. The first-reader checkpoint pilot described by the implementation docset also remains a real human/domain gate; it must not be fabricated, and fixtures or model outputs cannot substitute for it.

## Phase 5 runtime QC

The Phase-5 source delivery adds tests for pure evidence needs and abstention, competing diagnoses, closed Observe context conversion, rejection of unknown slots and Intelligence structs, the exact ten-playbook registry, deterministic writer packets, a deterministic Sandbox multi-pass run, provider-request/state caps, partial coverage, and Diagnosis architecture violations.

Codex must run at least the targeted `diagnosis_test.exs`, `context_builder_test.exs`, `writer_registry_test.exs`, `writer_packet_test.exs`, `writer_runner_test.exs`, and `phase_five_architecture_test.exs`, plus the complete Intelligence/package/workspace preservation ladder. `mix run examples/phase_five.exs` is the provider-free Phase-5 demonstration.

The offline source-writing environment has no Elixir/Erlang/Mix, so none of those runtime checks is claimed here. The optional Phase-5 diagnosis/usefulness pilot is skipped by default under the current docset policy and remains visible validation debt unless actually performed.
