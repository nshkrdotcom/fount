# Story-world reference core

`Fount.Intelligence.StoryWorld` turns one canonical screenplay revision plus already-frozen Observe measurements into a source-grounded narrative reference model. It is intentionally provider-free: compilation and queries do not call System One, Inference, a repository, the environment, the filesystem, a clock, or random ID generation.

The practical writer benefit is separation of questions that screenplay tools often collapse:

- **presentation** — when the screenplay shows or mentions something;
- **story time** — what can actually be established about diegetic before/after/overlap relationships;
- **causality** — what enables, causes, motivates, prevents, reveals, requires, pays off, complicates, resolves, or contradicts something else;
- **reality scope** — whether a claim belongs to the base story, recollection, dream, hypothetical, alternate, or contested material.

Scene order never becomes story chronology merely because one scene is printed before another.

## Compile from canonical source and frozen observations

```elixir
alias Fount.Intelligence.StoryWorld

{:ok, world} =
  StoryWorld.compile(screenplay, frozen_observations,
    records: story_records,
    evidence_registry: inspected_evidence
  )
```

`screenplay` must be the canonical `%Fount.Screenplay{}` for the revision named by every frozen `%Fount.Observe.Observation{}`. StoryWorld rechecks exact evidence excerpts against that revision and rejects stale/mismatched observations.

`records:` is optional replay input for interpreted state that has already been extracted or supplied by trusted host code. Every semantic record must carry exact evidence itself, cite evidence IDs from `evidence_registry:`, or originate from a frozen observation whose evidence is inherited. No record can name executable modules/functions.

## Record families

The Phase-3 compiler accepts these `record_type` values:

- `entity`, `event`, `interaction`;
- `assertion`, `goal`, `commitment`;
- `state_transition`;
- `beat`, `motif`;
- `story_time_node`, `story_time_constraint`;
- `causal_relation`;
- `scope`.

Phase-2 extraction records (`events`, `propositions`, `goals`, `knowledge_access`, `props`, `commitments`, `relationships`, `timeline`) are retained as compatible evidence-backed inputs and normalized into the richer StoryWorld families rather than discarded.

### Event-qualified state

Possession, access, injury/death, knowledge, plan/resource and relationship continuity use `state_transition` rather than screenplay scene order:

```elixir
%{
  "record_type" => "state_transition",
  "id" => "key-possession-1",
  "subject" => "brass-key",
  "attribute" => "possessor",
  "from" => nil,
  "to" => "Mara",
  "event_id" => "event-key-taken",
  "scope_id" => "base",
  "evidence_ids" => ["ev-key-taken"]
}
```

Ask for state at an event:

```elixir
StoryWorld.state_at(world, "brass-key", "possessor", "event-later")
# => {:known, %{value: "Mara", ...}} | {:ambiguous, ...} | :unknown
```

A transition only applies when its event is the queried event or is safely established at/before it. If chronology is unknown or ambiguous, the query abstains. A flashback therefore cannot inherit a later-presented death, injury, possession or access change just because that later scene appeared earlier or later in the file.

### Knowledge, belief and suspicion

Use assertions with `epistemic_owner` for what a character knows/believes/suspects, and `story_time_refs` when the claim is event-qualified. `StoryWorld.knowledge_at/4` filters those claims without conflating them with audience knowledge; `Fount.Intelligence.Reader` keeps the separate presentation-relative first-reader ledger described in `temporal-and-reader.md`.

### Reality scopes

The built-in `base` scope is always present. Non-base records must name a declared scope such as:

```elixir
%{"record_type" => "scope", "id" => "mara-dream", "kind" => "dream", "parent_id" => "base"}
```

Queries default to `base`. A dream/hypothetical/alternate transition does not alter base-story state unless a separate evidence-backed base record says so.

## Partial story time

`story_time_constraint` accepts evidence-backed relation sets using:

`before`, `after`, `meets`, `overlaps`, `same_time`, `during`, `contains`, `starts_with`, `ends_with`.

A single relation is known; multiple still-possible relations are ambiguous; absent evidence stays `:unknown`. Multiple direct constraints with no compatible intersection become a `temporal_contradiction` carrying their source evidence. Only unambiguous `before`/`after` edges propagate transitively; the package does not claim to be a general interval theorem prover.

```elixir
StoryWorld.story_time_relation(world, "event-a", "event-b")
# :unknown
# %{status: :known, relations: ["before"], ...}
# %{status: :ambiguous, relations: ["before", "overlaps"], ...}
# %{status: :contradiction, relations: [], ...}
```

## Causality is separate

A causal edge is never converted into a temporal edge, and a temporal edge is never converted into a causal one:

```elixir
StoryWorld.causal_descendants(world, "setup-event")
StoryWorld.causal_ancestors(world, "payoff-event")
```

This matters for devices such as flashbacks, delayed reveals, recollections and consequences shown before their causes are dramatized.

## Writer reference packet

```elixir
packet =
  StoryWorld.inspection_packet(world,
    question: "What is actually established about the key before the loading dock?",
    protected_strengths: ["keep the reveal understated"]
  )

markdown = StoryWorld.render_markdown(world)
json = StoryWorld.render_json(world)
```

The packet keeps source evidence, derived narrative state, uncertainty, conflicts and protected strengths distinct. In Phase 3 its `diagnoses` and `strategies` arrays are intentionally empty. It does not call a screenplay good/bad, predict audience response, or propose revised pages.

## Counterfactual support primitive

`StoryWorld.counterfactual_remove/2` reports dependency/support consequences of removing one or more StoryWorld records. It can identify affected records, temporal/causal edges and surviving alternate support. It is not a rewrite simulator and never generates replacement pages.

## Recompute boundary

Every interpreted record carries dependencies such as `canonical:<id>`, `observation:<id>`, `measurement:<id>`, `evidence:<id>` or `story:<id>`. `StoryWorld.affected_by/2` follows the reverse dependency index so a later shell can recompute the connected interpreted region rather than treating every screenplay edit as a full reset. The pure core itself does not persist or acquire anything.