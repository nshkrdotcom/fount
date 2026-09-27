# Capabilities B: Audience, Sequence, Dialogue, Setup / Payoff

Phase 7 installs capability families 5–8 from the Fount product plan. They are analysis capabilities for a screenplay writer, not quality scores and not page-generation workflows.

The four installed family ids are:

- `audience_reader_experience`
- `sequence_movement`
- `dialogue_interaction`
- `setup_payoff_motifs`

They are available through `Fount.Intelligence.run_capability/5` and the writer-facing playbooks `suspense_audit`, `sequence_momentum`, `dialogue_pass`, and `setup_payoff`. The dialogue playbook also composes the already-installed `relationship_dynamics` family so exchange tactics can be read beside trust/leverage/status movement without duplicating that Phase-6 logic.

## Audience / Reader Experience

`audience_reader_experience` combines two deliberately separate sources:

1. exact selected screenplay excerpts measured through the closed `audience.reader_experience` Observe lens; and
2. optional `reader_events` reduced by the existing strict-forward `Fount.Intelligence.Reader`.

Reader events are never synthesized inside the pure capability. If they are supplied, `Reader.reduce/3` validates every presentation point and evidence pointer, rejects future evidence at an earlier checkpoint, and produces question, expectation, promise, threat, suspense, curiosity, surprise, comprehension-risk, and forward-pull state in first-exposure order.

If `reader_events` are omitted, the family still returns excerpt measurements but reports partial Reader coverage. It does not invent a first-reader trajectory from later pages.

## Sequence Movement

`sequence_movement` reports scene-by-scene movement components rather than one momentum number. It keeps objective progress, constraint/stakes escalation, knowledge change, relationship change, choice change, tactic shift, reversal, local outcome, and handoff evidence inspectable.

The result contains both:

- `Temporal.sequence_view(..., ordering: :presentation)` for reader-visible order; and
- `Temporal.sequence_view(..., ordering: :story_time)` for the partial diegetic relation graph.

A flashback, intercut, or non-linear reveal is therefore not silently treated as chronological adjacency.

## Dialogue Interaction

`dialogue_interaction` measures adjacent canonical dialogue turns when the selected material contains character cues and dialogue. The shell derives turn pairs from Fount's canonical element stream, preserves exact cue/dialogue evidence, and sends each pair through the closed `dialogue.exchange` lens.

The result separates:

- response/evasion/redirect/attack/bargain behavior;
- reveal/conceal and knowledge asymmetry;
- subtext;
- exposition and whether exposition also performs dramatic work;
- tactic shifts;
- status/leverage transactions;
- repetition;
- voice-distinction evidence; and
- whether the exchange changes knowledge, goal, relationship, status, pressure, commitment, or available action.

### Typed dialogue context

The lens accepts only these optional neutral Observe slots:

- `known_facts`: list of `fact`
- `speaker_beliefs`: list of `belief`
- `relationship_state`: `relation_summary`
- `prior_turns`: list of `turn`

Use `dialogue_context` for shared slots or `dialogue_context_by_scene` for scene-specific additions. `Fount.Intelligence.Acquisition.ContextBuilder.validate/2` validates the slots against the installed lens before provider dispatch. Unknown keys, executable values, and Intelligence structs are rejected rather than silently serialized.

## Setup / Payoff and Motifs

`setup_payoff_motifs` composes the existing `Temporal.setup_payoff_ledger/2`, frozen commitments, typed causal edges, motif records, and excerpt measurements.

It can represent setup, reinforcement, transformation, payoff, subversion, deliberate abandonment, unsupported-payoff candidates, open setups, motif callbacks, motif-function changes, and revision-chain break candidates.

For each recorded payoff edge where both events are known, the capability reports presentation relation and story-time relation separately. This matters for a common screenplay case: a clue is planted in the first presented scene and explained by a flashback shown later even though the payoff/explanation event occurred earlier in diegetic time.

## Writer control and claim limits

These capabilities produce evidence, derived state, trajectories, diagnoses, uncertainty, and next investigations. They do not generate replacement pages, accept edits, or turn a diagnosis into canon. Workshop remains the owner of candidate writing, review, acceptance, recovery, and rendering.

A diagnosis such as repeated sequence function, exposition without dramatic work, weak handoff, open setup, or voice interchangeability is a source-grounded hypothesis for writer inspection. Intentional stillness, repetition, exposition, prediction, ambiguity, subversion, or unresolved setup can all be valid choices.

## Source-delivery verification state

This Phase-7 source delivery was inspected and source-level checks were run in an environment without Elixir/Erlang/Mix. Elixir formatting, compilation, ExUnit, Dialyzer, package builds, database integration, and live-provider verification were **not run here** and are not claimed. The optional human/domain usefulness review was also not run and remains validation debt under D046.

The user applies and commits the overlay. Codex must start from that applied state, format, compile, run the focused Phase-7 tests and the full repository QC/preservation gates, repair any failures in Phase 7, record actual runtime evidence in the docset, and stop before Phase 8. Phase 8 families are not implemented by this delivery.
