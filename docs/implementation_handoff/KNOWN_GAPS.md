# Remaining work and review priorities

This list distinguishes **missing implementation** from **unrun verification**. All original acceptance cases remain requirements. The next agent should finish these in Fount and then produce actual evidence; do not merely downgrade the specification or relabel a partial result as complete.

## 1. First execution and source integration - release blocking

No new source was compiled or formatted by Elixir. The code is deliberately handed off as source for an agent with the proper environment. Expect formatter changes and possible compiler warnings, missed imports, shape mismatches, fixture assumptions, or Ecto SQL errors. Run the full three-package suites, not only new tests. A simple text/JSON/hash check is not evidence of valid Elixir syntax or correct application behavior.

The old convenience writing modules are retained and the new session APIs are additive. Exercise both against the stricter persistence rules. Confirm lower-bound Elixir requirements: Probe requires at least the supplied 1.19 line, and Workshop has been aligned to that lower bound in this continuation; confirm the actual transitive requirements. The recommended local environment is the already-used 1.20/OTP29 toolchain. No lockfile is fabricated. Resolve Hex dependencies locally and record their actual versions.

## 2. Typed edits, scope and candidate review - release blocking

`Candidate.scope/3` currently protects old elements outside the selected element IDs by comparing text/type/attrs. It does **not** yet fully enforce byte-span-only editing, prohibit all movement/reordering of unchanged outside-scope elements, or constrain every insertion position. Extend the contract before treating selection as a strict authority boundary. Add negative tests for insertion outside a selected scene, outside-scope movement, a span-target rewrite changing text outside its span, and a character request restricted to a subset of the draft. `Context.editable_selection/2` for character rewriting currently expands to all scenes with confirmed appearances instead of intersecting all request restrictions.

Combination and rebase have concrete source paths, but validate overlapping span operations, local references across selected groups, deleted targets, scene gaps, and writer-edited candidate replay. Rebase is intentionally conservative: some independent span edits conflict at whole-element granularity. Validate resolution input before using it; unexpected resolution shapes need stronger errors. A required dependency removed by an overlap/rebase choice must not be silently reintroduced.

Acceptance checks the stored model, hashes, reports and accepted-head lock. Its report lookup establishes same-screenplay membership, not yet every candidate/session/source-revision lineage restriction. Add tests and require result/before/source membership as appropriate. A caller-supplied report must not masquerade as a check of another candidate. Verify repeated same actor/review/content acceptance is idempotent; changed review identity conflicts.

## 3. PostgreSQL and interchange - release blocking

Run both migrations against an explicitly chosen fresh database, then test deferred heading/cue/dual links, ordering, immutable IDs and payloads, report-source references, rollback and simultaneous writers. The added race test covers two accepted edits sharing a head, not the entire candidate concurrency matrix. Do not drop or reset a pre-existing database to make tests pass.

Canonical JSON v2 preserves IDs and validates the claimed source artifact/render relationship. Strict validation of every nested unknown field and comprehensive malformed payload cases are unfinished. FDX remains an interchange adapter, not a claim of full Final Draft application roundtrip fidelity. Add/retain explicit losses for unsupported production metadata and verify emphasis, notes, scene numbering, dual dialogue and title pages. Structural Core split/merge helpers require adversarial dual/empty-side tests.

## 4. Probe completeness

The following accepted options are exposed as **partial coverage** in `FountProbe.run/5`, not silently treated as honored: extraction `adjacent_scenes`; knowledge `behavior_element_ids` and intended-reveal comparison; dependency `record_report_ids`; continuity `record_report_ids` and `changed_targets`; action `layout_report_id`. Their implementations still need to be completed. Calling a lower-level module directly bypasses that facade annotation; retain uncertainty there as well.

Dependency proposals currently favor earlier-scene relations and miss necessary same-scene setup/use edges. Add ordered events within a scene and cited reuse of saved extraction reports. Continuity does not yet have a complete story-chronology model or a dedicated reliable pronoun/relationship repair check. Unknown transfers/timing must remain unknown.

The audience projection neutralizes cue identities but still approximates the audience from page material. It can include interior prose unavailable to a viewer. Character access is more conservative and explicitly excludes unestablished access, but model-derived access is still inference, not authority. Add private-aside/overhearing/letter-reading/off-screen/flashback/dual-dialogue fixtures and exact behavior support before claiming W03 is closed.

Dialogue now uses actual preceding turns in the same scene, not merely preceding selected-character turns; rhythm and tactic checks are present. Integrated knowledge and voice lens requests remain partial and need dedicated access-aware interrogation/voice conformance wiring. Voice training selections need additional typed-target and held-out edge cases. A historical voice recognizability score must not penalize a writer-requested new voice.

Action's printed density and source-to-PDF line regions are not implemented. Do not substitute word-count estimates for measured printed lines. Search needs a comprehensive filter matrix and branch/history discovery beyond explicit revision lists and accepted ancestry.

## 5. Constraints, notes and session recovery

Semantic constraints now translate a typed observation target to a legal complete prefix. Still finish selection-scoped scene-count evaluation after sequence replacement, all typed retain/remove target checks, and prohibited-fact invention checks. The invention-policy path verifies **declared** inventions only; it cannot certify absence of undisclosed inventions. Unknown semantic results need writer review, not invented pass values.

Note conflicts are conservatively surfaced when targets coincide, not exhaustively detected across a sequence. Prove that selecting some groups cannot resolve a note dependent on omitted groups, including selecting again from an already partially selected candidate. External notes remain request data unless explicitly authored; Fountain note removal must remain an explicit edit.

Sessions persist successful candidates, source IDs, preparation context, strategy cards and spending. Resume reuses preparation and retries unfinished branches; it does not yet selectively resume each failed inspection within a cached partial preparation. Trusted library callers can request `reinspect: true`, but CLI does not expose this option. Add explicit staged retry semantics without silently spending again or shifting the original base. Failed optional semantic repair attempts should retain more detailed failure artifacts instead of only preserving the original failed-check candidate.

## 6. Writer workflow evidence and remaining features

W01-W07 have actual generation/candidate source paths and real-only entrypoint modes, but not newly generated pages or story acceptance proof. Run each fixture acceptance literally. W03 must retain the independent ferry motive and key setup/use while repairing Mara's premature accusation. W04 needs two causally distinct five-to-three routes, verified pins and **measured** same-settings PDFs. The older six-to-six-page result remains zero savings. W05 needs chosen-outcome/secret tests and partner-response repair, not only a dialogue rewrite. Each W07 profile needs its actual inspections and reviewed candidate writing.

W08 exact recovery supports deleted complete scenes from the **same screenplay** with verified historical IDs. Exact partial-scene/range recovery and cross-screenplay copy with newly allocated identities and explicit cast mapping are unfinished. Adaptation is actual generation with source lineage, not exact recovery.

W09 has a finite plan, report execution, hypothesis revision in prose, three strategies and two materialized remedies. The structured hypothesis-record contract and the allowed one-follow-up investigation cycle are unfinished. Do not describe the existing plan/explain pass as satisfying those omitted steps.

## 7. Profiles, PDF, speech and interface polish

Nine finite question assets are compiled through public SDK constructors. Effective question definitions, asset hashes and Prepared fingerprints are separate provenance. Asset threshold numbers currently describe the fixed policy; changing them alone does not change interpretation. Finish threshold dispatch and profiles for remaining dynamic tools. Generation prompts still live primarily in source rather than a complete `priv/prompts` asset collection.

PDF export makes real Afterwriting/Poppler calls and records measured page data, but A4 and arbitrary profile options are not fully honored. Requested render failure now makes review export fail while retaining the packet. Visually inspect real pages and confirm fonts, title-page treatment and settings hashes. No PDF has been rendered in this pass.

Table-read JSON/HTML and optional real per-turn WAV files are present. Dual partners share timestamps in a manifest; there is no rendered mixed master audio file. `FOUNT_VOICES_FILE` supplies explicit character-ID or cue-name to eSpeak voice mappings in CLI launchers. Speech remains optional and unrun.

CLI tools are present, but complete command-level tests, exit-code/machine-output behavior under every partial state, and paid versus pure-tool credential requirements need further testing. Probe's generic launcher currently requires clients more broadly than some purely deterministic inspections need. Do not log credentials or raw private provider exceptions to solve these issues.
