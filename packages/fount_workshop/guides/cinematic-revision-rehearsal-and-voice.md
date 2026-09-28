# Cinematic revision, rehearsal, and voice protection

Phase 13 extends the existing Workshop candidate/session model. It does not create a second screenplay representation and it does not let analysis or generation advance canon.

## Cinematic passes

The pass workflow now ships four directly cinematic lenses:

- `action_visual` — behavior, images, physical obstacles, reactions and visual legibility;
- `sound_space` — sound, offscreen action, absence, object placement and spatial relationship;
- `cinematic_rhythm` — playable timing, intentional stillness, entrances/exits and held beats;
- `transition` — scene-boundary juxtaposition, carried sound/image and unresolved action.

These are directions, not rules. Silence is not automatically a defect. Voiceover is not banned. Sparse dialogue is not presumed weak. Camera directions are not added unless the writer asks for them. A valid result may leave already-working material untouched.

A normal request uses the existing `pass` workflow:

```elixir
request = %{
  "version" => 1,
  "workflow" => "pass",
  "mode" => "revise",
  "base_revision_id" => screenplay.revision.id,
  "instruction" => "Keep Mara silent. Let the room do the work.",
  "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene_id}]},
  "constraints" => [],
  "options" => %{"profile" => "sound_space"}
}
```

The generated result remains an ordinary candidate. The writer still decides whether to accept, reject, select, combine or continue editing it.

## Writer-selected voice evidence

Three optional request fields carry project-specific voice guidance:

- `voice_exemplars`: targets from the current authorized screenplay;
- `style_preferences`: explicit writer-owned preferences such as deliberate fragments or repetition;
- `protected_text`: exact target/text pairs that must survive byte-identically.

`protected_text` is not prompt advice. `FountWorkshop.Writing.VoiceProtection` converts each protected passage into an ordinary required `pin_text` constraint. The existing deterministic constraint path verifies the source location and candidate result. A failed required deterministic pin remains a hard review blocker.

Example:

```elixir
"options" => %{
  "profile" => "cinematic_rhythm",
  "voice_exemplars" => [%{"kind" => "element", "id" => dialogue_id}],
  "style_preferences" => ["Keep purposeful repetition", "Keep clipped action fragments"],
  "protected_text" => [
    %{
      "id" => "not-today",
      "target" => %{"kind" => "element", "id" => dialogue_id},
      "text" => "Not today. Not today."
    }
  ]
}
```

The generated voice context explicitly says not to silently translate or normalize multilingual text, dialect, deliberate fragments, strategic awkwardness or repetition. That is still not a claim that a model can certify voice, dialect or cultural authenticity. Those judgments remain writer/human review questions, and the original remains a valid choice.

Character workflows continue to support their existing `exemplar_targets`; those targets also become source-backed voice exemplars rather than a new compatibility surface.

## Noncanonical rehearsal

`FountWorkshop.Rehearsal` stores exercises in durable session progress only. Rehearsals can change tactic, reverse a status assumption, remove a participant, put opponents on the same side, imagine a private conversation that never appears, or temporarily invent backstory.

```elixir
{:ok, exercise} =
  FountWorkshop.Rehearsal.add(session_id, %{
    "kind" => "invented_backstory",
    "prompt" => "Privately improvise Dan as if he once stole a boat.",
    "invented_claims" => ["Dan once stole a boat"]
  }, services, actor: writer_id)
```

An active or rejected exercise is never included in later generation context. It does not call `Fount.Screenplay.apply/3`, write StoryWorld facts, or mutate the immutable opening request. Explicit adoption records actor/note provenance and makes the exercise available as traceable project-room context:

```elixir
{:ok, adopted} =
  FountWorkshop.Rehearsal.adopt(session_id, exercise["id"], services,
    actor: writer_id,
    note: "Useful possibility for later exploration."
  )
```

Even adopted rehearsal context is labelled noncanonical. It may inform later exploration, but it is not automatically promoted into a StoryWorld fact. Establishing a fact still requires canonical/source evidence through the existing model.

## Compare actual pages, not generator claims

`FountWorkshop.Comparison` compares the candidate screenplay to its immutable base with the existing stable-ID screenplay diff. It reports actual changed action, changed language, transition changes, dialogue delta and mechanical protected-text checks.

```elixir
{:ok, comparison} = FountWorkshop.Comparison.candidate(candidate_id, services)
```

The packet carries any generator summary only under `generator_claim` and sets `generator_claim_is_evidence` to `false`. It does not score voice, choose a winner or claim one candidate is stronger. Use the actual before/after text, the protected-text checks, and the original draft when making the writer decision.

## Phase-13 acceptance fixtures

The deterministic tests cover the required cases:

- **A02:** two quiet key/cooling-cup revisions use image versus sound while preserving Mara's silence; a fluent explanatory control changes actual language and is explicitly rejected in the fixture.
- **A04:** `Not today. Not today.` plus multilingual Unicode survives exact pinning; normalization fails the deterministic check, and the output declares language/cultural-authenticity limits.
- **A05:** `Dan once stole a boat` exists only inside rehearsal until explicit adoption; a rejected exercise never enters later generation context.

These fixtures establish engineering behavior, not human preference. Optional writer comparison remains nonblocking validation work and must be recorded separately if run.
