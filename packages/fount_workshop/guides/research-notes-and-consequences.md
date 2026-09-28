# Research, Notes, and Consequential Revision

Phase 14 keeps development material useful without turning it into screenplay truth or automatic instructions.

## Research is provenance, not authority

`FountWorkshop.Research` stores a research dossier in durable Workshop session progress. A source may carry location, retrieval date when known, rights/confidentiality metadata, and a `provider_export_allowed` decision. Recorded source content is always labeled `untrusted_content` with `instruction_authority: "none"`; quoted text cannot direct the writing runtime.

Claims carry one explicit status: `sourced`, `disputed`, `unverified`, or `deliberately_fictionalized`, and one origin: `source`, `writer_memory`, or `invention`. A sourced claim points at a recorded source. Writer memory and invention remain distinguishable from sourced material.

When the host has no web capability, `Research.missing_web/2` creates an unresolved question using only writer-supplied citations. It records `invented_references: false`; it does not pretend a search ran.

Research records do not change screenplay canon. They survive with the session until the writer chooses a concrete screenplay experiment through the ordinary candidate/review boundary.

## Notes stay separate until the writer decides

`FountWorkshop.NoteTriage.capture/4` preserves each raw note, source, confidentiality, original screenplay/revision identity, exact anchor excerpt, reader reaction, interpretation, and requested treatment. Overlapping notes are recorded as potential conflicts; they are not blended into one instruction.

`NoteTriage.decide/5` keeps the concern decision separate from the proposed treatment. A writer can, for example, accept the concern, reject explanatory dialogue, and choose a physical cue instead. Triage actions are `investigate`, `experiment`, `adopt`, `defer`, `decline`, or `ask_note_giver`.

Across drafts, `NoteTriage.anchor_status/2` and `reanchor/5` use stable identity plus exact text only:

- `exact`: the original element identity still has the exact anchored text;
- `relocated_with_evidence`: the old identity is gone and exactly one exact-text match exists;
- `ambiguous`: more than one exact-text match exists;
- `orphaned`: no exact identity/text match exists.

Fuzzy similarity is deliberately not treated as identity after a split or merge.

## A note decision becomes an experiment, not an overwrite

`NoteTriage.candidate/5` creates a normal writer-origin candidate through `CandidateAPI.manual/4`. It records the decided note IDs in the change group and preserves the full note-decision lineage. The screenplay head remains unchanged until explicit acceptance.

The call also records an explicit revision scope (`local`, `sequence`, or `whole_draft`), protected/preserved intentions, approved scene IDs, and a consequence plan. Consequences are separated into supported dependencies, hypotheses, unresolved work, checked scenes, and scenes not analyzed.

`FountWorkshop.Comparison` now includes `consequence_review`, derived from actual stable-ID page changes plus that declared plan. It reports any rewritten scene outside the approved set instead of silently widening a local change. Generator/candidate claims remain non-evidence.

## Stale candidates and rollback

Acceptance still compares against the unchanged base revision. A concurrent manual edit advances the accepted head, so an older candidate returns the existing stale-revision failure and must be reconciled with `FountWorkshop.Rebase`. Rebase exposes concrete conflicting surfaces rather than retargeting the old candidate silently.

`Fount.Screenplay.undo/2` restores the prior screenplay model content/identities into a new revision. Tests compare the serialized Fountain bytes to verify exact source restoration.

## Evidence limits

These contracts demonstrate persistence, provenance separation, deterministic anchor classification, candidate linkage, actual change comparison, and stale-write safety. They do not establish factual truth, creative quality, historical accuracy, reader response, or human preference. Optional human review remains separate evidence.
