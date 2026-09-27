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

Pure interpretation lives in `StoryWorld`, `Reader` and `Capabilities`. Acquisition, playbooks, reporting and persistence are explicit shell responsibilities. The [architecture guide](guides/architecture.md) describes the enforced rules and their limits. The full expanded temporal/diagnosis/capability program belongs to later phases and is not claimed here.

Phase 1 Elixir source/tests are written but unexecuted in this delivery. See [verification](guides/verification.md); Codex must compile, test, repair and close this same phase before the next starts.

## License

[MIT](LICENSE) - Copyright (c) 2026 nshkrdotcom.
