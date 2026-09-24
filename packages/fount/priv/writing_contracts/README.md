# Contracts and executable reference assets

| Asset | Purpose |
| --- | --- |
| [schema.sql](schema.sql) | Fresh PostgreSQL relational design to translate into Ecto migrations |
| [operations.json](operations.json) | JSON Schema for each canonical edit operation |
| [workflow.schema.json](workflow.schema.json) | Common writing request shape |
| [proposal.schema.json](proposal.schema.json) | Generated proposal/change groups; references the operation schema |
| [profiles.json](profiles.json) | Decision defaults and concrete Jev profile examples |
| [example_request.json](example_request.json) | Delayed-confession request with synthetic IDs |
| [example_proposal.json](example_proposal.json) | Complete valid local text proposal with synthetic IDs |

Use JSON Schema draft 2020-12 as the local document contract. An Elixir validator can be a small explicit decoder for these fixed shapes; no new schema-generation framework is required. Schema documents are the serialized shape; domain validation in 04–09 is also required. The schemas intentionally cannot establish that a UUID exists in a screenplay, that two edits are compatible or that a semantic assertion is true.

## Operation wire rules

An operation contains `kind`, `target` when the operation acts on one existing object, and `value` when it carries data. No `value` field exists on deletion of a whole scene/authored item. Multi-target operations put their IDs inside `value`. Unknown top-level keys fail validation. `ElementSpec` uses either `keep`, or one of `id`/`local_id` plus type/text/attrs. IDs in the examples are synthetic and must be bound to imported IDs for actual calls; the live fixture binding instructions are in `fixtures/README.md`.

Generated body types exclude `scene_heading` and `unknown`: scene headings are represented by SceneSpec, and unknown imported material cannot be invented by a generator. Archival import/export can still preserve the full core element vocabulary. `attrs` explicitly allows speaker identity, dual pairing, forced Fountain syntax, section level and ordinary metadata. Core interprets only declared fields; metadata is not executable behavior.

For a character cue, `attrs.character_id` binds it to a confirmed cast ID. `attrs.dual_with_cue` references its partner cue, with `dual_side: left|right`; final validation requires reciprocal opposite sides and adjacent legal dialogue groups. The compiler resolves new references before rebuilding blocks. A reference to a new block can use `new:block-<cue-label>` allocated alongside the declared new cue; this derived reference is reserved and cannot be declared as an unrelated object. Existing block IDs survive retained cue IDs.

Spans are half-open UTF-8 byte positions in the current element. Local validation additionally requires end > start, UTF-8 boundaries, in-range offsets, and `kind: element`. Operation targets ordinarily refer to the whole object; `replace_text` with a span replaces only those bytes, then reparses inline markup and refreshes mentions. Invalid or overlapping spans fail; they are not rounded to a character boundary. A full-text replacement uses no span. All non-text operations reject spans.

Character aliases contain `alias` and `kind`; supported kinds are `cue`, `name`, `nickname`, `former_name`, `other`. Normalize aliases for lookup while preserving authored spelling. A repeated alias across characters remains ambiguous; do not add a uniqueness rule across the cast. New characters require a display name; arbitrary attributes do not establish character knowledge or presence.

Authored item values use the following domain shapes, validated by their owning modules:

| Kind | Required value / interpretation |
| --- | --- |
| brief | The writer-editable fields listed in 09; all individually optional, at least one nonempty |
| story_plan | `title`, ordered `beats` with `id`, `description`, optional targets and intended effect |
| note | `text`, `source`, optional `solution_id`, `resolution` with accepted revision/group provenance |
| constraint | Complete constraint definition from 09, without duplicating outer target if omitted by decoder |
| fact | `statement`, `mode: intended|established`, optional evidence references for established material |
| voice_direction | `character_id`, `direction`, `exemplar_targets` |
| sequence / storyline | `name`, ordered `scene_ids`, optional purpose |
| story_time | `label`, optional `day`, `time`, `before_scene_ids`, `after_scene_ids`; explicit partial ordering, no fabricated absolute date |
| perspective_access | `subject`, `source_targets`, `channel`, `access`, `explanation`; enums and evidence rules in 06 |

The outer item retains ID, namespace, target, status, dependencies and provenance. `namespace` defaults to `fount.writer`; external imports may use another explicit string. A resolved note's accepting revision ID is filled by the application when forming the candidate revision, never guessed by the model.

Workflow `options` and constraint `spec` are object-shaped in the shared schema. Implement their exact discriminated validators from 09. Reject unknown options and invalid combinations, including a development placement missing its required IDs. New-project requests alone allow a null base; the launcher resolves it before executing the workflow. Materialized proposals never use a null base. Limits and model control settings are application options, not arbitrary entries forwarded to providers.

`profiles.json` supplies shared thresholds plus profile-specific question assets. Each instantiated profile records the effective thresholds alongside its own ID/version/hash. Substitute only named template variables with validated values. Model state/evidence is supplied separately; do not interpolate entire scripts into question instructions. Choice options and Score levels are ordered `[label, description]` pairs. Additional feature question assets follow the algorithms and questions in 07.

## Persistence rules beyond SQL

The SQL is a complete fresh schema, not a migration to run over existing tables. The implementation translates it into Ecto migrations. App validation enforces type-appropriate heading/cue membership, contiguous canonical ordering, reciprocal dual groups, parent ancestry, target resolution and candidate base/result consistency. Database FKs enforce revision and screenplay scope. Immutable revision rows are never updated in normal application APIs; changing a draft inserts a revision. Session progress and candidate decision metadata are the explicitly mutable records.

The content hash is computed from canonical authored state; database row serialization is not its definition. Canonical JSON encoding sorts object keys, keeps ordered arrays, rejects nonfinite numbers and excludes derived/runtime/provenance fields specified in 04. The render hash includes all source-affecting authored content but excludes identifiers and metadata that cannot affect output.

## Source versions and verification

The SQL/JSON assets make the design checkable before implementation. Passing their syntax checks does not mean Fount already implements them. The final implementation must validate real model responses and migrate/load real PostgreSQL values through the specified APIs. Do not copy synthetic contract IDs or example writing responses into live service demonstrations.
