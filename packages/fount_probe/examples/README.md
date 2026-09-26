# Fount Probe Examples

This directory contains executable scripts demonstrating Fount Probe's deterministic screenplay inspection, character knowledge tracing, voice attribution, and consequence modeling.

---

## Overview

The primary example runner is [`live.exs`](file:///home/home/p/g/n/fount/packages/fount_probe/examples/live.exs), which evaluates the canonical test screenplay fixture `last_light.fountain`. It demonstrates how the closed 16-tool catalog and TypeSafe's Jev model evaluate dramaturgical structure without generative hallucinations:

1. **Live Knowledge Tracing (`knowledge`)**: Connects to the TypeSafe AI endpoint via `system_one_sdk` and evaluates whether characters (Mara vs. Dan) and the audience know a key story revelation at an exact scene boundary (`EXT. BOAT RAMP - NIGHT`).
2. **Catalog Tool Orchestration (`tools`)**: Executes a batch of diagnostic probes (`inventory`, semantic `search`, and `scene_mechanics`) validating scene goals, obstacles, and discoveries.
3. **Voice Fingerprinting (`voice`)**: Runs blind classification against dialogue turns to determine whether character voices are distinctive or interchangeable.
4. **Knowledge Access & Reveal Boundaries (`knowledge_access`)**: Traces audience, reader, and character knowledge over time, tracking suspicion scores and pinpointing the exact scene element where a secret is revealed.
5. **Causal Consequences & Continuity (`consequences`)**: Analyzes narrative dependencies (such as a key transfer element) to see what breaks downstream if a scene is cut, paired with prop/wardrobe continuity checks.

---

## Running the Examples

### Prerequisites

- **TypeSafe System One API Key**:
  ```bash
  export SYSTEM_ONE_API_KEY="your-typesafe-api-key"
  ```
- **PostgreSQL Database** (for multi-tool modes `tools`, `voice`, `knowledge_access`, `consequences`):
  ```bash
  export FOUNT_DATABASE_URL="ecto://postgres:postgres@localhost:5432/fount_dev"
  export FOUNT_CODEX_MODEL="gpt-4o" # or your chosen model if using inference alongside Jev
  ```

---

### Executing Live Modes

Run scripts using `mix run`:

#### 1. Live Jev Knowledge Tracing (Requires only `SYSTEM_ONE_API_KEY`)
Traces audience vs. character knowledge states directly against live Jev:

```bash
mix run examples/live.exs --mode knowledge --out examples/_output/knowledge
```

**Artifacts generated in `examples/_output/knowledge/`:**
- `knowledge.json` — Evaluated perspectives (`audience`, `MARA`, `DAN`), probability values ($p \in [0, 1]$), model provenance, and prepared question fingerprint.

#### 2. Full Closed Tool Catalog Suite
Runs structural inventory, semantic concept search, and 7-dimension scene mechanics:

```bash
mix run examples/live.exs --mode tools --out examples/_output/tools
```

#### 3. Character Voice Attribution
Evaluates dialogue distinction between lead characters:

```bash
mix run examples/live.exs --mode voice --out examples/_output/voice
```

#### 4. Reveal Boundary & Suspicion Tracing
Identifies when reader/character belief shifts and flags the exact line of dialogue:

```bash
mix run examples/live.exs --mode knowledge_access --out examples/_output/knowledge_access
```

#### 5. Causal Dependencies & Continuity
Maps narrative prerequisites and prop/wardrobe state transitions across scenes:

```bash
mix run examples/live.exs --mode consequences --out examples/_output/consequences
```

---

## Custom Output Directory

Set the output location with `--out` or the `FOUNT_EXAMPLE_OUT` environment variable:

```bash
FOUNT_EXAMPLE_OUT="/tmp/probe_demo" mix run examples/live.exs --mode knowledge
```
