# Creative workflow requirements

This document specifies the writer experience before implementation details. Every workflow returns actual draft objects and a readable review packet. Shared mechanics are specified in 09; agent tools are specified in 07.

## Shared vocabulary and writer control

A **brief** records the writer's purpose, existing material to work with, desired effect, protected material and permission to invent or alter story facts. A **strategy** is a proposed dramatic approach with a beat plan and consequences. A **candidate** is an immutable complete screenplay revision created from one base and an ordered set of edit groups. A **change group** is a coherent piece of a proposed revision that can be selected as a unit. A **session** records a particular writing request, its alternatives, evidence and decisions so work can resume.

These are domain objects: they exist because writers need to explore, compare and reuse writing. A strategy is optional for a one-line polish and useful for a new scene or structural rewrite. The writer can supply a strategy directly. Do not force a planning interaction before every small change.

A request has `mode: explore | draft | revise | diagnose`, a workflow ID, a base revision, an instruction, a selection, optional constraints, and `alternatives` (default 3 for exploration, 1 for a pass). `explore` returns strategies; `draft` materializes selected strategies; `revise` can produce strategies and candidates in one invocation; `diagnose` returns evidence and proposed next moves, with candidate generation explicitly requested or already authorized by the instruction.

Changing the accepted draft always requires `accept`. Saving a strategy, note, session, report or candidate is allowed without that action. Candidates can be printed, rendered and edited before acceptance.

## W01 — Develop, continue and bridge

Inputs: premise or notes, optional selected beat plan, placement (`start`, `after_scene`, `between_scenes`, or `replace_range`), cast/setting brief, intended end state, and constraints. An empty screenplay with a writer brief is valid input.

1. Assemble the writer brief, the preceding and following scenes when present, relevant cast material, established facts and protected downstream requirements.
2. Ask Inference for 2–5 approaches with distinct dramatic mechanisms. Each describes the action, resistance, discovery or choice that makes it different, its ending and any new story inventions. New facts are proposals, not discoveries about the existing draft.
3. Show approach cards with a short beat plan and the passages or requirements they preserve. A writer can edit an approach or request a different route.
4. Materialize selected approaches as typed scene/element edits. Generation may include action, dialogue, silence, images, scene transitions and new cast proposals. It does not have to fill a fixed beat template.
5. Check entry/exit conditions, required information and protected text; identify consequences of new inventions. Return pages in context, not only an outline.

For a bridge, the following scene is an exit constraint: the new pages must put the characters in a plausible position to enter it. For a continuation with no ending specified, the model may propose endings and explicitly identify them as inventions. The system must not ask the writer to supply all of the creative answers before it can help.

Acceptance: starting with only a brief, create two different scene candidates, reopen them, edit one, and accept it. Starting with two existing scenes, insert a bridge and preserve both original scene IDs. New cast entries and notes must be represented in the candidate and saved atomically if accepted.

## W02 — Audition, compare and combine

Inputs: selected material and instruction, strategies from W01/W09, or existing candidate IDs. Default three alternatives. Writer-specified approaches take precedence over generated approaches.

Each alternative is shown with its actual pages, changed scene list, dramatic approach, protected-item checks and tradeoffs. Pairwise Jev checks may identify similar approaches; they cannot declare which scene is artistically best. When two alternatives use essentially the same mechanism, label that result and allow one additional generation for diversity. Keep all results available.

`audition` shows the prior scene, candidate scene/sequence and next scene as a continuous read, with optional PDF and table read. `combine` accepts explicit group or element-range selections from alternatives sharing a base. Copy compatible changes; for overlaps show the competing passages and use the writer's selected version. A request such as “A's opening with B's exit” authorizes Inference to write the connecting material, with the selected passages pinned by default.

Combination creates a new candidate and reruns affected checks. It never marks the source alternatives accepted. A partial choice is compared against the base, not against a discarded candidate that happens to be newest.

Acceptance: combine one group's dialogue from A with B's ending, detect an overlapping target, resolve it by explicit selection, generate a required connective beat, and save a coherent third candidate with source-candidate attribution.

## W03 — Change a story decision and repair the draft

Inputs: requested change, target proposition/event/scene/character, destination if moving material, exact protected material, and scope. Default scope is the current screenplay; a writer can restrict repair to a selected range.

1. Identify the current establishment and uses of the changed fact, reveal, motivation or object. Gather exact evidence with search, knowledge, dependency and continuity tools.
2. Build a change map: primary edit, dependent beats, possible dependencies needing judgment, protected beats, and unaffected material. Explain why each scene is included.
3. Generate one or more creative repair strategies. For a delayed reveal, strategies may preserve suspicion through a different clue, replace a conversation with evasive action, or change a later character decision.
4. Produce edit groups for the primary change and all necessary repairs. Groups declare dependencies so a writer cannot accidentally take the reveal move while unknowingly discarding its required setup repair.
5. Evaluate the changed draft at the old and new reveal points and at affected later scenes. Compare baseline and candidate so existing defects are not attributed to the new rewrite.
6. If a requested check fails, allow a repair pass with the failed requirement and actual evidence. Retain the unsuccessful candidate for inspection. Stop after the configured rounds and expose remaining concerns.

A scan over all scene summaries is a discovery step; verification opens exact source. “No identified consequence” must name the scope and evidence checked. Unknown links remain unknown. Reports may use possible/supported classifications; the workflow must not claim a complete causal proof.

Acceptance: move the ledger reveal from scene 3 to scene 6 in the supplied fixture; change Mara's earlier accusation, preserve her reason to go to the ferry, and keep the key transfer required by scene 7. The result must contain actual edits in all affected scenes and a comparison of reveal knowledge before/after.

## W04 — Rebuild a sequence and compress a draft

Inputs: scene range or named sequence, target scene count and/or page reduction, required entry/exit conditions, pinned scenes/lines, and creative priorities. A page target requires the same real PDF renderer/settings for baseline and candidates.

Infer a compact account of what the sequence currently accomplishes, then generate different route plans. For example: combine discovery and confrontation; make a failed attempt cause the next scene; remove an intermediary and transfer its necessary information into a different relationship. Each plan declares moves, merges, splits, omissions, new scenes and dependency repairs.

Generate complete candidate pages. A merge must decide where each surviving element and dialogue block belongs. A split must introduce a proper new scene heading. Preserve IDs for surviving material and record replacement lineage for rewritten material. A lifted scene is an experimental candidate, with downstream checks and no automatic claim that deletion improves the film.

Measure words exactly and pages by rendering. If page count cannot be measured, state that it is unavailable and show word changes; never translate words to claimed PDF pages. If the target cannot be met within protected material, return the best candidates with the shortfall and a separate option that relaxes a named constraint; do not silently violate it.

Acceptance: compress five fixture scenes into three, generate two different routes, preserve an exact line and a later setup, render both and report actual page counts. Do not pad the sample screenplay to manufacture a page-saving claim.

## W05 — Character-focused writing

Inputs: cast ID, direction, optional exemplars and scenes, and protected plot/outcome constraints. Separate requests to alter voice from requests to change choices or an arc.

Build a character workspace containing ordered speeches, relevant action, confirmed appearances, references, scene partners, writer notes, decisions and historical variants. A reference to the person is labeled as a reference. Show the evidence used to infer a voice or agenda; the writer can replace the inferred profile.

Propose a progression across scenes rather than giving the character a catchphrase everywhere. For a voice-only request, preserve proposition content and scene outcome while rewriting exchanges with enough partner context to remain responsive. For an agency request, propose changed choices and resistance, and invoke W03's consequence check. A voice rewrite is allowed to sound different from its baseline; the check tests the requested profile and retained scene purpose, rather than rewarding similarity to the old problem.

Group edits by scene while retaining a character-wide summary. Permit selection of individual scenes and recheck interactions after partial selection. A partner's reply may require a linked change; disclose it.

Acceptance: change Dan across at least three scenes, preserve selected outcomes and secret knowledge, and show one change in his response to Mara that goes beyond vocabulary substitution. Store the approved voice direction as authored metadata only if requested.

## W06 — Notes to a coordinated revision

Inputs: Fountain notes, external note text, saved writer notes or a collection of notes. Capture the exact note text and origin. Inference distinguishes the expressed symptom, possible underlying problem and suggested solution; those are hypotheses for the writer to inspect.

Group related notes and expose conflicting instructions. Offer creative approaches for ambiguous substantive notes, then produce one plan of edits. A simple local note can go directly to a proposal. Explicit constraints and pinned material are never overwritten by a guessed interpretation of a note.

A note can have several candidate responses. Acceptance resolves only the notes marked addressed by the accepted groups, with links to the accepted revision. Rejected alternatives leave notes open. If a Fountain note must disappear from the export, its removal is an explicit edit in the accepted group; the original note survives in history.

Acceptance: process one local dialogue note and one sequence note; resolve only the local note when its group is accepted. Preserve an unrelated note and the unaccepted structural suggestion.

## W07 — Creative passes

Ship profiles for dialogue/subtext, action/visual clarity, brevity, dry comedy, tension, and user-defined direction. Profiles contain prompts and suggested inspections, not universal correctness rules. Custom direction uses the same implemented pass operation, without defining executable modules or arbitrary workflow syntax.

The pass selects relevant material, identifies opportunities, writes alternatives, checks the writer's constraints and presents changes by scene/group. A comedy pass can create a reversal, visual gag, awkward behavior or callback; it must not merely append jokes to every line. A visual pass can replace dialogue with behavior. A tension pass can alter withheld information or competing aims. These may need scene edits beyond text replacement.

Use deterministic counts for repetition and paragraph size. Use Jev for questions such as whether information is repeated, an exchange remains responsive, an action conveys the desired implication, or a proposed joke discloses a protected fact. Direct emotional speech and writerly action prose are not automatically defects.

Acceptance: a dialogue pass changes an exchange while keeping its scene outcome; a visual pass turns an explanation into an action proposal; a comedy pass produces at least one proposed dramatic/comic mechanism with actual pages. Tests verify selection, constraints and edit handling, not that a joke is funny.

## W08 — Search, recover and adapt earlier writing

Search supports lexical/structural filters first, then model-assisted relevance over candidate passages. Include current, omitted, boneyard and explicitly selected historical revisions. Return exact excerpts, IDs and revision labels. No answer may quote text that is absent from the selected source.

`recover` can restore an exact old passage or ask Inference to adapt it to current circumstances. A three-way comparison uses the old source, current target and proposed adaptation. Character IDs must be mapped explicitly if the old and new cast differ. Duplicate imported IDs are not automatically assumed equivalent across separate screenplays.

The writer can use old dialogue in a new scene without reviving obsolete facts. Run the applicable knowledge/dependency checks and label deliberate departures from the source. Record source revision/IDs on the change group.

Acceptance: recover a key transfer from a prior draft, adapt it to a relocated scene, preserve current character identity and maintain the later use. Return both the exact recovered passage and the proposed adaptation.

## W09 — Diagnose, explore remedies and write

Inputs: a creative concern, a scope (possibly whole draft), protected material and desired number of approaches. The initial Inference pass proposes a small set of competing explanations and relevant tool requests. The application executes the requests and supplies results for synthesis. One follow-up investigation is allowed by default when evidence changes the hypothesis.

The result distinguishes findings from interpretive hypotheses. It then develops different remedies, including structural ones where appropriate. “Act II feels easy” might lead to a costly success, a failed plan that exposes a relationship, or a different character taking control; the remedy must be tied to the actual story. The writer can request pages for one or all approaches. A command explicitly requesting fixes can generate candidates immediately.

The tool vocabulary includes every implemented tool in 07. An external agent can call the same tools directly. The internal Inference loop uses structured completion requests because the supported Codex adapter does not accept arbitrary native tool controls.

Acceptance: investigate a sequence with repeated successful tactics, identify evidence for at least one plausible explanation, generate three strategy cards, and materialize two different fixes. Failure to establish the diagnosis does not prevent the model from offering clearly labeled exploratory alternatives.

## Review packet requirements

Every creative session can export `session.json`, `brief.md`, `strategies.md`, one Fountain file per candidate, source and structural diffs, `checks.json`, and `review.md`. PDF/audio are explicit additions. The packet lists accepted-head/base/candidate revision IDs, changed scenes, group dependencies, inventions, checks performed, unchecked questions, model identity and actual provider errors.

The main review page leads with the writer's request and the candidate pages/choices. Detailed probabilities and tool traces are available underneath. Never make the writer decipher a matrix to read or select an alternative.
