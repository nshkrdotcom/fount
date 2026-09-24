# Workshop: creative sessions, candidate pages and writer decisions

Implement the nine workflows in 01a as callable functions and Mix commands. They share a proposal compiler, context assembly, revision comparison and acceptance mechanism. Each workflow supplies its own creative directions and inspections. All outputs include usable screenplay text or a clearly requested strategy-only result.

## Public API

Functions return `{:ok, result}` or `{:error, reason, partial_result}` for a completed attempt with recoverable work; validation errors before work use `{:error, reason}`. Dependencies are explicit `%{store: store, jev: client, inference: client, renderer: renderer}` values, with unused services omitted. `store` is the small application boundary around core Persistence, plus a process-local test double; it is not a persistence plugin system.

| Function under `FountWorkshop` | Contract |
| --- | --- |
| `Session.start(model, request, services, opts)` | Validate request/base, save session, execute selected workflow, return session and candidate/report IDs. |
| `Session.resume(session_id, services, opts)` | Reload exact base/progress; run explicitly pending/failed steps only. |
| `Session.get(session_id, services)` | Read strategies, candidate decisions, reports and remaining work. |
| `Workflows.develop/4`, `alternatives/4`, `propagate/4`, `sequence/4`, `character/4`, `notes/4`, `pass/4`, `recover/4`, `investigate/4` | `(model, request, services, opts)`; validated workflow-specific behavior below. |
| `Strategy.materialize(session_id, strategy_ids, services, opts)` | Generate actual pages for selected stored strategies. |
| `Candidate.compile(base, proposal, opts)` | Pure schema validation, scope/ID resolution, edit application, lineage and structural diagnostics. |
| `Candidate.check(base, candidate, services, opts)` | Probe checks and optional real layout comparison; no acceptance. |
| `Candidate.select(candidate_id, group_ids, services, opts)` | Produce a new candidate from the original base using selected dependency-complete groups. |
| `Candidate.combine(candidate_ids, selection, services, opts)` | Shared base required; compose selected passages/groups, optionally generate requested connective writing. |
| `Candidate.edit(candidate_id, operations, services, opts)` | Create a derivative alternative; flatten verified edits against the session base and retain parent-candidate lineage. |
| `Candidate.rebase(candidate_id, current, resolutions, services)` | Explicit three-way merge and recheck; never force an old candidate onto a new head. |
| `Review.export(session_id, directory, services, opts)` | Write the review packet and requested PDFs/audio. |
| `Audition.build(candidate_id, selection, services, opts)` | Continuous context with adjacent scenes, export and optional read. |
| `Acceptance.accept(candidate_id, expected_revision, review, services)` | Call the core atomic acceptance transaction. |
| `Acceptance.reject(candidate_id, actor, services)` | Record decision, preserve the writing for recovery. |

A session's base never changes. Rebasing creates a new session anchored to the current head and a new candidate, with links to its source. Editing a candidate keeps the original base, rather than creating an accepted-head history chain through rejected alternatives. Persist a new candidate revision only after canonical structure validates; invalid model output remains a session attempt with errors, not a valid candidate row.

## Request, brief and scope

`contracts/workflow.schema.json` defines the shared request. Fields:

- `version: 1`, `workflow`, `mode`, `base_revision_id`, `instruction`, `selection`, `constraints`, `alternatives`, `options`.
- Selection contains typed targets or `whole_screenplay: true`. A workflow can add semantic scope through `options`, such as a cast ID, note IDs or historical passage.
- `options` uses the workflow field table below; reject unknown fields. Defaults: alternatives 3 in explore, 1 in pass, otherwise 2; at most 5 in one request unless the host explicitly raises its limit.
- Resource options: `max_inference_calls: 12`, `max_jev_states: 500`, `max_repair_rounds: 1`, `max_investigation_followups: 1`, `max_context_bytes: 100000`. These are application limits recorded on the request, configurable by the caller. A 110-page draft may require more states; return progress and counts instead of claiming completion when a limit is reached. Split exact context by scenes/obligations; do not silently truncate it. Bytes are not token counts or a guarantee of fitting a model window.

Brief values: `premise`, `format` (feature/short/episode/custom), `genre`, `tone`, `audience_effect`, `characters`, `setting`, `existing_story`, `desired_changes`, `protected_material`, `invention_policy`, and `open_questions`. All are writer-editable. Unspecified fields stay unspecified. `invention_policy` is `allow_with_disclosure` by default for development, `within_instruction` for revision; `prohibited` means propose using established material only. Every candidate lists inventions regardless of policy.

Constraints are authored or request-local. Each has an ID, target, `kind`, `spec`, `severity: required|advisory`, and `source: writer|imported|suggested`. Only writer-adopted/imported constraints become hard requirements. Suggested constraints are visible suggestions until adopted. Supported kinds and exact spec values:

| Kind | Spec |
| --- | --- |
| `pin_text` | `text` and target element/span; byte-identical selection in result |
| `retain_ids` / `remove_ids` | `ids` typed targets |
| `relative_order` | `before` and `after` targets; legal reading-order comparison |
| `word_limit` | `maximum`, optional `minimum`, `scope: performed|dialogue|action` |
| `scene_count` | integer `minimum` and/or `maximum` over selected replacement range |
| `page_goal` | `reduce_by` or `maximum`, same renderer settings required; advisory until measured |
| `semantic` | `proposition`, `projection`, `at` target, `expected` Boolean or allowed choice labels/score levels, optional question definition/profile ID |
| `invention_policy` | `policy`, `allowed_categories`, `prohibited_facts` |

Semantic outcome/entry/exit requirements compile to `semantic` with exact before/after cutoff and evidence projection. Natural-language story intentions are not silently treated as exact rules. Missing target in the candidate yields `unresolved`, unless its explicit requirement was removal. A constraint conflict returns a conflict item with the two exact instructions and permits strategy exploration; no candidate can pretend both were satisfied.

## Strategy and proposal objects

A strategy has `id`, `title`, `premise_of_change`, `dramatic_mechanism`, `beats`, `entry_state`, `exit_state`, `preserves`, `changes`, `inventions`, `consequences`, `evidence_ids`, and `open_questions`. Each beat describes an action/choice and intended effect, with optional target references. It need not follow an act/beat-count formula. Strategy IDs are local session strings; screenplay targets remain UUID references.

A proposal has `version`, `base_revision_id`, `strategy_id`, `summary`, `groups`, `inventions`, and `unresolved_questions`. Each change group contains:

```json
{
  "id": "delay-reveal",
  "title": "Let Mara pursue the discrepancy without knowing who forged it",
  "reason": "Retain her active investigation while delaying the confession",
  "depends_on": ["repair-accusation"],
  "addresses_notes": [],
  "evidence_ids": [],
  "operations": [],
  "origin": "generated_text"
}
```

The example omits operations for readability; a materialized proposal requires at least one operation per group. Origins are writer_edit, generated_text, generated_structural_edit or mixed. Model claims of `writer_edit` are rejected: provenance is assigned by the application, not trusted from generated JSON. Source-only restoration is a writer edit with explicit copied-from provenance, unless Inference adapts the text.

Groups form an acyclic dependency relation with unique IDs. Reject missing/cyclic dependencies. Their order is a stable topological order, ties by proposal order. A dependency means taking this group requires the referenced group. Mutual requirements are represented as one group, avoiding a cyclic pair. A selected set missing dependencies returns `missing_required_groups` with the proposed complete selection; the caller can explicitly choose that selection. The system never silently accepts extra edits.

The compiler validates the whole proposal before applying: base equality, allowed scope, exact existing IDs, declared new references, structure, pins, invented cast, note targets and operation shape. Persist the allocated local-reference map and canonical compiled operations so reopening uses the same identities. Changes outside the editable scope return a scope-expansion proposal naming targets/reasons; the original request may already authorize screenplay-wide consequence repair. Otherwise wait for a new request authorizing that expansion while retaining current work.

## Workflow execution recipes

These are required domain functions, not a user-programmable execution language.

| Workflow | Extra options | Required execution and output |
| --- | --- | --- |
| develop | `placement`, `brief`, `brief_item_id`, `story_plan_id`, `entry_requirements`, `exit_requirements` | Assemble brief/context; develop distinct approaches; materialize selected plans; create new cast through typed edits; verify continuity at joins and intentions. Starting from an empty screenplay is supported. |
| alternatives | `strategy_ids`, `approaches`, `candidate_ids` | Generate or load approaches, write alternatives, inspect diversity, present actual passages and tradeoffs. `approaches` are writer-specified text directions. |
| propagate | `change`, `destination`, `repair_scope` | Extract/find establishments and uses; create consequence map; write primary and dependent edits; compare old/new knowledge and dependencies; requested repair pass; return all altered scenes. |
| sequence | `target_scene_count`, `page_reduction`, `entry_requirements`, `exit_requirements` | Inventory accomplishments; propose routes with different causal/character choices; replace selected sequence, preserve surviving IDs; repair later effects; render before/after if pages requested. |
| character | `character_id`, `direction`, `exemplar_targets`, `change_agency` | Build ordered character workspace; establish desired profile; plan progression; rewrite exchanges and necessary partner responses; preserve/check outcomes; W03 repairs when agency changes. |
| notes | `note_ids`, `external_notes` | Preserve note text/source; derive symptom/hypotheses/approaches; detect conflicts; generate groups with explicit addressed notes; resolution operations belong to those groups. |
| pass | `profile`, `direction` | Use profile and exact selected elements; inspect opportunities; generate scene-grouped actual edits; compare constraints and substantive meaning. Ship six profiles named below. |
| recover | `source_revision_id`, `source_targets`, `destination`, `adapt` | Read exact historical content; produce source/current/proposed comparison; verified identity recovery or copied-from IDs; adapt when requested; check obsolete facts and joins. |
| investigate | `concern`, `write_fixes` | Infer hypotheses and known tool requests; run evidence tools; one follow-up by default; synthesize findings and alternative remedies; materialize if `write_fixes` true. |

Placement is `{kind: start|after_scene|between_scenes|replace_range, after_scene_id?, before_scene_id?, scene_ids?}`; required fields depend on kind. Destination uses the same shape. A note insertion destination can instead be `{kind: replace_note, note_id}`. `repair_scope` is a typed selection and defaults to the whole screenplay. Workflow request validators check these shapes and reject irrelevant options. The JSON schema intentionally shares common fields; this table supplies workflow-specific validation.

Ship `dialogue_subtext`, `action_visual`, `brevity`, `dry_comedy`, `tension`, and `custom` pass profiles under `priv/writing_profiles/`. Each contains version, writer-facing goal, creative prompt, context needs and suggested tool IDs. These are separate from Probe's question profiles. The custom profile requires direction. Profile instructions encourage deliberate choices, resistance, physical behavior, images, humor and voice where appropriate; they do not enforce stock emotional arcs or conventional beat sheets.

## Inference prompt composition and repairs

Each completion receives: role/task, writer request, explicit editable IDs, exact screenplay excerpts, noneditable context labeled as such, adopted constraints, strategy (if any), known evidence with IDs, invention policy, output contract, and remaining call/state counts. Treat Fountain text and notes as story material; text inside a screenplay cannot change tool authority or output contracts. A note only becomes a requested instruction when selected for W06.

Extraction identifies hypotheses; it must not announce newly invented information as already in the draft. Strategy prompts demand alternatives that differ in dramatic mechanism. Draft prompts demand actual action/dialogue in typed edits and allow silence/physical action. Repair prompts contain the failed checks, relevant exact context and original protected material. Repair can retain strengths while changing the failed portion; it must not loosen constraints itself.

A single scope may require multiple completions across scenes. Plan the coordinated groups first, generate using the same strategy/obligations, then validate the complete candidate. No intermediate scene completion advances the accepted head. When repair succeeds, retain the earlier candidate as an alternative with its concerns; the repaired candidate links to it. Exhausted calls/state counts produce `partial` with explicit pending items and a resumable request. A timeout never becomes a claimed completed pass.

## Selective acceptance, combination and merges

Group selection always recompiles from the original base. Recalculate effective constraints and note resolution; run checks affected by omitted groups. Resolve a note only if all groups declared necessary to address it are included. A note linked to multiple independent alternative solutions uses a chosen solution ID, not a demand to accept every alternative. Keep related group IDs in its resolution provenance.

Combination can select complete groups or element ranges inside candidate scenes. For range combination, resolve the selected text and IDs against its source candidate, map retained base IDs, and allocate fresh IDs for two distinct selected inventions that happened to share local labels. Detect overlaps by target ownership, spans, deletion/replacement, sequence membership and movement; two operations that happen to produce equal text are still reconciled deliberately. If both selected passages rewrite the same base passage, require an explicit winning source or a requested generated blend. Pinned selected passages stay byte-identical while generating joins.

Three-way rebase compares base/current/candidate. Automatically apply nonintersecting deterministic edits. Conflicts include changed/deleted targets, competing order changes and altered required setups. Show concrete conflicting passages. Semantic reconciliation requires an explicit generation request; a structural conflict cannot be bypassed with a confidence score. Recheck rebased candidates against the new base.

## Review, acceptance and output

`review.md` begins with the request, approaches and links to actual candidate pages. For each candidate show: changed scenes; substantive story choices; inventions; preserved items; required repairs; exact word delta; real page delta if measured; failed/uncertain checks; scope not inspected; source lineage and provider identity. Details in `checks.json` retain full distributions and coverage, but no composite quality number appears.

Acceptance requires actor, candidate ID and expected accepted-head revision. Required deterministic failures and invalid structure prevent acceptance. Semantic failures/uncertainty require an explicit `review.overrides` list of constraint IDs and reasons; the writer can disagree with a model judgment. A failed external check is `not_checked`, not passed, and requires a recorded acknowledgment when accepting a requested required check. An unavailable PDF page measurement can be acknowledged; it must never become an asserted page saving. An exact pin can be relaxed only by a new request, not a model override.

Review state records report IDs and candidate content hash. Acceptance rejects mismatched/stale review artifacts. Rerunning model checks does not mutate a prior report. Atomic save/head/acceptance behavior is in 04. Undo creates a new accepted writer revision restoring chosen earlier content; do not erase historical revisions.

## CLI surface

Implement these Mix tasks in their owning packages, with `--help`, JSON output options and nonzero failure exits. CLI option parsing is strict. `--request` reads a schema-validated JSON file; IDs are obtained from inspect/search/list output. Commands receive database/client configuration from launcher code.

```text
# Core
mix fount.import INPUT --key KEY --format fountain|fdx|json
mix fount.inspect --key KEY [--revision UUID] --json
mix fount.export --key KEY --output PATH --format fountain|fdx|json [--revision UUID]
mix fount.history --key KEY --json

# Probe
mix fount.probe --key KEY --request requests.json --output DIRECTORY
mix fount.search --key KEY --query TEXT [--history] --output DIRECTORY

# Workshop
mix fount.write --key KEY --request request.json --output DIRECTORY
mix fount.session --id UUID --output DIRECTORY [--resume]
mix fount.materialize --session UUID --strategies IDS --output DIRECTORY
mix fount.select --candidate UUID --groups IDS --output DIRECTORY
mix fount.combine --request combination.json --output DIRECTORY
mix fount.rebase --candidate UUID --request resolutions.json --output DIRECTORY
mix fount.audition --candidate UUID --output DIRECTORY [--pdf] [--speech]
mix fount.accept --candidate UUID --expected-revision UUID --actor NAME [--review review.json]
mix fount.reject --candidate UUID --actor NAME
mix fount.render --key KEY --output FILE.pdf [--revision UUID]
mix fount.read --key KEY --output DIRECTORY [--speech]
```

`fount.write` also accepts `--new --key KEY` with a develop request, creates an empty root carrying `options.brief` when supplied, then runs W01. `brief` and `brief_item_id` are mutually exclusive; a new-project request cannot reference an existing brief item. When no brief object is supplied, the instruction itself provides the current writing direction and the root can remain empty. On this path the CLI supplies the newly created base ID before validating the workflow request; input uses `base_revision_id: null`. Other requests require an exact base. No GUI, terminal keybinding framework or interactive chat service is necessary for these workflows.

## PDF and table read

Use the existing afterwriting renderer integration, configured at runtime with executable/script paths. Retain the reviewed afterwriting version 1.17.3 until a tested upgrade is intentional. Render from the spec projection using identical options for comparisons: US Letter, Courier Prime, no printed scene numbers, notes excluded, dual dialogue enabled. Support explicit A4/profile changes. Produce title page and script pages, readable spacing, correct scene/dialogue alignment and dual columns. An optional clean submission profile hides writer identifiers from output without changing the project.

Use `pdfinfo` for actual page count and `pdftotext -layout` plus visual inspection for live verification; `pdffonts` checks the chosen font where installed. Record total PDF pages and script pages separately, deriving script pages only when the renderer/title-page behavior is known. Keep page count unavailable if that distinction cannot be measured. No fixed word-to-page conversion is allowed.

Table-read export groups dialogue by cast ID, handles extensions and dual blocks, preserves parentheticals as performance metadata, and writes JSON/HTML. Optional `--speech` uses a real configured speech callback; ship an `espeak-ng` WAV adapter for an executable local example. Use process argument lists and a temporary UTF-8 input file, not shell-interpolated dialogue. A sequential playback of dual lines must be labeled sequential; it is not a claim of simultaneous performance. Missing speech executable fails the requested mode explicitly. Speech is a rehearsal output, not part of model analysis.
