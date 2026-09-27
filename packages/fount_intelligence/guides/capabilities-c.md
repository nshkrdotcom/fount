# Capabilities C: Emotional / Value, Theme, Genre Packs, Revision Intelligence

Phase 8 completes the twelve-family analytical catalog with four writer-facing capabilities. They are evidence-backed ways to inspect a screenplay, not formulas for whether a script is good and not automatic rewrite instructions.

The installed family ids are:

- `emotional_value_movement`
- `theme_meaning`
- `genre_lens_packs`
- `revision_intelligence`

All remain inside the existing Fount boundary: Observe acquires atomic measurements; pure Intelligence interprets frozen values; Workshop still owns generated pages, candidate storage, review, acceptance, recovery, and rendering.

## Emotional / Value Movement

This family treats emotional movement as multiple screenplay-supported conditions rather than one positive/negative score. It can track changes in practical options, hope, fear, security, belonging, trust, status, control, certainty, and moral confidence, plus anticipated gain/loss and visible event/reaction/behavior links.

Use it directly with `Fount.Intelligence.run_capability/5`, or opt it into the preserved `character_trajectory` writer playbook with:

```elixir
%{
  "include_emotional_value_movement" => true,
  "subject" => %{"character" => "Mara"},
  "selection" => selection,
  "story_world_records" => records
}
```

The opt-in is deliberate: Phase 8 does not silently add provider work to the existing Phase-6 `character_trajectory` default.

A supported reversal or missing visible reaction is a prompt to inspect behavior and consequences. It is not a claim that a real person should feel a particular way, and delayed/concealed reaction can be intentional.

## Theme and Meaning

`theme_meaning` builds competing thematic hypotheses from recurring value conflicts, consequential choices, consequences, motifs/contrasts, ending recontextualization, writer intent, and counterevidence.

The installed conflict-axis vocabulary is deliberately practical and incomplete. `other_or_unclear` exists so the system does not force material into a taxonomy. The result can contain multiple hypotheses and counterevidence. It never emits an authoritative single theme, a depth score, or an overall quality score.

The existing `submission_read` writer id now has a Phase-8 analytical path through this family. It remains a read/diagnosis packet; it does not generate or accept revisions.

## Optional genre/craft packs

`Fount.Intelligence.genre_packs/0` exposes six initial core assets:

- mystery
- thriller
- horror
- romance
- comedy
- action

They are starting assets, not a closed genre list and not mandatory conventions. A caller-owned catalog starts with every core pack disabled. Installation and enablement are separate decisions.

```elixir
catalog = Fount.Intelligence.new_genre_pack_catalog()
{:ok, catalog} = Fount.Intelligence.enable_genre_pack(catalog, "genre.mystery")
{:ok, mystery} = Fount.Intelligence.fetch_genre_pack(catalog, "genre.mystery")
```

A pack is data: it names installed safe lens ids, installed capability families, existing writer playbooks, diagnostic salience, writer-intent prompts, explicit subversions/opt-outs, trust/source metadata, and a resource request that must fit host caps. It cannot name modules, functions, shell commands, file paths, provider endpoints, credentials, HTTP/database callbacks, decoders, tools, or arbitrary executable adapters.

### Project/studio declarative lenses

A project/studio may author a constrained generic measurement through `Fount.Observe` without loading code:

```elixir
{:ok, preview} = Fount.Observe.preview_declarative_lens(declaration)

catalog = Fount.Observe.new_declarative_lens_catalog()
{:ok, catalog} = Fount.Observe.install_declarative_lens(catalog, declaration)
{:ok, catalog} = Fount.Observe.enable_declarative_lens(catalog, declaration["id"])
```

The declaration compiles only to a normal `Fount.Observe.Question`, a validated caller-supplied `Fount.Observe.Lens` asset using a registered projection and the existing `system_one` sensor, plus safe execution options for a registered calibration reference when present. Host code may then pass that compiled lens through ordinary Observe preflight/evaluation. No arbitrary function/module registry is opened.

Project/studio genre packs may reference explicitly enabled custom lens declarations by passing their catalog to `validate_genre_pack/2` or `install_genre_pack/3` as `custom_lenses: lens_catalog`.

### Subversion is first-class

A pack can state that an expectation is intentionally inverted, refused, or de-emphasized. The genre capability reports that intent and suppresses defect-style interpretation for that expectation. For example, a mystery may reveal the culprit at midpoint and deliberately become character-first; the pack should not convert “late culprit reveal” into a mandatory rule.

## Revision Intelligence

Revision Intelligence requires an explicit base and candidate model. It measures both revisions and then compares source/structural edits with frozen StoryWorld and optional strict-forward Reader state.

Use:

```elixir
Fount.Intelligence.preflight_revision(before, candidate, request)
Fount.Intelligence.run_revision_intelligence(before, candidate, request, clients)
Fount.Intelligence.run_revision_playbook(before, candidate, request, clients)
```

The preserved `revision_regression` writer playbook is the packet wrapper for that explicit two-revision path.

The comparison keeps separate:

- exact source/structural edits;
- intended target effect;
- declared protected strengths;
- continuity, knowledge, causal, voice, action-readability, setup/payoff, and reader-state collateral-risk measurements;
- StoryWorld state-transition differences (character/relationship/practical/value state);
- causal-edge ripple;
- partial diegetic story-time constraint changes;
- optional strict-forward Reader presentation-state differences; and
- optional Strategy Contrast output when 2–5 strategies are supplied.

A reader-presentation change is never silently treated as a diegetic rewrite, and a later-presented flashback is not silently treated as later story time.

Revision Intelligence does **not** choose a winner, rank candidates, accept/reject a candidate, or promote anything to canon. Those remain writer/Workshop decisions. Strategy comparison reports distinctions; it does not select a preferred strategy.

## Resource and trust workflow

The safe asset workflow is deliberately explicit:

1. validate references, trust/source metadata, declaration shape, and host resource caps;
2. preview the canonical hash and compiled safe primitives;
3. install into a caller-owned catalog;
4. enable separately;
5. inspect/disable later without changing code.

Durable storage of project/studio packs and cross-session recomputation belong to a later phase. Phase 8 supplies the data contracts and in-memory/caller-owned workflow only.

## Source-delivery verification state

This Phase-8 source delivery was written against the supplied post-Phase-7-QC Fount snapshot. Python source/JSON/archive checks may be run here, but Elixir/Erlang/Mix are unavailable in this source-writing environment. Therefore formatting, compilation, ExUnit, Credo, Dialyzer, ExDoc, package builds, database/writer/PDF regression, and provider/live verification are **not run here** and are not claimed.

The optional human/domain review is also not run and remains visible validation debt under D046. Codex must start from the user's applied Phase-8 commit, run the full Phase-8 runtime/preservation ladder, repair defects within Phase 8, update the docset with actual evidence, and stop before Phase 9.
