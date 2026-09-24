# Context, perspective and evidence

## Context is selected for the writing task

Workshop's creative context and Probe's evidence state have different purposes. A creative rewrite often needs the ending, later setups, character notes and writer intentions so it can repair the draft. A test of what a character or audience could know at an earlier point must exclude later information. Build both explicitly; never reuse a rewrite prompt's context as a knowledge-test state.

`FountWorkshop.Context.build(model, brief, reports, opts)` returns a context packet with: editable targets and exact text; immediately adjacent scenes; relevant cast/voice directions; protected material; required before/after conditions; relevant dependencies; selected historical material; and an inclusion manifest. Broad inventories are discovery aids. Before editing a scene, retrieve its exact current content.

For long drafts, create one derived scene inventory with scene ID, heading, cast references, short summary, proposed events and evidence IDs. It is revision-specific. Inference extraction operates scene by scene or on a few neighboring scenes. An operator may scan the entire inventory and request exact scenes next. Never generate an edit from a summary when the target text has not been supplied.

If the context cannot fit the configured state/request limit, return the exact oversize selection or process independent scenes as an explicitly recorded staged pass. Keep global brief/protected conditions consistent across those calls. Do not silently remove middle scenes or summarize protected text.

## Evidence reference

Every observation about existing writing uses:

```json
{
  "evidence_id": "ev_17",
  "screenplay_id": "UUID",
  "revision_id": "UUID",
  "target": {"kind": "element", "id": "UUID", "span": null},
  "excerpt": "Exact current element text",
  "role": "input_context"
}
```

`evidence_id` is local to the report, not a global canonical ID. Validate quoted excerpts against the referenced revision, including spans. A model may return evidence IDs supplied in the prompt; it may not fabricate an ID or quote. An incorrect citation yields a validation error or removes the unsupported explanation statement with a diagnostic. Do not present it as verified.

Separate **input context** (what the evaluator saw), **candidate support** (passages extraction suggests are relevant), and **tested support** (a specific relation actually evaluated). Jev's typed answers do not spontaneously supply explanatory spans. If only a whole scene was evaluated, the finding can point to that scene; it cannot claim that one particular line caused the answer without another test.

Every state records its exact canonical JSON hash, source IDs, perspective, included/excluded targets, context completeness and any model-derived projections. This provenance is available in report JSON without filling the main writer review with implementation detail.

## Reader and audience views

`page_reader` includes the performed draft's action, dialogue, lyrics and meaningful scene context up to the cutoff. Remove standalone and inline notes, boneyards, omitted scenes, title metadata, outlines/synopses and model reports. Fountain emphasis is converted to plain text for evaluation while exact original evidence remains addressable. Scene headings give location/time context but are not automatically dialogue heard by characters.

`audience_estimate` uses the same cutoff and excludes metadata that a viewer would not necessarily receive: internal cast catalog biographies, true identities embedded only in a cue, writer explanations and private facts. For prose that mixes observable action and internal explanation, Inference can propose observable evidence units with source spans. Jev can check whether the source actually supports presenting that unit. Record that this projection is inferred from the page, not an observation of a finished film.

A writer can supply an authored `perspective_access` item to declare a particular visual/audio beat visible, hidden or ambiguous. This is a design declaration; the report indicates it. Do not treat a character cue naming the killer as proof that the audience has seen the killer's identity. Use neutral cue labels for unrevealed identities when declared; absent an identity-visibility declaration, report the ambiguity instead of certifying a mystery reveal.

Default reveal workflows use `audience_estimate`; an explicit reader-clarity pass uses `page_reader`. Reports label which question was tested. Apparent audience knowledge derived from a script is always an estimate.

## Character view

A character's appearance, reference or speaking cue is not sufficient evidence that they observed every event in a scene. An offscreen voice, overheard conversation, private gesture, telephone call or intercut can create different access.

Build an access ledger with this shape:

```text
character_id
source revision and exact source elements/spans
evidence unit text
channel: sees | hears | is_told | prior_knowledge | inference
access: writer_declared | text_supported | plausible | unknown | denied
support probability/confidence where evaluated
chronology: reading_order or explicit story_time label
```

Access ledger entries are derived report data unless the writer authors/adopts them. For automatic extraction, Inference proposes evidence units and a reason for access using exact source references; validate IDs/quotes, then evaluate each proposed access relation with Jev where interpretation is needed. `text_supported` requires `P(supported) >= .8` and Choice confidence >= .7. A character's own explicit utterance can be included as their behavior; it does not automatically establish that their claim is true.

Character state includes writer-declared and text-supported evidence units, with `plausible` units supplied in a separately labeled uncertainty section when requested. Unknown/denied units are excluded. Supply only the accessible fragment or faithful evidence unit; do not paste the full source paragraph if it also discloses hidden information. Keep excluded text outside the request, in the evidence registry for later inspection.

Writer-declared prior knowledge is valid context for a character if its as-of point allows it, but does not imply audience knowledge. Lies, beliefs and true facts are separate fields. An explicit lie can establish that a character heard a claim while leaving truth and belief uncertain. Tests of “could infer” and “believes” are separate questions.

Default trace reports both the estimate and access coverage: unresolved access candidates, uninspected scenes and excluded plausible units. If missing access could change the answer, classify a low-support result as `insufficient_evidence`; do not declare impossible knowledge. A behavior mismatch is phrased as a possible unsupported action with exact evidence, not a contradiction proven by absence of a cue.

Do not require the writer to annotate every scene before using the feature. Automatic ledgers support discovery with visible uncertainty; authored access fixes particular ambiguous cases.

## Order and simultaneous events

Knowledge-as-presented follows screenplay reading order. Story chronology is a separate inferred/authored ledger, needed for flashbacks and continuity. `CONTINUOUS` suggests local continuity but does not prove elapsed time or identical physical conditions. Explicit `story_time` authored items can identify day/time/order; extracted labels remain hypotheses.

A cutoff never includes later elements, scenes, writer-intended outcomes or an explanation created from the complete screenplay. Prefixes include the baseline plus complete action/dialogue groups. Dual dialogue partners form one simultaneous group; neither side becomes artificially available first. A flashback can disclose past information to the audience at its present reading position without implying that a character learns it then.

## Blind dialogue view

For voice attribution, remove tested cue, speaker/cast IDs, scene ID/ordinal, parentheticals, speaker-identifying headings, neighboring labeled lines and the actual label from model state. Keep mapping and actual speaker outside the request. Replace known cast names/aliases in dialogue and training samples with a common neutral name marker so specific names cannot identify a character.

Candidate options are opaque labels `voice_a`, `voice_b`, etc., mapped locally to cast IDs. Profiles contain writer-authored voice direction or held-out example lines. Do not feed whole biographies, plot roles, scene-specific information or the tested line into the profile. Keep train/test IDs disjoint, exclude duplicates after normalization, and report exclusions.

For a rewrite toward a new requested voice, evaluate the desired voice description and preserved meaning. Blind attribution to the old voice is optional diagnostic evidence, not a required success criterion. Distinctive vocabulary alone does not prove the rewritten character is compelling.

## Generation, explanation and inventions

Generated strategies may deliberately invent events, motives, props or scenes within the brief. They label those as `inventions` and state their implications. A generated invention cannot appear in an analysis report as if it was in the original screenplay.

Explanations receive the brief, completed tool results and actual selected evidence excerpts. Restrict citations to the evidence registry. Explanations may interpret uncertain findings and propose possibilities, but may not turn an unevaluated hypothesis into a checked fact. Keep the writer's creative instruction separate from screenplay text so inline notes and dialogue are treated as material rather than software instructions.
