# Fount Workshop Examples

This directory contains executable scripts demonstrating Fount Workshop's bounded scene revision loops, candidate generation, Myers text diffs, historical beat recovery, and PDF publication.

---

## Overview

The primary example runner is [`live.exs`](file:///home/home/p/g/n/fount/packages/fount_workshop/examples/live.exs), which operates against canonical screenplay models and PostgreSQL revision stores. It demonstrates how writers and AI agents collaborate without risking script corruption:

1. **Historical Beat Recovery (`recover`)**: Simulates cutting an action line, discovering it was needed, and using `FountWorkshop.Recover` to surgically restore the exact historical beat into the current draft without rolling back intermediate scenes.
2. **Competing Creative Alternatives (`alternatives`)**: Generates 3 distinct dramaturgical approaches for a scene, previewing full Myers diffs and structural changes in memory before the writer decides which (if any) to accept.
3. **Multi-Scene Sequence Routing (`sequence_routes`)**: Restructures an entire sequence across multiple scenes with rendered PDF side-by-sides.
4. **Targeted Character Rewrite (`character_workspace`)**: Performs dialogue punch-up specifically for one character while holding all other dialogue turns and action lines constant.
5. **Coverage Note Response (`grouped_notes`)**: Takes multiple writer/producer notes and executes a coordinated revision pass.
6. **Full Revision Pass with PDF Export (`pass_all`)**: Executes a comprehensive pass, formats diff review packets, and renders industry-standard PDFs inspected with Poppler.

---

## Running the Examples

### Prerequisites

1. **PostgreSQL Database**:
   ```bash
   export FOUNT_DATABASE_URL="ecto://postgres:postgres@localhost:5432/fount_dev"
   ```
2. **AI Provider Credentials** (for LLM generation and probe evaluation):
   ```bash
   export SYSTEM_ONE_API_KEY="your-typesafe-api-key"
   export FOUNT_CODEX_MODEL="gpt-4o"
   ```
3. **Poppler & Node.js Dependencies** (for PDF export and verification):
   - Ensure Poppler tools (`pdfinfo`, `pdffonts`, `pdftotext`) are installed.
   - Install Afterwriting dependencies:
     ```bash
     cd packages/fount_workshop && npm ci
     ```

---

### Executing Live Modes

Run scripts using `mix run`:

#### 1. Historical Beat Recovery (Zero AI calls required)
Demonstrates restoring a cut element directly from historical revision trees:

```bash
mix run examples/live.exs --mode recover --out examples/_output/recover
```

**Artifacts generated in `examples/_output/recover/`:**
- `<candidate_id>.fountain` — Reconstructed candidate screenplay with the restored beat.
- `<candidate_id>.pdf` — Formatted PDF with Courier Prime, margins, and page budget.
- `<candidate_id>.review.json` — Myers source diffs, element changes, and provenance.
- `manifest.json` — Revision hashes, head stability assertion, and execution summary.

#### 2. Creative Alternatives Pass
Generates distinct revision candidates for a scene and produces side-by-side review packets:

```bash
mix run examples/live.exs --mode alternatives --out examples/_output/alternatives
```

#### 3. Targeted Character Dialogue Punch-Up
Isolates a character's dialogue turns across selected scenes:

```bash
mix run examples/live.exs --mode character_workspace --out examples/_output/character_workspace
```

#### 4. Sequence Restructuring
Re-orders and rewrites a sequence across scene boundaries:

```bash
mix run examples/live.exs --mode sequence_routes --out examples/_output/sequence_routes
```

#### 5. Full Pass with Atomic Acceptance Demo
Add `--accept_demo` to demonstrate accepting a previewed candidate and advancing the canonical revision:

```bash
mix run examples/live.exs --mode recover --accept_demo --out examples/_output/accepted_demo
```

---

## Custom Output Directory

Set the output location with `--out` or the `FOUNT_EXAMPLE_OUT` environment variable:

```bash
FOUNT_EXAMPLE_OUT="/tmp/workshop_demo" mix run examples/live.exs --mode recover
```
