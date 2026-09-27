# Diagnosis and multi-pass writer playbooks

Phase 5 adds a writer-facing diagnosis shell without moving provider, database, or generation effects into the pure reasoning core.

## What a writer gets

The shell is useful when the writer has a concrete concern such as:

- "the interrogation loses pressure after the first reversal";
- "these three scenes feel like the same scene";
- "the note says the protagonist feels passive, but I do not want to make her louder";
- "this revision fixed the reveal but may have flattened the relationship".

A run starts from the writer concern, exact screenplay evidence, and one or more competing hypotheses. It then keeps four things separate:

1. source evidence and explicit writer intent;
2. derived narrative/reader state supplied as closed Observe context;
3. diagnoses with support, counterevidence, uncertainty, alternatives, and protected strengths;
4. optional strategy classes. Actual replacement pages remain Workshop candidates and are never silently accepted.

There is no universal screenplay-quality score.

## Public API

```elixir
playbooks = Fount.Intelligence.writer_playbooks()

{:ok, preflight} =
  Fount.Intelligence.preflight_playbook(model, "scene_doctor", request,
    max_playbook_provider_requests: 40,
    max_measurement_states: 40
  )

{:ok, packet} =
  Fount.Intelligence.run_playbook(
    model,
    "scene_doctor",
    request,
    %{observe: observe_provider},
    max_playbook_provider_requests: 40,
    max_measurement_states: 40
  )

{:ok, markdown} = Fount.Intelligence.render_packet(packet, :markdown)
```

The host supplies the Observe provider. `fount_intelligence` does not import System One SDK, Inference, or ASM. System One stays behind `fount_observe`; generation stays in Workshop/Inference.

## Request shape

The minimum request is a writer concern plus at least one explicit hypothesis:

```elixir
%{
  "concern" => %{
    "statement" => "The interrogation loses pressure after the first reversal.",
    "desired_effect" => "sustained entrapment without making Mara overtly aggressive",
    "protected_strengths" => ["Mara remains restrained"]
  },
  "selection" => %{"scene_ids" => [scene_id]},
  "hypotheses" => [
    %{
      "code" => "repeated_tactic",
      "hypothesis" => "The exchange stops changing tactic or leverage.",
      "alternatives" => ["The stillness may be intentional entrapment."],
      "context" => %{}
    }
  ]
}
```

Hypotheses are not silently invented by the pure core. A host or earlier investigation can supply them. If an assessment is absent, `Fount.Intelligence.Diagnosis` returns an explicit evidence requirement rather than a forced conclusion.

## The four passes

A writer-playbook run uses the following shell sequence:

```text
selected screenplay evidence
  -> Observe: concern-relevance measurements
  -> pure Diagnosis: explicit evidence needs
  -> Acquisition.ContextBuilder: plain state -> closed Observe Context
  -> Observe: support + counterevidence measurements
  -> pure Diagnosis: diagnoses / abstentions / next investigations
  -> WriterPacket
```

The first measurement never removes evidence from the second pass. It becomes an explicit model-estimated context signal, avoiding a false-negative gate from an uncalibrated model.

## Context inversion

`Fount.Intelligence.Acquisition.ContextBuilder` loads the installed lens contract, rejects `Fount.Intelligence.*` structs, converts only plain data, and delegates decoding/validation to `Fount.Observe.Context.from_map/2`.

The Phase-5 contextual lens requires a literal writer `concern` and permits only these optional slots:

- `known_facts` — list of Observe `fact` primitives;
- `speaker_beliefs` — list of Observe `belief` primitives;
- `relationship_state` — one Observe `relation_summary` primitive;
- `base_assessments` — list of plain JSON literals produced by the preceding measurement pass.

Unknown slots fail before the writer-playbook run dispatches any provider request because `run_playbook/5` performs the complete preflight first.

## The ten baseline writer playbooks

Phase 5 registers these shells:

- Scene Doctor
- Dialogue Pass
- Character Trajectory
- Relationship Pass
- Suspense Audit
- Sequence Momentum
- Setup / Payoff
- Notes Diagnosis
- Submission Read
- Revision Regression

They share the Phase-5 diagnosis engine and advertise their existing foundational inspection tools plus the later capability families that will deepen them. This phase does **not** implement the Phase-6–8 capability-family semantics early.

## Resource behavior

Preflight reports target counts, initial provider-request estimates, configured caps, and an explicit `nil` hosted cost when no provider cost can be known. It does not reserve the Observe budget or call a provider.

Execution shares one `Fount.Observe.Budget` across passes. `max_playbook_provider_requests` limits initial dispatch across the two passes; `max_evidence_fragments` limits source material admitted to one run. If acquisition is skipped because a cap is exhausted or the selected source exceeds the host evidence limit, the packet is `partial`; skipped request IDs and the evidence-scope truncation flag remain visible. Missing evidence stays an investigation requirement. Unknown provider cost is never rendered as zero.

## Deterministic Sandbox

`mix run examples/phase_five.exs` creates fixtures from the actual selected evidence IDs and runs the full multi-pass shell with `Fount.Observe.Sandbox`. A fixed `run_id` makes the observation lineage reproducible. No network, database, or hosted provider is involved.

## Writer packet

`Fount.Intelligence.Reporting.WriterPacket` follows the presentation contract: concern, scope, intended experience, concise finding, evidence, derived state/trajectory, diagnoses and abstentions, counterevidence/alternatives, uncertainty/missing evidence, protected strengths, next investigations, strategies, revision comparison, resources, errors, and limitations have separate fields. `candidate` remains `nil` in Intelligence. Workshop owns concrete generated pages.

The reference renderer supports deterministic Markdown and canonical JSON. It is an interaction contract, not a GUI implementation.

## Current validation status

The Phase-5 source in the offline delivery was written against the supplied post-Phase-4 snapshots. The source-writing environment did not contain Elixir/Erlang/Mix, so compile, ExUnit, Credo, Dialyzer, ExDoc, package, integration, live-provider, and human-review claims must come from the Codex QC pass after the overlay is applied. The optional diagnosis/usefulness pilot remains validation debt unless actually performed.

No human usefulness or reader-agreement claim is made by this offline implementation or its deterministic fixtures.
