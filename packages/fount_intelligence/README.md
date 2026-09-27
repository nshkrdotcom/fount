<p align="center"><img src="assets/fount_intelligence.svg" alt="Fount Intelligence" width="200" height="200"/></p>

# Fount Intelligence

**Investigate a screenplay problem before deciding how to rewrite it.**

Inspect when information becomes available, what a character can know, whether a reaction relies on unavailable knowledge, which later events depend on an earlier setup, and what a proposed edit changes. Compare dialogue and voice without treating every repeated phrase as a defect. Keep exact evidence, uncertain interpretation and missing measurements separate.

The package preserves sixteen read-only inspection intents: inventory, extraction, search, constraints, knowledge trace, reveal boundary, dependencies, continuity, scene mechanics, dialogue, voice, action, comparison, scene lift, ablation and strategy contrast. Use `Fount.Intelligence.playbooks/0` for the installed schemas. A complete report means acquisition completed for the declared scope, not that an interpretation is true or that a screenplay is good.

## Start without a provider

From this package run `mix run examples/inspect.exs`. It uses canonical inventory and exact evidence without a model or database. [Usage](guides/usage.md) shows request, provider and Workshop composition boundaries.

## Writing stays in Workshop

Intelligence never accepts screenplay changes. Proposed fact extraction and investigation explanations use an explicit host-owned proposal service; Workshop supplies its Inference implementation. PDF layout is likewise an explicit Workshop service. Actual alternate pages, candidate storage, review, acceptance, recovery and rendering remain in `fount_workshop`.

## Architecture and verification

Pure interpretation lives in `StoryWorld`, `Temporal`, `Reader` and `Capabilities`. Acquisition, playbooks, reporting and persistence are explicit shell responsibilities. The [architecture guide](guides/architecture.md) describes the enforced rules and their limits.

Phase 4 provides qualified temporal views and a strict forward-only Reader reducer. Phase 5 adds pure evidence-composed diagnosis plus a multi-pass shell that measures selected evidence, returns explicit evidence needs, converts rich state into closed Observe context, measures support/counterevidence, and emits a writer-facing result packet. The ten baseline writer playbooks are available through `Fount.Intelligence.writer_playbooks/0`; see [Diagnosis and multi-pass writer playbooks](guides/diagnosis-and-playbooks.md) and `mix run examples/phase_five.exs`.

Phase 6 adds source-grounded Scene Engine, Agency/Causality, Character Trajectory, and Relationship Dynamics capabilities through `Fount.Intelligence.run_capability/5`, plus Scene Doctor, Character Trajectory, and Relationship Pass packet integrations through `run_capability_playbook/5`. Character and relationship views keep reader-visible presentation order separate from explicit diegetic story time, and no transformation arc is required. See [Capabilities A](guides/capabilities-a.md) and `mix run examples/phase_six.exs`.

The Phase 6 source/tests/example in this delivery are written against the supplied post-Phase-5 snapshot but are not runtime-verified in this source-writing environment because Elixir/Erlang/Mix are unavailable here. Codex must format, compile, test and repair this same phase after the overlay is applied. Optional human/domain review remains validation debt unless actually performed. Phase 7 is not included.

## License

[MIT](LICENSE) - Copyright (c) 2026 nshkrdotcom.

## Story-world reference core

`Fount.Intelligence.StoryWorld` remains the Phase-3 pure narrative reference layer underneath Phase 4. It keeps presentation points, partial diegetic story time, causality, scope and exact evidence separate. Phase 4 consumes those records without changing their meaning or introducing provider/database calls into the pure core.