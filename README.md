<p align="center">
  <img src="assets/fount.svg" alt="Fount" width="200" height="200"/>
</p>

<p align="center">
  <a href="https://hex.pm/packages/fount"><img src="https://img.shields.io/hexpm/v/fount.svg" alt="Hex.pm"/></a>
  <a href="https://hexdocs.pm/fount"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="HexDocs"/></a>
  <a href="https://github.com/nshkrdotcom/fount"><img src="https://img.shields.io/badge/GitHub-repo-black?logo=github" alt="GitHub"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"/></a>
</p>

# Fount

**A screenplay revision workshop for writers who want to experiment aggressively without losing control of the draft.**

Fount lets you experiment aggressively with a screenplay without losing control of it: **ask creative questions, generate real alternate pages, trace the consequences of big story changes, mix the best pieces, hear them performed, compare them to your draft, and decide what actually becomes canon.**

It is built around a simple idea: rewriting a screenplay should not mean handing the whole script to a model and hoping it remembers what matters.

Fount keeps the screenplay itself, its revision history, its characters, scenes, dialogue, story evidence, alternate approaches, proposed changes, and accepted draft separate enough that you can try dangerous ideas without endangering the version you already have.

**Nothing becomes part of the accepted screenplay merely because an AI generated it.**

---

## What You Can Actually Do With It

Fount is designed for screenplay work such as:

* **Develop pages from a brief.** Start with a dramatic intention, situation, constraint, or story problem and generate actual screenplay material rather than another outline about what could happen.
* **Continue a draft or bridge existing scenes.** Write forward from existing pages or create the missing dramatic connection between two scenes while using the surrounding screenplay as context.
* **Explore genuinely different versions.** Ask for multiple dramatic approaches, keep them as separate candidates, and audition the alternatives instead of forcing the system to choose one for you.
* **Combine the best parts of different attempts.** Keep the entrance from one version, the confrontation from another, a passage from a third, and generate only the connective writing needed to make those choices work together.
* **Change a major story decision and repair the consequences.** Move a reveal. Change who knows a secret. Remove an event. Alter a choice. Then inspect what earlier and later scenes depended on the old version and repair the affected material.
* **Rebuild a sequence.** Replace a weak run of scenes with a new dramatic progression while preserving the facts, passages, starting conditions, ending conditions, or outcomes that still need to survive.
* **Rewrite a character across the draft.** Change not just dialogue but choices, tactics, behavior, presence, relationships, and how other characters respond, while protecting story facts that should remain unchanged.
* **Turn notes into coordinated revisions.** Apply a small note locally or let a larger note produce related changes across scenes. Conflicting or unresolved notes can remain visible rather than being silently flattened into a rewrite.
* **Run creative passes.** Work specifically on subtext, tension, visual action, dialogue, exposition, compression, character behavior, rhythm, or another declared creative direction.
* **Recover earlier writing.** Find useful material from an older revision and either restore it or adapt it to the screenplay as it exists now.
* **Investigate before rewriting.** Ask where a story problem actually begins, whether a reveal happens too early, what depends on a scene you want to cut, whether a payoff has enough setup, whether two characters sound alike, or why a scene is not producing the intended dramatic effect.
* **Hear the script.** Turn screenplay dialogue into ordered table-read material with character voice mapping and pluggable speech synthesis.
* **Compare before committing.** Inspect screenplay changes, structural differences, reports, candidate pages, and PDFs before choosing what belongs in the accepted draft.
* **Export screenplay PDFs and perform mechanical submission checks.** Render candidate or accepted pages, inspect the resulting PDF, and run dated submission-oriented checks without pretending that a mechanical check replaces reading the screenplay.

---

## The Point: Try the Rewrite Without Sacrificing the Draft

A normal AI writing conversation tends to collapse everything together.

You paste in pages. You ask for a rewrite. The model gives you something new. You ask it to change that. Then change something else. Several turns later, the original dramatic logic, the exact old wording, and the distinction between *an experiment* and *the screenplay* can become difficult to recover.

Fount treats those as different things.

Your accepted screenplay remains the accepted screenplay.

An investigation is an investigation.

A strategy is a possible dramatic approach.

A generated version is a candidate.

A manually adjusted candidate is still a candidate.

A combination of several candidates is still a candidate.

Only an explicit review and acceptance makes a revision the new accepted draft.

That means you can be much more aggressive creatively because experimentation is cheap and acceptance is deliberate.

---

## A Real Example

Suppose the second half of your feature is dying because an important reveal happens too early.

You should be able to give Fount a direction like:

> Move Sarah learning that Owen stole the money from Scene 31 to Scene 47.
>
> Find everything between those scenes that stops making sense if she no longer knows.
>
> Preserve the motel sequence and preserve the fact that Sarah already suspects Owen is lying.
>
> Give me two substantially different repaired versions.
>
> Do not change the accepted draft.
>
> Let me compare both versions, hear the affected dialogue, and show me exactly what each version changed.

That is the kind of problem Fount is built around.

It is not just asking a model to rewrite Scene 31.

The useful work is understanding what the decision touches, producing alternative solutions, keeping those solutions separate, and letting the writer decide what survives.

---

## Investigate the Script Before You Operate on It

Sometimes you know exactly what you want changed.

Sometimes you only know that something is wrong.

Fount Intelligence exists for the second case. Its screenplay-specific investigations are read-only: they can inspect the draft without quietly rewriting it.

A writer can ask questions such as:

| Writer's question                                 | What Fount can investigate                                                      |
| ------------------------------------------------- | ------------------------------------------------------------------------------- |
| When does the audience actually figure this out?  | The point where the available evidence becomes sufficient                       |
| Does Mara know this yet?                          | What that character has actually had access to before this moment               |
| Why does this reaction feel impossible?           | Whether the behavior assumes knowledge the character has not acquired           |
| Can I cut Scene 42?                               | What setups, payoffs, introductions, props, facts, or later events depend on it |
| Is this reveal properly set up?                   | Earlier support and the chain leading to the payoff                             |
| Did I break continuity with this rewrite?         | Character, story, temporal, spatial, and object continuity                      |
| Why is this scene flat?                           | Objectives, obstacles, tactics, beats, action, and dramatic movement            |
| Do these characters sound too similar?            | Dialogue patterns, vocabulary, cadence, and character voice                     |
| Is this passage all exposition?                   | Dialogue and scene material through specific dramatic lenses                    |
| What actually changed between these drafts?       | Source and screenplay-level differences between revisions                       |
| What happens if this whole story beat disappears? | A counterfactual inspection of the screenplay without that material             |

The goal is not to produce an all-knowing AI opinion about your screenplay.

The goal is to let a creative judgment be traced back to the actual pages that caused it.

Phase 5 adds writer-facing diagnostic playbooks for the cases where the writer knows the symptom but not the cause: Scene Doctor, Dialogue Pass, Character Trajectory, Relationship Pass, Suspense Audit, Sequence Momentum, Setup / Payoff, Notes Diagnosis, Submission Read, and Revision Regression. They keep competing explanations, counterevidence, protected strengths, resource use, and missing evidence visible before Workshop is asked to generate replacement pages.

---

## Explore More Than One Answer

A screenplay problem rarely has one objectively correct solution.

Fount therefore separates **strategy** from **pages**.

A strategy can propose a dramatic route before committing to a rewrite. You can keep several approaches alive, materialize the ones worth seeing, reject obvious dead ends, or ask for actual pages from multiple directions.

Those candidates remain separate from the accepted screenplay.

You can then:

**audition → compare → select → manually edit → combine → review → accept**

You are not required to accept an entire AI-generated version wholesale.

If one version contains the right ending and another contains the right confrontation, Fount can preserve the passages you choose and construct a new candidate around them.

---

## Big Rewrites Should Understand Their Blast Radius

Changing a screenplay is rarely local.

Move a revelation and earlier dialogue may become too informed.

Remove a scene and a later prop may appear from nowhere.

Change a character's decision and somebody else's response may no longer make sense.

Rewrite a sequence and the next scene may begin from emotional or physical circumstances that no longer exist.

Fount tracks screenplay structure and revision history so larger creative operations can inspect those consequences instead of treating every requested rewrite as an isolated chunk of prose.

This is particularly important for:

### Story-decision changes

Change a fact, reveal, decision, relationship, discovery, or event and inspect the material that depended on the previous version.

### Sequence rebuilding

Replace a run of scenes while preserving declared story requirements and the conditions on either side of the sequence.

### Character rewrites

Rework a character across a selected portion of the screenplay while considering dialogue, actions, tactics, decisions, appearances, and surrounding reactions.

### Note-driven revision

Turn a note into the edits it actually requires instead of assuming every note maps cleanly to one sentence or one scene.

---

## Recover Instead of Recreate

Revision history should be creatively useful.

If an earlier version contained a better joke, beat, entrance, scene, image, exchange, or piece of behavior, Fount can retain the history needed to recover it.

But old writing does not always fit the current draft anymore.

Recovery can therefore mean either:

**restore this material**

or:

**take what worked about this material and adapt it to the screenplay I have now**

That distinction matters after the plot, relationships, chronology, or character knowledge has changed.

---

## Hear the Pages

Dialogue that looks acceptable on the page can fail immediately when heard.

Fount Workshop can extract ordered dialogue turns for a scene, retain the associated character identity and parentheticals, route characters to voices, and hand those turns to a speech engine.

Table reads can be generated for accepted material or candidate revisions, making them useful when auditioning alternate versions before choosing one.

---

## Review the Actual Pages

Fount's revision workflow is built around reviewable candidates rather than invisible mutation.

A review packet can contain the base screenplay material, candidate Fountain pages, structural changes, source differences, analysis reports, lineage, table-read material, decision information, and—when requested and successfully rendered—candidate PDFs.

A renderer failure is a failure. It is not reported as a successful PDF that does not exist.

Acceptance is a separate operation performed only after the candidate and its checks have been reviewed.

---

## Screenplay Files Are Inputs and Outputs, Not the Story Model

Fount works with screenplay formats while keeping the screenplay itself independent of one particular file syntax.

### Fountain

Fount can preserve imported Fountain source exactly when it has not been changed, including formatting details that a simplistic parser would normally destroy.

Fountain remains a practical authoring and interchange format rather than being treated as the entire internal meaning of the screenplay.

### Final Draft / FDX

Fount includes practical FDX interchange for screenplay material such as scene headings, scene numbers, action, character cues, dialogue, parentheticals, dual dialogue, transitions, and representable styling.

When information cannot be represented faithfully, the adapter is expected to report that loss rather than silently pretend conversion was perfect.

### PDF

Fount Workshop can render screenplay PDFs using its configured screenplay renderer and inspect the resulting files for mechanical properties such as page geometry, fonts, and blank pages.

### JSON

Structured projections are available for integrations, indexing, inspection, and other tooling.

---

## Writer Control Is the Default

The core rule is simple:

**AI-generated writing is proposed writing, not accepted writing.**

Fount keeps revision identity, candidate lineage, source evidence, analysis reports, checks, and explicit writer review attached to the work so that a generated candidate cannot quietly masquerade as the screenplay you approved.

The accepted draft advances only through an explicit acceptance operation.

That separation is what makes aggressive experimentation practical.

---

## What Fount Is Today

Fount is currently a **headless screenplay engine and creative-workflow stack**, not a finished desktop screenwriting application.

There is no polished Final Draft-style GUI in this repository today.

The repository contains the screenplay model, revision system, investigations, generation workflows, candidate management, review machinery, persistence, command-line entry points, PDF handoff, table-read support, and supporting APIs needed to build that experience.

The intended user is a writer.

The current delivery surface is primarily for developers, agents, integrations, and future writer-facing applications built on top of those capabilities.

---

## Final Four-Package Product

The implementation is intentionally one four-package product rather than a compatibility stack: `fount` owns the canonical screenplay and typed edits; `fount_observe` owns neutral measurements and the System One adapter boundary; `fount_intelligence` owns evidence-grounded interpretation, reader/story-world reasoning, diagnosis and playbooks; `fount_workshop` owns generation, revision experiments, review, acceptance, sharing and performance conveniences through Inference/ASM.

Phase 16 adds a repository-owned final acceptance harness without creating another creative or canonical path. `bash scripts/final_acceptance.sh --static` checks source/package/traceability invariants; the runtime-QC environment uses `--runtime` for Mix CI and package builds, then records PostgreSQL, live-provider and optional human evidence separately. See [`packages/fount_workshop/guides/final-acceptance.md`](packages/fount_workshop/guides/final-acceptance.md).

---

## Repository Structure

| Package | Responsibility |
|---|---|
| [`fount`](packages/fount/README.md) | Canonical screenplay, Fountain/FDX/JSON interchange, typed edits, identity, exact selection/evidence, search and PostgreSQL persistence. |
| [`fount_observe`](packages/fount_observe/README.md) | Atomic source-grounded measurements, native SDK boundary, deterministic Sandbox, explicit resource limits and L1 result reuse. |
| [`fount_intelligence`](packages/fount_intelligence/README.md) | Read-only screenplay investigations plus pure StoryWorld/Temporal/Reader/Diagnosis reasoning, multi-pass writer playbooks, source-grounded evidence, uncertainty, dependencies, dialogue/voice analysis and comparison. |
| [`fount_workshop`](packages/fount_workshop/README.md) | Actual generated/revised pages, candidates, review/acceptance, recovery, rehearsal and exports. |

## How the Pieces Fit Together

The writer supplies an intention or concern. Intelligence can investigate it, acquiring exact measurements through Observe and retaining source evidence and uncertainty. Workshop can then generate alternatives against explicit screenplay targets. Fount stores and compares immutable revisions; only explicit review/acceptance advances canon.

Observe alone talks to SystemOneSDK. Workshop alone owns Inference completion, PDF and speech integration. Pure Intelligence logic takes values and returns values. There is one implementation path, not a compatibility bridge to a retired analysis package.

---

## Under the Hood

For applications building on Fount, the system keeps several kinds of information deliberately separate.

**Source** preserves what was actually imported.

**Screenplay structure** represents scenes, elements, dialogue, characters, authored material, and durable identities.

**Analysis** contains derived interpretations, evidence, model output, and other observations that should not be mistaken for authored screenplay truth.

**Candidates and presentation** contain possible revisions, comparisons, reports, Fountain exports, table reads, and PDFs.

That separation allows the system to reason about a screenplay without turning every inference into a fact and to generate possible writing without turning every generation into a revision.

---

## Development and Tests

The root Mix project uses Blitz to operate the four package projects:

```text
packages/fount
packages/fount_observe
packages/fount_intelligence
packages/fount_workshop
```

Each package retains its own dependencies, build output, and lockfile.

Install a compatible Elixir/OTP toolchain, Node.js/npm, PostgreSQL, and Poppler utilities (`pdfinfo`, `pdffonts`, and `pdftotext`; usually `poppler-utils` on Debian/Ubuntu).

From the repository root:

```bash
mix setup
```

This fetches the Mix dependencies for the workspace and runs `npm ci` for the workshop's pinned screenplay renderer.

PostgreSQL must already be running for integration tests that use persistence.

The existing test configuration defaults to:

```text
host/socket: /var/run/postgresql
port:        5433
user:        home
```

Override those values with:

```text
FOUNT_TEST_PGHOST
FOUNT_TEST_PORT
FOUNT_TEST_USER
FOUNT_TEST_PASSWORD
FOUNT_TEST_DATABASE
FOUNT_WORKSHOP_TEST_DATABASE
```

Create the test databases when needed:

```bash
createdb -h "${FOUNT_TEST_PGHOST:-/var/run/postgresql}" \
  -p "${FOUNT_TEST_PORT:-5433}" -U "${FOUNT_TEST_USER:-home}" \
  "${FOUNT_TEST_DATABASE:-fount_test}"

createdb -h "${FOUNT_TEST_PGHOST:-/var/run/postgresql}" \
  -p "${FOUNT_TEST_PORT:-5433}" -U "${FOUNT_TEST_USER:-home}" \
  "${FOUNT_WORKSHOP_TEST_DATABASE:-fount_workshop_test}"
```

For password authentication, provide the password through your normal PostgreSQL client configuration or `PGPASSWORD`.

Workspace commands:

```bash
mix test
mix test --seed 0
mix test -j 1

mix ci

mix blitz.workspace format
mix blitz.workspace compile
mix blitz.workspace credo --strict
mix blitz.workspace dialyzer
mix blitz.workspace docs
```

Run an individual package directly when needed:

```bash
(cd packages/fount && mix test)
(cd packages/fount_observe && mix test)
(cd packages/fount_intelligence && mix test)
(cd packages/fount_workshop && mix test)
```

Specific test files and line numbers should likewise be run from the owning package.

### Local cross-repository dependencies

The workspace supports the standard Mix Workspace Ops bootstrap hook through `MIX_WORKSPACE_OPS_BOOTSTRAP` and `workspace_dep/1`.

When no workspace override is active, those dependencies remain their ordinary committed dependencies. Workspace registry and source-selection state remain outside this repository.

---

## Executable Examples

From the repository root after setup:

```bash
(cd packages/fount && mix run examples/live.exs --mode roundtrip)
(cd packages/fount_observe && mix run examples/sandbox.exs)
(cd packages/fount_intelligence && mix run examples/inspect.exs)
```

These respectively exercise interchange, deterministic measurement and provider-free inventory. A complete writing/persistence demonstration is:

```bash
(cd packages/fount_workshop && mix run examples/phase_one.exs \
  --out examples/_output/phase_one --decision reject)
```

It requires a configured PostgreSQL database and migrations, but no live model. Add `--pdf` after installing the Workshop renderer/Poppler. Use `--decision accept` to exercise explicit fixture acceptance. The output distinguishes synthetic completions/measurements from actual database/export operations.

Existing live Workshop workflows remain in `packages/fount_workshop/examples/live.exs`; live inspection examples moved to `examples/analysis.exs` in that same package. Their credentials, database and export prerequisites remain explicit. See each package's example guide.

## Current Development Status

**Phases 1–10 are complete on recorded engineering QC. Phase 11 is offline-implemented in this delivery and awaits runtime QC.** Phase 10 is the durable-analysis baseline. Phase 11 adds rights-aware evaluation corpora, disagreement-preserving semantic annotations, calibration/abstention metrics, descriptive drift, frozen current-output-contract reasoning fixtures, all-twelve-family benchmark coverage, non-linear regression assets, longitudinal resource calibration, and explicit Observe/Workshop live-QC entry points.

The authoritative runtime evidence through Phase 10 is in the current docset. Phase-11 Elixir/DB/package/live checks are intentionally unclaimed here and are delegated to its Codex QC handoff. System One remains behind Observe, creative completion remains Workshop/Inference/ASM-owned, human studies remain optional under D046, and Phase 12 is not included.

---

## License

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom

## Source handoff snapshots

For the progressive screenplay-writing implementation workflow, generate a parsable XML snapshot with `repomix`, then use `python3 scripts/seal_handoff_snapshot.py --root . --input /absolute/path/fount.raw.xml --output /absolute/path/fount.xml`. The helper verifies included source against disk, preserves exact bytes, and embeds file hashes and Git identity for safe offline overlay construction. Run `python3 -m unittest discover -s scripts/tests -v` to verify the helper.

Use five fresh inputs on each pass: `fount.xml`, `system_one_sdk.xml`, `inference.xml`, `agent_session_manager.xml`, and the complete updated `docset.xml`. The source-writing environment returns ZIPs; the user applies and commits them; Codex verifies and repairs the applied phase before the next snapshots. The complete current docset supplied for the phase defines product scope and progress. Historical implementation notes above are not a replacement for that current specification.