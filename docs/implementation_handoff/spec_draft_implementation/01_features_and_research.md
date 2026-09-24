# Features and screenplay research

## The product

Fount is a writing environment in which a writer can develop, audition, restructure and revise an actual screenplay with model assistance. The main output of its creative tools is usable material: alternative dramatic approaches, beat plans, scenes, exchanges, and coordinated draft changes. A writer can read every alternative in context, change it, combine it with another, or discard it.

The analysis toolkit supplies the evidence and checks that make those operations practical. It remains available to agents and advanced callers. Import/export, persistence, navigation, diagnostics and measurements support the writing experience; completing those components alone does not complete this release.

The initial delivery surface is Elixir APIs, a JSON command interface and Mix commands that write readable review packets. This gives another agent a practical writing environment without waiting for a graphical editor. The writer's command can be creative and open-ended. The implementation translates it into actual screenplay operations and returns pages that can be adopted.

## Required creative workflows

All nine workflows below ship. They share context assembly, candidate editing, review and analysis implementations. Each has a concrete specification in [01a](01a_creative_workflows.md); IDs are stable throughout this docset.

| ID | What the writer asks | Required result |
| --- | --- | --- |
| W01 — Develop and continue | “She needs his help but cannot admit why. Give me three ways this scene could happen.” Or “Build the next sequence from these notes.” | Distinct dramatic approaches, optional beat plans, then actual screenplay pages for the selected approaches. Works with an empty draft, existing scenes or a gap between scenes. |
| W02 — Audition and combine alternatives | “Let me hear the version where he bluffs, the one where he confesses to something else, and the one where she traps him.” | Separate candidate scenes in the surrounding draft; differences in dramatic mechanism explained; mix selected change groups into a new candidate and repair joins. |
| W03 — Change the story and repair consequences | “Move the reveal to the ferry. Keep the audience suspicious, but Mara must not know before then.” | A change plan, rewritten reveal and affected scenes, preserved dependencies or explicit proposed replacements, and a coherent candidate draft. Also handles a changed fact, motivation, relationship or prop. |
| W04 — Rebuild a sequence or cut pages | “These five scenes need to become three. Keep the betrayal and the joke. Give me different routes.” | Alternative sequence structures, rewritten transitions and pages, dependency checks, real rendered page deltas when requested. |
| W05 — Rewrite through a character | “Dan is too agreeable. Give him a sharper agenda throughout, without making him cruel.” | A character-focused workspace and coordinated scene/dialogue proposals, with effects on scene partners, progression and protected outcomes checked. |
| W06 — Turn notes into a revision | “The midpoint goes soft. Fix that, preserve the hospital scene, and use the idea in this old note.” | Interpretation of the notes, alternative creative solutions where appropriate, a plan of affected material, and grouped edits. Notes resolve only through acceptance. |
| W07 — Perform a creative pass | “Do a dry comedy pass.” “Make the pursuit more visual.” “Cut the explanation but keep the emotional hesitation.” | Individually reviewable edits across the requested scope, including additions and structural changes when allowed. Presets offer useful starts; the writer supplies the creative direction. |
| W08 — Recover, search and recombine writing | “Find the old exchange where he nearly admits it. Use its opening with this draft's ending.” | Evidence-linked current/historical search, exact old material, a three-way comparison and a newly adapted candidate. Old content is recoverable even when absent from the current draft. |
| W09 — Investigate a story problem and propose fixes | “Why does the last half feel too easy? Give me three substantially different fixes.” | Several explicit hypotheses, relevant investigations, findings with inspected scope, creative repair strategies, and candidate edits for selected strategies. |

These are not just names for one scene rewrite prompt. W03 must edit several affected scenes; W04 must change scene structure; W05 must work across a character's appearances; W08 must retrieve real historical material; W01 must create usable material where no existing scene is available.

## What makes the creative work substantive

Each proposed approach states what changes in the dramatic situation: who acts, what tactic or choice changes, what resistance they meet, what it costs, what the audience learns, and how the scene or sequence ends. Fields may be inapplicable; no formula requires every scene to contain all of them. Approaches that merely exchange adjectives or paraphrase the same beats are identified as similar and shown honestly. The system does not promise novelty in all generated output.

For example, a scene in which Mara needs Dan to open a locked gate can be reinvented as a bargain that costs her a secret, a bluff that turns the guard against Dan, or a shared practical emergency in which opening the gate is Dan's own decision. Those are different causal routes. A request for alternatives should explore such routes before spending calls producing several near-identical dialogue polishes.

A writer can pin an exact line, a comic beat, a scene, a reveal point, a relationship outcome or a factual constraint. Exact preservation is checked by code. Dramatic preservation is checked with evidence and Jev, with uncertainty displayed. A creative instruction to change something overrides an older preference only when the request explicitly supersedes it; contradictions are returned for resolution with a useful plan already prepared.

## Required supporting capabilities

| ID | Capability | Used by |
| --- | --- | --- |
| F01 | Fountain/FDX/JSON import/export; exact unchanged Fountain; proper spec PDF and title handling | All workflows and handoff |
| F02 | Stable screenplay IDs, typed editing, scene/sequence operations, cast/aliases, notes, omissions, dual dialogue, canonical validation | All writing operations |
| F03 | PostgreSQL revisions, saved candidates, named alternatives, partial selection, undo and history | W02–W08 |
| F04 | Writer brief, beat plans, authored intentions and constraints, separate from model suggestions | W01–W07 |
| F05 | Structural/semantic search, character and storyline collections, exact context selection | W03–W09 |
| F06 | Jev/Inference toolbelt described in 07, including knowledge, causality, continuity, scene mechanics, dialogue, voice, action and revision checks | All workflows where applicable |
| F07 | Text/structural/semantic comparison; complete provenance; explicit accept/reject; stale-base detection | Every generated edit |
| F08 | Ordered table reads and actual optional speech synthesis | Auditioning and polish |
| F09 | Three real example entrypoints and offline default tests in all three packages | Demonstration and maintenance |

The initial diagnostic feature list is retained and expanded as F06. Causal support, consequence checks, omission experiments and historical retrieval are required now because the creative workflows need them. Only capabilities explicitly placed in 13 are deferred.

## Craft research and implications

Accessed 2026-09-24. These sources inform tool questions and writing workflows. They do not validate a numerical quality score or a compulsory story structure. Summaries below are paraphrases; the detailed workflow designs are our own conclusions.

| Primary source | Relevant observation | Design consequence |
| --- | --- | --- |
| [John August: How to Rewrite](https://johnaugust.com/2005/how-to-rewrite) | Establish the rewrite goal, then identify the scenes that must change. | W03/W05/W06 begin with an intended change and a scene selection, retaining reasons for each proposed edit. |
| [Scriptnotes 377: The Second Draft](https://johnaugust.com/2018/scriptnotes-ep-377-the-second-draft-transcript) | Discusses a plan for revisions, character-focused passes and interpreting notes. | Notes produce an editable creative plan; a character pass considers the character's progression across scenes. |
| [Index cards](https://johnaugust.com/2003/index-cards) and [card practices](https://johnaugust.com/2010/10-hints-for-index-cards) | Scene/sequence cards help explore order and story points, while outlines remain changeable. | Beat plans and sequence alternatives are saved, editable objects with links to the pages they generate. |
| [Scriptnotes 609: Dialogue and Character Voice](https://johnaugust.com/2023/scriptnotes-episode-609-dialogue-and-character-voice-transcript) | Voice, responses to the other speaker, and conversational transitions matter. Small verbal fillers can perform real conversational work. | A dialogue pass rewrites interactions, and preserves useful hesitation or softening. Tic counts are evidence for selection, never an automatic deletion rule. |
| [Scriptnotes 357: Exposition](https://johnaugust.com/2018/scriptnotes-ep-357-this-title-is-an-example-of-exposition-transcript) | Information delivery can be integrated with character and events. | W07 can turn an explanation into action, conflict or discovery while checking that required information still reaches the right people. |
| [Scriptnotes 655: Conflict and Stakes](https://johnaugust.com/2024/scriptnotes-episode-655-conflict-and-stakes-compendium-transcript) | Scene wants, resistance and consequences offer concrete ways to examine conflict. | W09 investigates different explanations for a weak sequence and generates changes in choices, resistance and consequences. |
| [Scriptnotes 693: Setups](https://johnaugust.com/2025/scriptnotes-episode-693-setups-that-dont-feel-like-setups-transcript) | A plant can serve an immediate scene purpose as well as prepare later material. | W03/W04 preserve or relocate dependencies creatively; replacement setups should fit the receiving scene. |
| [Scriptnotes 695: Scott Frank](https://johnaugust.com/2025/scriptnotes-episode-695-advice-to-a-young-film-student-with-scott-frank-transcript) | Emphasizes intention and storytelling; starting from mechanical craft formulas can produce constructed-feeling work. | Creative approaches are generated from the writer's aim; diagnostic rubrics remain optional lenses. |
| [Academy rubric](https://www.oscars.org/sites/oscars/files/2025-05/Nicholl_Scoring_Rubric_0.pdf?VersionId=aXuyjFCEk2BV.xAlWb9VJ2ubCenaKb82) | Includes originality, distinctive voices, character action and emotional involvement. | Ask what an alternative changes for character and audience. Do not convert the rubric into an automatic grading system. |
| [Academy formatting resources](https://www.oscars.org/nicholl/screenwriting-resources) | Professional formatting has variation; submission drafts differ from shooting drafts. | A general spec preset hides printed scene numbers while keeping internal scene identity. |
| [Fountain syntax](https://fountain.io/syntax/) | Defines structured plain-text screenplay constructs. | Retain practical interchange and keep notes/boneyards separate from performed material. |
| [TypeSafe introduction](https://docs.typesafe.ai/introduction) | Typed probabilistic answers can be composed in code, and questions evaluate independently against shared state. | Jev checks explicit creative requirements and evidence relations. Inference creates and interprets; Fount executes and compares. |

Do not carry over the supplied context's claims that Jev is deterministic or infallible, that all direct emotion or interior description is defective, or that a probability difference measures suspense. Nor does a quiet scene, a long action paragraph, or a camera instruction automatically justify rejection. The tool can identify a possible issue, explain its relevance to the current request and propose an alternative.

## Release scope and success

A feature screenplay of around 120 pages must be workable through scene/sequence context assembly, whole-draft inventories, exact retrieval and staged generation. The system must not require the entire draft in every call, nor hide material excluded from an analysis. Limits are caller options with transparent errors and resumable saved work; defaults appear in 09. There is no fixed act template.

The strongest acceptance demonstration is a writer changing the story: delay a reveal, rebuild the affected sequence, audition different approaches, combine preferred passages, accept a coherent revision and export its actual pages. The live examples also demonstrate writing new material, a character pass and recovery from history. A release that only prints diagnoses fails this requirement.
