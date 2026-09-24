# Core screenplay APIs and edit contracts

## Canonical values

Retain existing IR element/scene/dialogue structs and pure Fountain parsing. Extend `Fount.Screenplay` to contain `id`, `revision`, `ir`, `cast`, `mentions`, `authored_items`, `import`, and a derived `index`. Derived model reports do not live in this struct. `Fount.Document` retains its CST/source and source-backed edit functions.

`Screenplay.from_document/2` creates a canonical root revision, preserves original bytes and offers `cast_resolution: :literal_cues | :manual`. `:literal_cues` creates one character per exact normalized cue name after separating Fountain extensions; ambiguous aliases remain unresolved. It establishes speaking identity, never physical attendance or who heard another line. No model call occurs on import.

`Screenplay.new/1` accepts title, scenes/body, cast and authored items so an initial model is built as one root. After creation, all authored changes use one `Screenplay.apply/3` batch. An empty model is valid for story development. Pure unsaved editing is allowed; when saving a candidate the base revision must exist. For several unsaved steps, `Screenplay.squash(base, changed, ops)` verifies and creates one candidate whose parent is the intended saved base, preserving intermediate origin information in the change set.

```elixir
Fount.Screenplay.apply(model, operations, opts \\ [])
# {:ok, candidate, change_set} | {:error, diagnostics}
Fount.Screenplay.diff(before, after_model)
# %{elements: ..., scenes: ..., blocks: ..., cast: ..., authored_items: ..., order: ...}
Fount.Screenplay.restore(current, prior, selection \\ :all)
# produces a candidate + change_set parented by current
Fount.Validate.screenplay(model)
# diagnostics, with stable codes and typed targets
```

ChangeSet fields: `base_revision`, `result_revision`, `operations`, `changed_targets`, `inserted_targets`, `removed_targets`, `lineage`, `origin_by_group`, and `diagnostics`. Each successful non-no-op batch creates one revision. Apply all steps in memory, validate final structure and publish the value only if the batch succeeds. No intermediate edit is persisted by `apply`.

## One target type

Use `%Fount.Annotation.Target{kind: kind, id: uuid, span: span_or_nil}` consistently in core, reports, persisted JSON and adapters. Supported kinds: `screenplay`, `revision`, `scene`, `element`, `dialogue_block`, `character`, `title_entry`, `authored_item`.

A report evidence reference adds `screenplay_id` and `revision_id` outside the target. A target span is `{byte_start, byte_end}` measured in the element's current UTF-8 `text`, half-open and nonempty. Only element targets accept this span. Original file positions are a separate `source_reference` containing artifact ID and artifact byte range; never present stale source offsets as current positions.

`Fount.Target.resolve(model, target)` returns the typed value or `{:error, :missing_target}`. Fixed kind strings map through an explicit enum table. Unknown kinds fail. Update JSON, FDX metadata where supported, persistence codecs, snapshots retained for interchange, tests and all call sites together; no legacy `node_id` target survives in new payloads.

## Structural query surface

`Fount.Query` supports Document and Screenplay for structural functions. Cast/author metadata calls on a Document with no canonical cast return a documented `:canonical_model_required` error; they must not invent identities. Convert to Screenplay for those functions.

| API | Return / ordering |
| --- | --- |
| `node(subject, id)`, `scene`, `dialogue_block` | value or nil; indexed lookup |
| `scenes(subject, opts)`, `elements(subject, opts)`, `dialogue_blocks` | canonical order; `include_omitted: false` default for writing views |
| `scene_elements(subject, scene_id)`, `scene_dialogue_blocks` | `{:ok, ordered_list}` or unknown-scene error |
| `scene_for(subject, element_id)`, `block_for(subject, element_id)` | value or nil |
| `elements_between(subject, first_id, last_id)` | inclusive range, reject reversed/different scopes |
| `scenes_between(subject, first_id, last_id)` | inclusive reading-order range |
| `characters(model)`, `character(model, id)` | cast catalog; deterministic order by name then ID |
| `character_dialogue(model, cast_id)` | only confirmed speaker links, in reading order |
| `character_mentions(model, cast_id, opts)` | returns role/status; optional candidates/references |
| `scenes_with_character(model, cast_id, opts)` | specify `role: :speaker | :mention | :declared_present`; no conflation |
| `authored_items(model, kind, opts)` | status and typed target retained |
| `outline(subject)`, `location_groups`, `swimlanes` | preserve existing useful views and omission filters |

Extend the existing index with block membership, cast cue links and ordinals. Build it once when constructing/loading/editing a model. Queries must not rebuild it inside each element lookup.

## Deterministic slices

Constructors return `{:ok, %Fount.Slice{}} | {:error, reason}`:

```elixir
Fount.Slice.scene(model, scene_id, opts)
Fount.Slice.scene_range(model, first_id, last_id, opts)
Fount.Slice.scene_prefix(model, scene_id, through_element_id, opts)
Fount.Slice.dialogue_block(model, block_id, opts)
Fount.Slice.character(model, cast_id, opts)
Fount.Slice.selected(model, typed_targets, opts)
Fount.Slice.to_map(slice)
```

Slice fields: screenplay/revision IDs, selector, ordered scene/block/element IDs, cast links, typed content, source references and a deterministic fingerprint. `include_omitted`, `include_notes`, and `include_boneyards` are explicit options; ordinary performed-content slices exclude them. A raw archival slice can include them for history/search. Keep source data separate from model state: Probe owns perspective filtering, and Workshop owns creative context composition.

Prefix selection ends after an element or after the whole dialogue group containing it. An explicitly requested exact element cutoff that divides simultaneous dialogue returns `:split_simultaneous_group`; callers choose the preceding or following legal group. Scene prefix includes a baseline before the first body group. Full reading order can differ from story chronology; do not infer chronology from scene ordinal.

## Typed edits required by creative workflows

Operations are JSON objects with `kind`, a typed `target` when relevant, and the actual value shape. The serialized shape is specified by [operations.json](contracts/operations.json). Existing constructors can delegate to these operations. Source-backed Document editing retains its own byte-aware implementation; generated edits always target canonical Screenplay values.

| Operation | Value and behavior |
| --- | --- |
| `replace_text` | String on an action/dialogue/parenthetical/lyric/note/centered/transition element. Keep ID/type; refresh markup and mention spans. |
| `set_scene_heading` | Heading string on scene; preserve heading ID; reparse location/time fields. |
| `set_scene_number` | String or null on scene; identity independent of printed numbering. |
| `insert_elements` | `{position: before/after/start/end, anchor_id: uuid/null, elements: [ElementSpec]}` within a scene or screenplay preamble. |
| `delete_elements` | `{ids: [uuid]}`; reject dangling blocks/headings unless a companion edit repairs final structure. |
| `replace_scene_body` | `{elements: [ElementSpec]}`; typed full body replaces the scene body while preserving explicitly reused IDs. |
| `insert_scene` | `{after_scene_id: uuid/null, scene: SceneSpec}`; null means before the first scene. |
| `delete_scene` | Removes scene and content from this candidate; history retains them. |
| `omit_scene` | Boolean; retained in canonical model, absent from performed/spec output. |
| `move_scene` | `{after_scene_id: uuid/null}`; moving after itself is an error. |
| `replace_sequence` | `{scene_ids: [uuid], scenes: [SceneSpec]}`; input range must be contiguous. Supports actual merge/split/reorder/rewrite. |
| `rename_character` | `{name: string, mention_ids: [uuid]}` on cast ID; change linked cues and explicitly selected confirmed mentions only. |
| `put_character` | Cast fields with existing ID or new local reference; additions are part of candidate edits. |
| `link_speaker` | `{character_id: reference}` on dialogue block; update cue binding without inferring attendance. |
| `put_authored_item` | Complete item with existing ID or new local reference; core validates target/status/JSON, Probe validates known constraint formats. |
| `delete_authored_item` | Removes an authored item in this revision; prior revision retains it. |
| `set_title` | Ordered list of title key/value entries with retained IDs or new local refs. |

`ElementSpec` is either `{"keep": existing_element_id}` or `{id: existing_uuid OR local_id: "new:...", type, text, attrs}`. `SceneSpec` has retained scene `id` or new `local_id`, heading, optional number, omitted flag and body elements. For a retained scene, reuse its heading ID; for a new scene allocate scene and heading IDs in the compiler. Dialogue block identity follows a retained cue ID; newly introduced cues get new block IDs. Explicit dual grouping attributes create reciprocal links when blocks are rebuilt.

Model output uses `new:<label>` references for new objects. The proposal compiler allocates UUIDs once, returns the mapping and replaces all references before applying. A local reference is declared once across the whole candidate. Existing IDs must be from the supplied editable scope; no invented UUID is treated as a known target. New elements can reference new characters declared earlier in the same candidate. Within a batch, operation order is explicit; later operations can reference allocated IDs.

Sequence replacement retains an existing element/block/scene identity only when that ID is explicitly reused once and is from the replaced range. A scene merged into another retains the surviving scene ID; the removed scene is recorded in lineage. Moving an element with `keep` preserves its identity. A split assigns a new scene ID to the second scene but retains moved element IDs. New text representing a new beat gets a new ID and may record `replaces` lineage; do not use text similarity as proof of identity.

Core exposes convenience `split_scene` and `merge_scenes` functions by compiling to `replace_sequence`; there is one final edit semantics. Recovery compiles exact retrieved historical content into ElementSpecs. A historical ID absent from the current model can be restored only when supplied in a verified `restore_registry` from the same screenplay; otherwise allocate new IDs and retain `copied_from` lineage. Foreign screenplay imports always allocate new IDs.

## Authored items and protection

Authored kinds shipped: `brief`, `story_plan`, `note`, `constraint`, `fact`, `voice_direction`, `sequence`, `storyline`, `story_time`, `perspective_access`. Core stores typed targets and JSON values; Probe/Workshop validate the domain-specific values. An inferred fact stays in a report until `adopt` produces a `put_authored_item` operation. A writer's declaration may be a design intention rather than something already established on the page; record `fact.mode: intended | established` and never substitute it for scene evidence without disclosure.

Constraints include exact text/identity protection, presence/absence of IDs, word-count limits, required relative order, semantic propositions, allowed inventions, desired outcomes and entrance/exit conditions. Exact pinned material cannot be changed by model edits. Resolve span pins against the base, then map them through the edit ChangeSet: insertions before a pin shift its current offsets, while edits overlapping its protected bytes fail. A whole-element replacement that retains a span pin must supply one unique exact occurrence within the retained element; ambiguous repeated occurrences require explicit writer selection. The resulting check stores the mapped candidate span, never reuses a stale base offset. Semantic constraints can fail or be uncertain; writer acceptance may override with a recorded reason. All unresolved constraints appear in review.

Deleting a referenced target marks its authored items `unresolved` with the missing reference, preserving writer wording. Moving a scene preserves its ID but can change chronological/prefix constraints; those checks rerun. Replacing a note with prose resolves it only if the accepted change group explicitly says it addresses that note.

## Import, export and real writing details

Archival Fountain export uses original bytes when the render hash is unchanged. Edited canonical export retains Fountain markup, notes, boneyards, explicit blank lines, forced syntax and dual dialogue as supported; report any representation loss. A `spec` projection excludes omitted scenes and comments before rendering. An anonymized export changes title/metadata presentation, not the authored draft.

FDX import/export must retain supported paragraph types, title information, dual dialogue and styling; return explicit fidelity losses for unsupported structures. Do not claim perfect FDX round-trip after canonical edits. Canonical JSON interchange uses a versioned codec and preserves IDs, authored items, revision metadata and artifact references/bytes when requested; exclude secrets and runtime objects.

Word counts are deterministic on performed plain text, with action/dialogue totals separate. Printed line counts come from the renderer when available, not Fountain source wrapping. Dialogue table reads exclude cues/parentheticals from spoken text but retain them as metadata. Dual lines are grouped. Spec output and audience projections remove inline notes as well as standalone note elements.

`ChangeImpact.between(before, after)` returns changed/new/removed typed IDs and parent closure on both models: element → block → scene → screenplay; cast changes include affected cues/mentions; order changes affect prefixes; authored changes include dependent constraints. It helps choose relevant checks. Reports always retain their original revision rather than being silently relabeled current.
