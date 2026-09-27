# Temporal views and the forward Reader

Phase 4 adds two pure writer-facing views that deliberately answer different questions.

`Fount.Intelligence.Temporal` asks what is established **inside the story** at an event, under partial diegetic chronology. `Fount.Intelligence.Reader` asks what a first-time reader can carry **through screenplay presentation order** at a visible checkpoint. Moving a reveal may change Reader state without changing the event's diegetic date; inserting a flashback may change interpretation without creating an impossible chronology.

Neither module acquires measurements, calls a provider, opens a repository, reads the environment, or writes screenplay pages.

## Diegetic temporal views

Temporal views are explicitly labeled `diegetic_story_time_qualified` or `diegetic_story_time_partial`.

```elixir
alias Fount.Intelligence.{StoryWorld, Temporal}

{:ok, world} = StoryWorld.compile(screenplay, observations, records: records)

Temporal.character_state(world, "Mara", "event-loading-dock")
Temporal.relationship_state(world, "Mara", "Dan", "event-loading-dock")
Temporal.knowledge_state(world, "Mara", "event-loading-dock")
Temporal.resource_state(world, "Mara", "event-loading-dock")
Temporal.setup_payoff_ledger(world)
```

Character and resource state use the existing `state_transition` records. Relationship state is directional: `%{"from" => "Mara", "to" => "Dan"}` is not silently treated as the reverse relationship. Knowledge partitions assertions only when their `epistemic_owner` and stance support that partition. Missing chronology stays unknown.

`sequence_view/3` requires the caller to choose presentation or story-time semantics:

```elixir
Temporal.sequence_view(world, event_ids, ordering: :presentation)
Temporal.sequence_view(world, event_ids, ordering: :story_time)
```

The story-time form returns pairwise partial relations. It does not force a total chronology from file order.

### Setup/payoff ledger

`setup_payoff_ledger/2` uses explicit commitment records plus typed causal `pays_off`/`resolves` links. It does not infer a payoff merely because a later scene resembles an earlier setup. Open setups therefore remain visible as open rather than being guessed complete.

### Recompute region

`Temporal.recomputation_region/2` starts with StoryWorld dependency impact and expands only through the connected story-time constraint region. This is intentionally different from Reader recomputation: diegetic state follows graph connectivity, not the screenplay suffix.

## Forward Reader

Reader consumes explicit source-backed `%Fount.Intelligence.Reader.Event{}` values. Every reader-visible event names a visible canonical presentation point and carries exact evidence from the same screenplay revision.

```elixir
alias Fount.Intelligence.Reader
alias Fount.Intelligence.Reader.Event

{:ok, event} =
  Event.new(%{
    "id" => "reveal-archive-key",
    "kind" => "reveal",
    "action" => "explicit",
    "point" => reveal_element.id,
    "key" => "archive-key",
    "claim_class" => "deterministic_derived_narrative_state",
    "data" => %{"proposition" => "The key opens the archive."},
    "evidence" => [exact_evidence],
    "dependencies" => ["reader:key-reveal"]
  })

{:ok, reader} = Reader.reduce(screenplay, [event])
```

Reader creates checkpoints only for visible performed screenplay elements. Notes, boneyards and omitted material are not checkpoints. A `visibility: "private"` event is retained only as an ignored event ID; it cannot change first-reader state. A reader-visible event aimed at hidden material is rejected.

More importantly, the reducer validates evidence order. An event at presentation point N cannot cite evidence from a later visible point. Such input returns `{:error, {:future_reader_evidence, ...}}` instead of leaking future information backward.

## Ledger tracks

The reducer currently carries these inspectable tracks:

- open questions;
- expectations;
- promises;
- threats;
- reveal state;
- reader-visible character epistemic models;
- directional relationship state;
- suspense components, without one universal score;
- curiosity;
- surprise opportunity/realization records;
- comprehension/confusion risk;
- emotional-alignment hypotheses;
- scene-to-scene forward pull.

Question actions are `open`, `reinforce`, `partial`, `resolve`, and `abandon`. Reveal actions move through explicit states such as `hinted`, `inferable`, `explicit`, `confirmed`, `complicated`, or `overturned`. Other ledgers preserve their own action histories instead of flattening everything into one tension or engagement number.

Every event also declares a claim class:

- `canonical_fact`;
- `deterministic_derived_narrative_state`;
- `model_estimated_reader_interpretation`.

Phase 4 never manufactures a human-calibrated reader-response claim. The first-reader human pilot belongs to the domain gate and must be recorded separately.

## Reader versus character knowledge

Audience knowledge and diegetic character knowledge are independent:

```elixir
Reader.knowledge_differential(
  reader,
  world,
  "Mara",
  reveal_element.id,
  "event-loading-dock"
)
```

The returned packet explicitly labels the Reader side as presentation-relative and the StoryWorld side as diegetic/story-time-qualified. A character can know something before the audience learns it, or the audience can know something the character does not.

## Trajectories and recomputation

`Reader.trajectory/3` emits a presentation-relative change trajectory for an inspectable Reader track/key. `Reader.recomputation_boundary/2` finds the earliest reader event affected by changed dependencies and returns only the presentation suffix that must be replayed. Earlier snapshots remain reusable because the forward-only invariant makes them independent of later events.

This is not persistence. Durable materialization and cross-revision cache reuse remain a later implementation phase.

## Writer-facing packet

```elixir
Reader.inspection_packet(reader)
Reader.render_markdown(reader)
Reader.render_json(reader)
```

The packet reports deterministic ledger state, explicitly labeled model estimates, ignored private events, and limitations. It is an inspection surface for a writer or a later Workshop workflow, not a verdict on screenplay quality and not a generated rewrite.
