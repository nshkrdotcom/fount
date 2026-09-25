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

Fount Probe provides deep, verifiable, and deterministic dramaturgical inspection for screenplays. Designed for writers, analytical pipelines, and autonomous AI agents, Fount Probe enforces strict boundaries between observation and mutation: all probes are read-only, and every diagnostic finding retains complete provenance anchored to source byte spans, scene UUIDs, element IDs, and revision hashes.

---

## Architectural Guarantees

```text
┌────────────────────────────────────────────────────────┐
│                    SCREENPLAY MODEL                    │
│   (Canonical Elements, Scenes, CST, Revision UUID)     │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│                   FOUNT PROBE ENGINE                   │
│                                                        │
│  ┌─────────────────┐ ┌─────────────────┐ ┌──────────┐  │
│  │     Catalog     │ │   Projection    │ │  Report  │  │
│  │ (16 Closed Tools)│ │(Unit Selection) │ │ (Evidence│ │
│  └─────────────────┘ └─────────────────┘ └──────────┘  │
│  ┌─────────────────┐ ┌─────────────────┐ ┌──────────┐  │
│  │ Knowledge Trace │ │   Continuity    │ │  Voice   │  │
│  └─────────────────┘ └─────────────────┘ └──────────┘  │
│  ┌─────────────────┐ ┌─────────────────┐ ┌──────────┐  │
│  │ Scene Mechanics │ │   Comparison    │ │  Ablate  │  │
│  └─────────────────┘ └─────────────────┘ └──────────┘  │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼
┌────────────────────────────────────────────────────────┐
│              EVIDENCE & PROVENANCE REPORT              │
│  Observations, Confidence, Grounded Element/Scene IDs  │
└────────────────────────────────────────────────────────┘
```

1. **Strict Read-Only Execution (`writes_screenplay: false`)**:
   No tool in the catalog can mutate screenplay text, alter element structures, or advance revision hashes. Investigations are purely observational and idempotent.
2. **Exact Source Identity & Provenance**:
   Observations are never abstract or ungrounded. Every finding links to precise canonical entity IDs (`scene_id`, `element_id`) and concrete byte ranges in the Concrete Syntax Tree (`start_byte`, `end_byte`).
3. **Closed Tool Catalog**:
   Probing operates strictly within a vetted, 16-tool closed schema defined in `FountProbe.Catalog`. Arbitrary code execution, shell commands, or unconstrained dynamic dispatch are architecturally prohibited.
4. **Structured Investigation Lifecycle**:
   Investigations move from diagnostic questions to validated findings through a three-phase protocol: `plan/4` (probe selection) → `execute/4` or `run/5` (grounded observation) → `explain/5` (evidence-backed synthesis).
5. **Comparative & Counterfactual Analysis**:
   Verify proposed screenplay revisions against dramaturgical constraints (`compare`), quantify ripple effects of removing sequences (`scene_lift`), or evaluate counterfactual changes in character knowledge (`ablate`).

---

## The Closed Tool Catalog

`FountProbe.Catalog` defines 16 specialized inspection tools:

| Tool | Required Parameters | Optional Parameters | Purpose |
| :--- | :--- | :--- | :--- |
| **`inventory`** | `selection` | `include_summaries` | Hierarchical summary of scenes, characters, headings, and counts. |
| **`extract_story`** | `selection`, `kinds` | `question`, `adjacent_scenes` | Extracts beats, events, dialogue turns, or scene summaries. |
| **`search`** | `query` | `selection`, `filters`, `revision_ids`, `mode`, `limit`, `exact_phrase` | Lexical, semantic, and exact-phrase retrieval across screenplay spans. |
| **`check_constraints`** | `constraints` | `selection` | Validates dramaturgical pacing rules, cast parameters, and narrative limits. |
| **`knowledge_trace`** | `proposition`, `subjects`, `points` | `access_mode`, `suspicion`, `behavior_element_ids`, `intended_reveal_point` | Verifies whether characters know or suspect specific propositions. |
| **`locate_boundary`** | `scene_id`, `proposition`, `projection` | `character_id`, `threshold`, `include_prior_context` | Pinpoints the exact scene or element boundary where knowledge shifts. |
| **`dependencies`** | `targets`, `selection` | `record_report_ids`, `include_alternative_support`, `inspect_setup_purpose` | Analyzes narrative setups, payoffs, props, and causal prerequisites. |
| **`continuity`** | `selection` | `subjects`, `changed_targets`, `record_report_ids` | Verifies temporal, character, wardrobe, prop, and spatial consistency. |
| **`scene_mechanics`** | `selection` | `character_id`, `objective`, `concern`, `include_tactics` | Evaluates dramatic objectives, obstacles, tactics, and beats in scenes. |
| **`dialogue`** | `selection`, `lenses` | `character_ids` | Deep dialogue analysis across subtext, cadence, and exposition lenses. |
| **`voice`** | `character_ids`, `selection` | `training_targets`, `profiles`, `comparison_groups` | Character dialogue fingerprinting and vocabulary distinctiveness. |
| **`action`** | `selection` | `direction`, `layout_report_id` | Assesses visual pacing, line density, readability, and blocking clarity. |
| **`compare`** | `before_revision_id`, `after_revision_id`, `constraints` | `profile_id` | Forensic delta analysis between two screenplay revisions. |
| **`scene_lift`** | `scene_ids`, `constraints` | `consequence_scope` | Assesses dramatic and causal consequences of cutting or moving scenes. |
| **`ablate`** | `groups`, `proposition`, `point`, `projection` | `character_id` | Counterfactual ablation removing specific scenes, facts, or beats. |
| **`strategy_contrast`** | `brief`, `strategies` | — | Evaluates multiple proposed creative rewrite strategies against criteria. |

---

## Quickstart

### 1. Installation

Add `fount_probe` and its peer packages to your `mix.exs`:

```elixir
def deps do
  [
    {:fount, "~> 0.1.0"},
    {:fount_probe, "~> 0.1.0"}
  ]
end
```

### 2. Inspecting Screenplay Inventory

Inspect a screenplay model to obtain structural counts, scenes, and character rosters:

```elixir
{:ok, model} = Fount.parse(fountain_text) |> Fount.Screenplay.from_document()

{:ok, report} = FountProbe.run(model, "inventory", %{
  "selection" => %{"type" => "all"},
  "include_summaries" => true
})

report.tool # => "inventory"
report.data["inventory"]["scenes"] # => List of scenes with heading metadata
```

### 3. Tracing Character Knowledge

Verify whether a character knows a critical plot revelation at a specific scene:

```elixir
{:ok, trace} = FountProbe.run(model, "knowledge_trace", %{
  "proposition" => "Marcus is collaborating with the syndicate",
  "subjects" => [marcus_character_id, elena_character_id],
  "points" => [interrogation_scene_id],
  "access_mode" => "direct"
}, clients)

trace.data["assessments"]
# => %{"ELENA" => %{status: :unaware, confidence: 0.94, evidence_ids: [...]}}
```

### 4. Forensic Revision Comparison

Compare two screenplay revisions against character voice and pacing constraints:

```elixir
constraints = [
  %{"type" => "character_voice", "character_id" => elena_id, "max_drift" => 0.10},
  %{"type" => "scene_count", "expected" => 42}
]

{:ok, comparison} = FountProbe.compare(base_model, revised_model, constraints, clients)

comparison.data["constraint_results"]
# => [%{"constraint" => "character_voice", "status" => :passed, "delta" => 0.04}]
```

### 5. Multi-Probe Investigation Lifecycle

Orchestrate complex dramaturgical inquiries:

```elixir
concern = %{
  "question" => "Why does the third act confrontation feel unearned?",
  "subjects" => ["ELENA", "MARCUS"],
  "scope" => %{"type" => "act", "number" => 3}
}

# 1. Plan probes to run
{:ok, plan} = FountProbe.plan(model, concern, clients)

# 2. Execute gathered probes
{:ok, reports} = FountProbe.execute(model, plan.requests, clients)

# 3. Synthesize an evidence-backed explanation
{:ok, finding} = FountProbe.explain(model, concern, reports, clients)

finding.summary
# => "Elena confronts Marcus regarding the stolen ledger, but no preceding scene shows Elena discovering the ledger's existence."
finding.citations # => [%{tool: "dependencies", evidence_id: "elem-842"}]
```

---

## Command Line Interface

Fount Probe includes Mix tasks for direct terminal inspection:

```bash
# Run a probe query
mix fount.probe --tool inventory --selection all

# Search screenplay elements with semantic filtering
mix fount.search "vault key" --mode semantic --limit 10
```

---

## Documentation Guides

- [Architecture & Provenance](guides/architecture.md)
- [Tools & Catalog Reference](guides/tools-and-catalog.md)
- [Investigations & Evidence](guides/investigations-and-evidence.md)
- [Comparison & Counterfactual Ablation](guides/comparison-and-ablation.md)

---

## License

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom
