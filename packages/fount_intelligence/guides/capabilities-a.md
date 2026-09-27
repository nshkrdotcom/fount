# Phase 6 capabilities A: scene, agency, character, relationship

Phase 6 turns the generic Phase-5 diagnosis shell into screenplay-specific analysis for four capability families without moving creative acceptance or page generation out of Workshop.

The public entry points are:

```elixir
Fount.Intelligence.capability_families()
Fount.Intelligence.preflight_capability(screenplay, family, request)
Fount.Intelligence.run_capability(screenplay, family, request, %{observe: provider})
Fount.Intelligence.preflight_capability_playbook(screenplay, playbook, request)
Fount.Intelligence.run_capability_playbook(screenplay, playbook, request, %{observe: provider})
```

Installed families are `scene_engine`, `agency_causality`, `character_trajectory`, and `relationship_dynamics`. Phase-6 playbook packets are available for `scene_doctor`, `character_trajectory`, and `relationship_pass`. They return analysis only; `candidate` stays `nil`.

## Why exact screenplay text is part of measurement state

Observe keeps target/evidence/provenance outside semantic provider input so those envelopes do not silently alter a reusable measurement. For these screenplay capabilities, the model must still see the words it is judging. `CapabilityRunner` therefore copies the selected exact excerpts into each scene-level measurement `state.source` while attaching those same excerpts as current-revision evidence. A response can be traced back to exact source, and the source actually participated in the measurement.

Selections are grouped by canonical scene and measured independently. Host limits can cap scenes or fragments per scene; reaching a cap marks the result partial rather than pretending the whole selection was inspected.

## Frozen StoryWorld input

A capability request may carry `story_world_records` previously produced by source-grounded extraction or trusted host code. The shell recompiles those records against the current screenplay revision and selected evidence before pure reasoning. Missing records stay unknown.

```elixir
request = %{
  "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene_id}]},
  "subject" => %{"scene_id" => scene_id},
  "story_world_records" => records,
  "intent" => %{"desired_effect" => "the bargain tightens without making Mara openly hostile"}
}
```

Callers that already use `extract_story` can pass its validated `data["records"]` into this field. Phase 6 does not add a second hidden extraction path or a direct Inference/ASM dependency.

## 1. Scene Engine

The Scene Engine measures and reasons about objective, opposition, stakes, urgency, tactic, tactic shift, reveal, decision, consequence, value delta, relationship delta, and possible later-entry/earlier-exit opportunities. Frozen beats, goals, state transitions, causal edges, interactions, and counterfactual support are kept alongside those measurements.

Diagnoses are candidates, not formulas: unclear objective, weak/unclear consequence, repeated tactic, static state, entry/exit economy, unsupported turn, and locally-functional-but-potentially-redundant scene. Intentional stillness, repetition, or long entrances/exits remain legal choices.

## 2. Agency and Causality

Agency never treats scene order as causality. Explicit StoryWorld edges build decision → action → consequence chains, causal reach, alternate support, and removal-support packets. Measurements cover initiating choice, active goal pursuit, motive/knowledge/relationship support, reactive behavior, delayed consequence, and removal impact.

The system only emits an agency-intent mismatch when the request itself declares an intended agency mode. A reactive protagonist is not automatically a defect.

## 3. Character Trajectory

Character analysis keeps goals, beliefs/knowledge assertions, commitments, state changes, relationship movement, decisions, and measured scene-by-scene changes distinct. It exposes both:

- reader-visible trajectory in screenplay presentation order; and
- diegetic state-change relationships based only on explicit StoryWorld story-time constraints.

A later-presented flashback can therefore precede a present-day relationship or belief state without creating a false regression. Arc patterns are hypotheses only. Steadfast, tragic, corruption, revelation, cyclical, ensemble, deliberately static, mixed, and unclear shapes are all allowed; transformation is never required.

## 4. Relationship Dynamics

Relationship analysis tracks directional state for trust, intimacy, allegiance, leverage, status, dependency, attraction, resentment, obligation, concealment, and knowledge asymmetry. `Mara -> Dan` and `Dan -> Mara` remain separate. Interaction events, transition points, commitments, preparation/payoff support, and non-linear presentation are all inspectable.

Possible diagnoses include long stasis, unsupported reversal, repetitive negotiation, missing consequence, and underprepared betrayal/payoff. They remain hypotheses with limitations and exact evidence.

## Writer-playbook use

| Phase-6 family | Writer-facing playbook | Existing Workshop action after the writer chooses a strategy |
| --- | --- | --- |
| Scene Engine | `scene_doctor` | `FountWorkshop.TargetedRewrite.propose/4`, `FountWorkshop.SequenceRebuild.propose/5`, or `FountWorkshop.Pass.propose/6` |
| Agency / Causality | `character_trajectory` | writer-selected targeted/sequence change; Phase 6 itself does not generate it |
| Character Trajectory | `character_trajectory` | `FountWorkshop.CharacterRewrite.propose/5` or `FountWorkshop.Pass.propose/6` |
| Relationship Dynamics | `relationship_pass` | `FountWorkshop.TargetedRewrite.propose/4`, `FountWorkshop.CharacterRewrite.propose/5`, or a writer-directed pass |

This is a usefulness map, not Phase-9 integration. No Phase-6 module calls Workshop or Inference directly.

## Resource and validation limits

Preflight reports selected scenes, semantic input sizes, question count, provider-request estimate, and caps without dispatching. Execution records actual acquisition usage from Observe. Hosted cost remains `nil` unless a runtime reports it.

The delivery includes deterministic synthetic screenplay fixtures, non-linear story-time cases, Sandbox playbook coverage, and source checks. In the offline source-writing environment used to produce the overlay, Elixir/Erlang/Mix were unavailable, so formatter/compile/ExUnit/full-CI results are not claimed. Human usefulness/domain review is optional validation debt under D046 unless actually performed.
