<p align="center">
  <img src="assets/fount_probe.svg" alt="Fount Probe" width="200" height="200"/>
</p>

<p align="center">
  <a href="https://hex.pm/packages/fount_probe"><img src="https://img.shields.io/hexpm/v/fount_probe.svg" alt="Hex.pm"/></a>
  <a href="https://hexdocs.pm/fount_probe"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="HexDocs"/></a>
  <a href="https://github.com/nshkrdotcom/fount"><img src="https://img.shields.io/badge/GitHub-repo-black?logo=github" alt="GitHub"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"/></a>
</p>

# Fount Probe

**Screenplay-specific inspection, comparison, and investigation engine for the Fount framework.**

Writers often struggle with questions that are difficult to track across a 110-page draft:
* *Does Elena actually know Marcus forged the ledger in Scene 14, or is she acting on information she hasn't learned yet?*
* *If I cut this minor setup scene in Act 1, what downstream payoffs or prop introductions collapse in Act 3?*
* *Does Marcus's dialogue sound distinct from Dan's, or are they speaking with the same voice?*
* *Is this scene advancing the story with active decisions and consequences, or is it pure exposition?*

Asking a general-purpose conversational LLM to answer these questions often produces hallucinations, polite flatteries, or vague summaries. 

**Fount Probe provides deterministic, verifiable dramaturgical diagnostics.** It evaluates screenplays through a closed catalog of 16 forensic inspection tools powered by [TypeSafe AI](https://docs.typesafe.ai)'s **Jev** model. Fount Probe is strictly read-only: it observes and reports, grounding every finding to exact scene UUIDs, element IDs, and byte spans in the screenplay's Concrete Syntax Tree.

---

## Architectural Guarantees

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                          CANONICAL SCREENPLAY                           │
│            (Scenes, Elements, CST Byte Spans, Revision Hash)            │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           FOUNT PROBE ENGINE                            │
│                                                                         │
│  ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐  │
│  │  Closed Catalog   │   │    Projection     │   │ Budget Controller │  │
│  │ (16 Finite Tools) │   │ (Unit Selection)  │   │  (:atomics Quota) │  │
│  └───────────────────┘   └───────────────────┘   └───────────────────┘  │
│  ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐  │
│  │  Knowledge Trace  │   │    Continuity     │   │  Scene Mechanics  │  │
│  │  (Audience/Cast)  │   │  (State & Props)  │   │ (7 Turn Dynamics) │  │
│  └───────────────────┘   └───────────────────┘   └───────────────────┘  │
│  ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐  │
│  │   Dependencies    │   │  Dialogue & Voice │   │ Revision Compare  │  │
│  │  (Causal Ripple)  │   │ (Subtext/Attrib)  │   │ (Forensic Diffs)  │  │
│  └───────────────────┘   └───────────────────┘   └───────────────────┘  │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       STRUCTURED EVIDENCE REPORT                        │
│   Grounded Findings, Probabilities, Element IDs, CST Byte Provenance    │
└─────────────────────────────────────────────────────────────────────────┘
```

1. **Strict Read-Only Execution (`writes_screenplay: false`):** Fount Probe cannot mutate screenplay text, alter element structures, or advance revision hashes. Probes are purely observational and idempotent.
2. **Exact Source Identity & Byte Provenance:** Observations are never abstract. Findings cite concrete entity IDs (`scene_id`, `element_id`) and byte spans (`start_byte`, `end_byte`) in the original script.
3. **Closed Tool Catalog:** Operations run through 16 statically validated probe schemas defined in `FountProbe.Catalog`. Dynamic code execution, shell commands, or arbitrary prompts are architecturally impossible.
4. **Structured Three-Phase Investigation Protocol:**
   - **`plan/4`:** Identify which specific probes are required to investigate a writer's question.
   - **`execute/4`:** Dispatch targeted probe batches against the canonical screenplay model.
   - **`explain/5`:** Synthesize evidence-backed dramaturgical findings citing only the collected probe reports.
5. **No Hallucinations via System One (Jev):** Rather than generating unpredictable conversational text, high-volume classification passes route through TypeSafe's Jev model via `system_one_sdk`, returning typed, mathematically constrained probability distributions (`Noul`, `Choice`, `Score`).

---

## The Closed Tool Catalog

Fount Probe organizes screenplay inspection into 16 specialized diagnostic tools:

| Category | Tool | What It Does for the Writer |
| :--- | :--- | :--- |
| **Structure & Retrieval** | **`inventory`** | Hierarchical summary of scenes, headings, characters, page counts, and optional beat summaries. |
| | **`extract_story`** | Extracts character intentions, narrative events, dialogue turns, or scene goals. |
| | **`search`** | Lexical and semantic retrieval across elements, distinguishing conceptual matches from keyword coincidences. |
| **Knowledge & Irony** | **`knowledge_trace`** | Tracks what the audience vs. individual characters know, believe, or suspect across scenes. |
| | **`locate_boundary`** | Pinpoints the exact scene and element where a secret, confession, or plot revelation occurs. |
| | **`access`** | Audits whether an information channel actually existed for a character to learn a secret (e.g. overheard vs. witnessed). |
| **Continuity & Causality** | **`continuity`** | Verifies chronological consistency for characters, props, wardrobe, and locations across scene cuts. |
| | **`dependencies`** | Analyzes setups and payoffs, identifying prerequisite objects, rules, or motivations between scenes. |
| | **`scene_lift`** | Quantifies the narrative collateral damage if a scene is cut or moved. |
| | **`ablate`** | Counterfactual test: verifies what character knowledge or insights collapse if a prior scene is erased. |
| **Dramaturgy & Craft** | **`scene_mechanics`** | Evaluates 7 core dramatic dimensions: problems, decisions, plans, relationships, consequences, objectives, and disclosures. |
| | **`dialogue`** | Deep dialogue analysis across 5 lenses: subtext, responsiveness, exposition, repetition, and tactics. |
| | **`voice`** | Blind attribution test: classifies unlabelled dialogue lines against character profiles to test voice distinction. |
| | **`action`** | Evaluates action prose for visible behavior vs. unfilmable interior monologue and spatial clarity. |
| **Revision Delta** | **`check_constraints`** | Asserts dramaturgical rules (pacing limits, cast caps, fact invention) against a draft. |
| | **`compare`** | Forensic delta analysis between two revisions to verify that edits satisfied constraints without introducing regressions. |
| | **`strategy_contrast`** | Evaluates whether competing rewrite pitches represent materially distinct causal strategies. |

---

## Declarative Question Profiles (`priv/profiles/*.json`)

Fount Probe separates evaluation logic into **domain projections** (in Elixir) and **versioned question profiles** (in JSON assets located in [`priv/profiles/`](file:///home/home/p/g/n/fount/packages/fount_probe/priv/profiles/)).

Profiles define question instructions and mathematical calibration thresholds:
- `support_probability`: Minimum threshold for an affirmative finding (e.g., $\ge 0.80$).
- `minimum_confidence`: Minimum confidence margin required to avoid an `"uncertain"` verdict.
- `sha256`: Cryptographic fingerprint guaranteeing that historical benchmark runs remain 100% reproducible.

Writers and studios can tune evaluation strictness or test custom profile IDs dynamically without recompiling code.

---

## Quickstart

### 1. Structural Inventory

Inspect screenplay metrics, scene structures, and character rosters:

```elixir
{:ok, model} = Fount.parse(fountain_text) |> Fount.Screenplay.from_document()

{:ok, report} = FountProbe.run(model, "inventory", %{
  "selection" => %{"type" => "all"},
  "include_summaries" => true
})

report.tool # => "inventory"
report.data["inventory"]["scenes"] # => List of scenes with heading metadata
```

### 2. Tracing Dramatic Irony & Character Knowledge

Verify whether a character knows a critical plot revelation before an interrogation scene:

```elixir
{:ok, clients} = FountProbe.Launcher.clients()

{:ok, trace} = FountProbe.run(model, "knowledge_trace", %{
  "proposition" => "Marcus forged the marina financial ledger",
  "subjects" => [
    %{"kind" => "audience"},
    %{"kind" => "character", "character_id" => elena_id}
  ],
  "points" => [interrogation_scene_id],
  "access_mode" => "evidence",
  "suspicion" => true
}, clients)

trace.data["assessments"]["ELENA"]
# => %{"status" => "unaware", "probability" => 0.08, "evidence_ids" => [...]}
```

### 3. Dialogue Multi-Lens Analysis

Evaluate whether dialogue in a scene is responsive, carries subtext, or suffers from expository bloat:

```elixir
{:ok, report} = FountProbe.run(model, "dialogue", %{
  "selection" => %{"targets" => [%{"kind" => "scene", "id" => scene_id}]},
  "lenses" => ["subtext", "exposition", "responsive", "tactic"]
}, clients)

# Inspect dialogue turns flagged for on-the-nose exposition:
report.data["turns"]
|> Enum.filter(&(&1["lenses"]["exposition"]["status"] == "complete"))
```

### 4. Counterfactual Scene Lift Analysis

Evaluate what breaks downstream before cutting a scene:

```elixir
{:ok, lift_report} = FountProbe.run(model, "scene_lift", %{
  "scene_ids" => [setup_scene_id],
  "constraints" => ["preserve_climax_payoff", "track_keycard_possession"]
}, clients)

lift_report.data["broken_dependencies"]
# => [%{"target_scene_id" => "scene-42", "reason" => "keycard_possession_unmotivated"}]
```

### 5. Multi-Probe Investigation Protocol

Execute a structured three-phase inquiry into a complex story concern:

```elixir
concern = %{
  "question" => "Why does Elena's betrayal in the third act feel unmotivated?",
  "subjects" => ["ELENA"],
  "scope" => %{"type" => "act", "number" => 3}
}

# 1. Plan probes
{:ok, plan} = FountProbe.plan(model, concern, clients)

# 2. Execute gathered probes
{:ok, reports} = FountProbe.execute(model, plan.requests, clients)

# 3. Synthesize evidence-backed finding
{:ok, finding} = FountProbe.explain(model, concern, reports, clients)

finding.summary
# => "Elena acts on knowledge of Marcus's offshore accounts, but no preceding scene shows Elena discovering or receiving that information."
finding.citations # => [%{tool: "access", scene_id: "scene-28", element_id: "elem-412"}]
```

---

## Command Line Interface

Fount Probe includes Mix tasks for direct terminal inspection:

```bash
# Run a scene inventory:
mix fount.probe --tool inventory --selection all

# Semantic concept search across dialogue and action:
mix fount.search "a character conceals an object in a panic" --mode semantic --limit 5
```

---

## Executable Live Examples

Fount Probe includes live scripts exercising TypeSafe Jev evaluations, character voice attribution, and consequence modeling:

```bash
export SYSTEM_ONE_API_KEY="your-typesafe-api-key"

# Live Jev character knowledge tracing:
mix run examples/live.exs --mode knowledge --out examples/_output/knowledge

# Blind character voice attribution:
mix run examples/live.exs --mode voice --out examples/_output/voice

# Causal dependencies and prop continuity:
mix run examples/live.exs --mode consequences --out examples/_output/consequences
```

Consult the [**Probe Examples Guide**](examples/README.md) for full instructions and prerequisites.

---

## Comprehensive Guides

Explore detailed guides covering Fount Probe's subsystems:

* [**Architecture & Invariants**](guides/architecture.md) — Read-only execution, CST byte spans, and the three-phase investigation lifecycle.
* [**Closed Tool Catalog**](guides/tools-and-catalog.md) — Complete parameter specifications and schemas for all 16 tools.
* [**Investigations & Evidence**](guides/investigations-and-evidence.md) — Planning, executing, and synthesizing evidence-backed coverage findings.
* [**Comparison & Counterfactual Ablation**](guides/comparison-and-ablation.md) — Revision comparison, scene lifts, and knowledge ablation.
* [**Live Examples**](examples/README.md) — Executable diagnostic scripts and output schemas.

---

## The Fount Ecosystem

Fount Probe is the analytical middle tier of the Fount screenplay framework:

1. **[Fount](https://hexdocs.pm/fount)**: The headless screenplay engine, lossless CST parser, and relational revision store.
2. **[Fount Probe](https://hexdocs.pm/fount_probe)**: The dramaturgical auditor and diagnostic engine. 100% read-only inspection for character knowledge, continuity, scene mechanics, and voice attribution.
3. **[Fount Workshop](https://hexdocs.pm/fount_workshop)**: The writer's studio. Scoped AI revision loops with Myers diffs, beat recovery, competition submission checks, and PDF publishing.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
