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

Pure interpretation lives in `StoryWorld`, `Reader` and `Capabilities`. Acquisition, playbooks, reporting and persistence are explicit shell responsibilities. The [architecture guide](guides/architecture.md) describes the enforced rules and their limits. Phase 3 implements only the pure StoryWorld portion of the larger temporal program. Forward Reader state, diagnosis, capability expansion and revision strategy remain later phases and are not claimed here.

The Phase 3 Elixir source/tests are written but unexecuted in this offline delivery. See [verification](guides/verification.md); Codex must compile, test and repair this same phase, and the required human structural/factual pilot must be recorded before Phase 3 can be marked COMPLETE.

## License

[MIT](LICENSE) - Copyright (c) 2026 nshkrdotcom.
## Phase 3: story-world reference core

`Fount.Intelligence.StoryWorld` now provides the pure narrative reference layer used before later reader-state and diagnosis phases. Give it the canonical screenplay revision plus frozen Observe observations and it keeps presentation order, partial diegetic story time, causality and reality scope separate. Writers can ask what state is established at a particular event, inspect contradictory or ambiguous chronology, trace causal support, and see exact source evidence without turning scene order into fictional chronology.

See [Story-world reference core](guides/story-world.md) and `mix run examples/phase_three.exs`. This phase adds no provider or repository call to the pure core; System One remains behind Observe and completion remains a Workshop/Inference responsibility.
