# Screenplay tools for agents and creative workflows

## Public contract

```elixir
FountProbe.tools()                         # catalog + JSON input schemas
FountProbe.run(model, tool_name, params, clients, opts \\ [])
# {:ok, %FountProbe.Report{}} | {:error, validation_error}
FountProbe.compare(before, after_model, params, clients, opts \\ [])
FountProbe.execute(model, requests, clients, opts \\ [])
# ordered reports; request objects select only catalog tools
```

`clients` is `%{system_one: client, inference: client_or_nil}`. Deterministic operations need neither client. Missing required clients return explicit errors. The optional history reader is a function receiving a screenplay/revision ID and returning the exact immutable model; it performs no model calls.

The tool catalog is a static map to existing functions. An external agent can invoke it through `mix fount.probe --request ... --json`; Workshop calls the same API. A model selects a tool, scope and parameters; it cannot select modules, functions, SQL, filesystem paths, native shell commands or arbitrary reducer code.

## Report envelope

```text
id, tool, version, screenplay_id, primary_revision_id, source_revision_ids
status: complete | partial | failed
request: normalized tool parameters
profile: id, version, sha256
coverage: inspected targets, excluded targets/reasons, retrieval mode, projection gaps
findings: [{id, kind, summary, targets, evidence_ids, status, measurements}]
data: tool-specific JSON
annotations: derived typed Fount annotations
graph: optional entities/events/relations with evidence
provenance: state hashes, Prepared fingerprints, requested/resolved model,
            provider response/request IDs, actual usage, elapsed time
errors: [{input_id, code, message}]
```

Revision source lists include all historical/candidate models used. A complete report means all scheduled requests completed, not that every possible screenplay problem has been detected. Partial reports retain successes and missing inputs; callers may not treat them as a clean check.

Prepare each common question battery once. Use `SystemOneSDK.evaluate_stream/4`; associate results through zero-based `batch_index`, including errors. Unknown typed answers remain missing/error, never a zero probability. No auto-generated explanatory citation is attributed to Jev.

## Shared decision rules

Default Noul policy: `supported` if p >= .8; `not_supported` if p <= .2; otherwise `uncertain`. Missing context can change a low answer to `insufficient_evidence`. Noul has no independent provider confidence.

Choice retains the complete distribution and provider confidence. A usable selection requires confidence >= .7 and top-two margin >= .15 by default; otherwise report `uncertain`. Score retains provider score, distribution and confidence; do not round it into a factual ordinal. Thresholds are configurable product defaults, not calibrated guarantees.

A semantic constraint tests probability mass in an allowed region. Noul `expected: true` uses p; `expected: false` uses 1-p. Choice sums probabilities for allowed option keys. Score sums probabilities at allowed rubric indices. `pass` if allowed mass >= .8, `fail` if <= .2, otherwise `uncertain`; Choice/Score confidence below .7 makes it uncertain. Optional explicit probability-range policies compare p directly, with caller-provided inclusive limits. No invented error bars.

Negative intent is encoded without sign ambiguity: proposition “Mara knows the ledger is forged”, expected false. Do not ask “Mara does not know” and then require a low probability as though it were the positive proposition.

## Tool catalog and algorithms

### T01 `inventory` and `extract_story`

Inputs: scene selection, extraction kinds (`events`, `propositions`, `goals`, `knowledge_access`, `props`, `commitments`, `relationships`, `timeline`) and optional writer question. Inventory starts from deterministic headings/cast/word counts. Inference proposes concise scene summaries and candidate records with exact evidence IDs/spans. Each record states its claim, subjects, reading position, kind and uncertainty. Validate every ID and quote, and keep extraction separate from canonical authored metadata.

Use one scene per extraction context by default; adjacent context is explicit. Maintain proposed coreference links separately from confirmed cast identity. Jev Choice can classify a relation as supported/plausible/unsupported, but high confidence does not turn extraction into authored truth.

Output: scene inventory, candidate records, evidence registry, unresolved aliases and access assumptions. Tool failures leave affected scenes uninspected. W01 can operate directly on an empty draft brief; it does not need fictitious extraction results.

### T02 `search`

Inputs: free-text query, structural filters, revision scope and `mode: retrieve | inspect_all`. Structural filters include cast speaker/reference/presence, scene range, element types, omission/note/boneyard inclusion, location, authored sequence/storyline and revision IDs.

First apply exact structural filters. Use PostgreSQL full-text search when persisted, and documented Unicode token matching in memory for pure inputs; ranking need not be identical; exact phrase matches are available. Inference may suggest query expansions, then Jev evaluates relevance against the original query. `inspect_all` evaluates all eligible scene inventories and opens relevant passages. Return top results with relevance distributions and exact excerpts. If only a retrieval subset was considered, do not claim that no establishment exists elsewhere.

Output: ordered hits with scene/block/element/revision IDs, excerpt, relevance, matched filters, candidate counts and coverage. W08 applies this over explicit historical revisions and removed material; T02 never mixes revisions without labels.

### T03 `check_constraints`

Inputs: explicit constraint IDs/specs and model revision. Deterministic constraints include pinned text/IDs, element counts, relative scene order, word limits, required note status and allowed edit scope. Semantic constraints carry proposition, perspective, cutoff, Noul/Choice/Score shape and expected policy. Unknown deleted targets become `unresolved`.

Build states according to 06; compile one battery for compatible state/perspective groups; evaluate with the shared rules. Report exact deterministic results separately from model estimates. Check authored declarations about intended outcomes against actual pages; do not include the desired answer as evidence.

Output: one row per constraint with normalized spec/hash, value/distribution, result status, target evidence and unmet conditions. A semantic fail is a review concern; pinned exact text or invalid scope is an edit-validation error.

### T04 `knowledge_trace`

Inputs: proposition, subjects (`audience`, `reader`, cast IDs), scene points/range, access mode, optional suspicion rubric, optional behavior element IDs and intended reveal point. Question wording distinguishes evidence to know, reasonable inference, belief and behavior; do not collapse them into one variable.

Build a cumulative perspective state for each selected reading point. Questions include “Does the supplied accessible evidence establish [proposition] for [subject]?” and, when requested, “Does this selected action require [subject] to already believe [proposition]?” Behavior uses only the selected action plus appropriate prior context. Suspicion is an explicit 0–4 rubric from absent through possibility/plausible/strong/apparently conclusive evidence.

Output: per-subject curve, first supported point, all later drops, evidence access coverage, possible mismatch findings, and audience-minus-character probability differences labeled `information_difference`. Never label the difference a measured suspense level. Flag an early reveal only against the writer's intended point. Unknown access prevents a definitive impossible-knowledge claim.

### T05 `locate_boundary`

Inputs: scene ID, predicate/constraint, perspective, optional starting context and threshold (default .8). Evaluate baseline and every legal ordered group prefix. Find the first pair where prior p < threshold and current p >= threshold. If baseline already exceeds threshold, return `already_supported_at_entry`. Also return all crossings/drops and the complete curve. Empty or incomplete curves cannot establish a first crossing.

Localize to a group, not an arbitrary byte or one dual-dialogue partner. A crossing points to the newly included group and all prior input evidence. It does not prove the group's causal necessity. No bisection optimization ships in this release; screenplay interpretation need not be monotonic.

### T06 `dependencies`

Inputs: target event/proposition/element or changed/deleted targets, scene scope, optional candidate extracted records. Retrieve possible setups/causes/usages across the selected draft. Evaluate exact source pairs with separate Nouls:

- Does A establish the object, ability, information or rule used by B?
- Does A plausibly cause/enable/motivate B? Choose the relation type separately when supported.
- Does B still have support in the supplied alternative evidence if A is removed?
- For an optional setup craft question: does A serve an immediate purpose in its own scene?

Represent typed event/proposition nodes and evidence-grounded edges in the existing semantic graph. Store each evaluated pair, probability and relation type; unsupported and untested edges remain distinguishable. Deterministic traversal returns dependents and alternative supports, with cycles allowed because relationships can be mutual. Use visited sets; no assumption that the entire story is a DAG.

Output: supported/uncertain dependency graph, affected later targets, alternative establishments and proposed missing bridges. Claims that a payoff has no discovered support include retrieval coverage. Graph reachability identifies candidates for review; rerun actual affected checks on the edited draft before claiming a consequence.

### T07 `continuity`

Inputs: selected characters/props/facts or changed targets and a scene range. Inference extracts candidates for location, ownership, physical state, explicit time, promises and relationship state. Keep evidence and possible aliases. Pair adjacent relevant records in story order only when story chronology is known; otherwise use reading order and mark chronology uncertainty.

Jev judges whether a transition contradicts established state, has an explicit plausible explanation, or remains unknown. Exact heading/time differences are useful observations; `NIGHT` followed by `CONTINUOUS` alone is not a contradiction. A missing prop transfer can be an unshown event. Return possible repair sites and any known source that supports the later state.

Output: transition rows and evidence-linked possible contradictions/missing bridges. W03/W04 use these to propose actual repairs. Do not automatically add inferred continuity facts to the canonical draft.

### T08 `scene_mechanics`

Inputs: scenes/sequence, optional character/objective focus and writer concern. Inference proposes scene intentions, obstacles, choices and turn/tactic candidates. Jev verifies local claims and evaluates descriptive dimensions: new problem, decision, changed plan, changed relationship, consequence, objective pursuit; new information compares the scene against relevant prior context. Setup/payoff is delegated to T06 rather than guessed from a local scene alone.

For dialogue tactics, choices are supplied from explicit writer objectives or validated extracted candidates plus `other/unclear`; retain a distribution per group. Consecutive similar tactics are an observation. No code declares a repeated tactic defective or the scene ending dispensable.

A scene function table includes per-dimension p and inspected scope. A run of scenes with low support for selected changes is a potential explanation for the user's concern, not a dead-scene verdict. Entry/exit economy compares proposed later-entry/earlier-exit candidates with required scene outcomes and dependencies through T12.

### T09 `dialogue`

Inputs: scenes, cast selection and requested lenses (`exposition`, `subtext`, `responsiveness`, `repetition`, `tics`). Exact word/phrase and direct-address counts are deterministic. Inference identifies information statements and potential duplicate beats. Jev checks whether the listener already has the information, whether the speaker has a scene-specific reason to say it, whether adjacent turns respond to one another, and whether the same audience information is repeated.

A subtext question asks whether a line states the emotion/intention explicitly and whether this conflicts with the writer's request for concealment/deflection. Direct speech itself is allowed. Preserve useful hesitation, connective phrases and genre conventions. Return exact turns plus alternative writing opportunities; generation remains Workshop's responsibility.

Output: dialogue findings, duplicate pairs, tic counts by character, uncertain listener access and suitable rewrite targets. A flagged phrase is never deleted automatically.

### T10 `voice`

Inputs: 2–8 candidate cast IDs, evaluation range, optional writer profiles, training IDs and comparison groups. Default choose up to 8 training turns and 20 test turns per character, deterministic by evenly spaced reading positions. Require at least 3 distinct training turns and 3 eligible test turns per character unless the writer supplies a voice description. A description removes the training minimum, not the test-count disclosure. Test turns need at least 6 words. Return insufficiency rather than padded samples.

Normalize whitespace, case and known name markers before deduplication. Choose training turns first, then evenly spaced test turns from the remaining eligible distinct lines. Exclude tested turns and normalized duplicates from training. Blind state rules are in 06. One Choice question uses opaque voice labels. Retain every distribution and actual label outside model state. Soft matrix `M[a,b] = mean(p(b) over eligible turns actually spoken by a)`. Hard matrix counts argmax selections; ties follow declared option order. Keep skipped/uncertain counts separate; missing responses do not enter denominators. Optional normalized entropy is diagnostic data only.

For early/late drift, use the same fixed training profiles and candidate set, disjoint evaluation groups and explicit group counts. Unequal samples are displayed. W05 can instead evaluate conformity to a requested new voice using a Noul plus meaning/outcome constraints; it must not require sounding like the old version.

### T11 `action`

Inputs: action selection and writer direction. Deterministic outputs include word/paragraph counts and available actual rendered line counts. Jev can distinguish visible behavior/sound, explanatory interior prose, spatially unclear action and explicit camera instruction. Inference can identify visual beats and candidate paragraph split positions with source spans.

Return opportunities relevant to the requested pass: externalize a crucial inference, clarify position or action/reaction, separate visual beats, remove redundant explanation. Do not require every action line to be literally photographable; prose can orient a reader. Do not use Fountain source line count as printed density. Paragraph layout findings remain unavailable until actual layout is known.

### T12 `compare`, `scene_lift`, `ablate`

`compare` accepts two revisions and the same constraint specs/profile. Return source/structural changes, affected constraints, before/after values and semantic deltas. A changed question/profile is marked `not_comparable`; a missing target is `unresolved`. For Noul delta use p_after − p_before; for Score report score and allowed-mass changes; for Choice compare the same option-domain probabilities. Existing failures remain visible separately from newly failed checks.

`scene_lift` speculatively omits selected scenes through core edits and evaluates user constraints plus T06/T07 checks of affected later targets. Return inspected consequences and candidate repair sites. Do not persist or accept the experimental model automatically. The phrase “safe to cut” is not an output status.

`ablate` removes each explicitly selected clue/group from separate temporary copies and reevaluates one selected proposition at the same cutoff. Return baseline p, changed p, delta and evidence removed. This is evidence sensitivity within the chosen evaluation, not proof of real audience causation. W03 may use it to choose where a delayed reveal needs rewriting. No combinatorial search over every subset.

### T13 `strategy_contrast`

Inputs: the writer brief and 2–5 strategy cards from one session. Jev evaluates pairs: “Do these approaches change the causal route, character choice, source of resistance or disclosure in materially different ways?” Inference may supply a short explanation grounded in the two cards. Output similarity flags and differences; never a best-draft score. Required constraints are checked separately. This tool helps W01/W02/W09 request a new approach when alternatives merely paraphrase one another.

## Planning and explanation

`FountProbe.plan(model, question, inference_client, opts)` returns hypotheses and catalog requests with reasons. The caller validates names, IDs, parameters and estimated call counts, executes requests and supplies reports to `FountProbe.explain`. A follow-up plan can request more relevant evidence. Plans have no edit operations. Workshop uses the findings to select or generate strategies and then calls its own proposal generator.

Use separate prompts for extraction, investigation, explanation and creative generation. An explanation is not forced to omit raw evidence: it receives the selected exact excerpts and results it needs to make a useful interpretation. It cannot cite an uninspected scene as checked evidence.

## Profiles

Store profiles under Probe `priv/profiles` with `id`, `version`, `tool`, `questions`, `thresholds` and `projection`. Questions use literal string keys, type, instructions and optional criteria/ordered levels. Compile through the SDK constructors, not direct manipulation of Prepared fields. Store generation/pass prompts under Workshop `priv/prompts` and `priv/writing_profiles`.

A profile changes wording or thresholds for an existing tool. It cannot define new executable operations or an arbitrary orchestration language. Profile SHA-256 and SDK Prepared fingerprint are distinct recorded values. The reference defaults in `contracts/profiles.json` cover the shared policies; create the feature-specific question assets from the exact questions and rubrics in this document.

## Catalog request shapes

Each catalog entry exposes its JSON input schema and `requires: [system_one, inference, history]` as applicable. `execute/5` accepts an ordered list of `{id, tool, params}` with unique string IDs, returns the same request order, and records invalid entries individually. `plan/4` returns `{hypotheses, requests, open_questions}`; hypotheses have `id`, `claim`, `reason`, and request IDs. `explain(model, question, reports, inference_client, opts)` returns an evidence-validated interpretation. It performs no editing.

A `selection` is `{whole_screenplay: true}` or `{targets: [typed_target]}`. A `point` is `{scene_id, through_element_id}`; null `through_element_id` means scene entry. Scene exit uses its final legal group ID. A `projection` is `page_reader`, `audience_estimate`, `character_access`, or `blind_dialogue`, with `character_id` required for character access. History readers and comparison models are supplied as trusted function options, never serialized callbacks or arbitrary file paths. Defaults use the current loaded revision and performed content.

| Tool | Required parameters | Optional parameters / defaults |
| --- | --- | --- |
| inventory | selection | `include_summaries: true`; false is deterministic only |
| extract_story | selection, `kinds` | `question`, `adjacent_scenes: 0` |
| search | `query` | `selection: whole`, `filters: {}`, `revision_ids: [current]`, `mode: retrieve`, `limit: 20`, `exact_phrase: false` |
| check_constraints | `constraints` (full specs or adopted IDs) | `selection` if testing a replacement range; otherwise constraint targets determine state |
| knowledge_trace | `proposition`, `subjects`, `points` | `access_mode: evidence`, `suspicion: false`, `behavior_element_ids: []`, `intended_reveal_point` |
| locate_boundary | `scene_id`, `proposition`, `projection` | `character_id`, `threshold: 0.8`, `include_prior_context: true` |
| dependencies | `targets` (event/proposition IDs from an explicitly supplied report or typed screenplay targets), selection | `record_report_ids: []`, `include_alternative_support: true`, `inspect_setup_purpose: false` |
| continuity | selection | `subjects: []` means discovered relevant entities, `changed_targets: []`, `record_report_ids: []` |
| scene_mechanics | selection | `character_id`, `objective`, `concern`, `include_tactics: false` |
| dialogue | selection, `lenses` | `character_ids: []` means all selected speakers |
| voice | `character_ids`, selection | `training_targets`, `profiles`, `comparison_groups`, defaults/sample rules in T10 |
| action | selection | `direction`, `layout_report_id`; without layout report printed-line metrics are unavailable |
| compare | `before_revision_id`, `after_revision_id`, `constraints` | `profile_id`; both actual models supplied by caller or resolved through the authorized reader |
| scene_lift | `scene_ids`, `constraints` | `consequence_scope: whole_screenplay` |
| ablate | `groups`, `proposition`, `point`, `projection` | `character_id`; each group has ID and ordered typed targets |
| strategy_contrast | `brief`, `strategies` | no artistic-ranking parameter |

Search filters: `scene_ids`, `character_ids`, `character_role: speaker|reference|declared_present`, `element_types`, `location`, `authored_collection_ids`, `include_omitted`, `include_notes`, `include_boneyards`. Omission/comment flags default false. Selection plus filters intersect. A requested revision not supplied or available through the authorized reader returns an error for that revision; do not quietly search only the current one. `limit` controls returned hits, not permission to label uninspected material checked.

`subjects` in knowledge_trace is a list of `{"kind":"audience"}`, `{"kind":"reader"}`, or `{"kind":"character","character_id":uuid}`. `access_mode` is `evidence` by default; `writer_declared` restricts to explicit access declarations. Intended revelation controls findings, not the evidence shown to the model. Evidence mode may use validated extraction with uncertainty as described in 06.

`ablate.groups` and `scene_lift` are pure experimental edits. If a tested target disappears, return unresolved instead of evaluating against the wrong surviving element. Comparison reports name both inputs and any generated temporary revision IDs. Return unsaved experimental models in an in-memory `transient_models` sidecar, excluded from the JSON report envelope. Pass them as `source_models` to `Persistence.save_report/3` to save the immutable evidence and report together; a temporary comparison returned only in memory need not be persisted. Temporary experiments are not accepted writing candidates unless Workshop explicitly creates one for the writer.

Tool-local profile question keys are stable strings. Domain validators reject unknown fields, malformed IDs, inappropriate projections and empty required lists before paid calls. `clients` in Probe uses `system_one`; Workshop's service field `jev` maps explicitly to that key. Do not make a caller guess two spellings at the same interface.
