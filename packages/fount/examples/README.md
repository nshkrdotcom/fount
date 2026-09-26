# Fount Examples

This directory contains executable scripts demonstrating Fount's core screenplay engine, lossless multi-format interchange, and relational revision persistence.

---

## Overview

The primary example runner is [`live.exs`](file:///home/home/p/g/n/fount/packages/fount/examples/live.exs), which operates against the canonical test screenplay fixture `last_light.fountain`. It showcases three foundational capabilities:

1. **Lossless Roundtrip (`roundtrip`)**: Parses Fountain text into an exact Concrete Syntax Tree (CST) and Screenplay IR, verifying that untouched files round-trip byte-for-byte while simultaneously exporting to Final Draft (FDX) and Canonical JSON.
2. **Interchange Fidelity Audit (`interchange`)**: Exercises the multi-format interchange matrix across Fountain, FDX, and JSON, asserting semantic identity and reporting any syntax-level translation diagnostics.
3. **Relational Persistence (`database`)**: Connects to PostgreSQL via `Fount.Repo`, saves a screenplay, executes atomic edit operations advancing revision hashes, and demonstrates historical revision retrieval (ensuring historical beats remain immutable).

---

## Running the Examples

All examples are executed using `mix run`:

### 1. Multi-Format Lossless Roundtrip
Exports the screenplay into Fountain, Final Draft (`.fdx`), Canonical JSON, and generates an export manifest:

```bash
mix run examples/live.exs --mode roundtrip --out examples/_output/roundtrip
```

**Artifacts generated in `examples/_output/roundtrip/`:**
- `last_light.fountain` — Pure Fountain export, matching source bytes exactly.
- `last_light.fdx` — Final Draft XML projection with paragraph types and dual-dialogue structure.
- `last_light.json` — Lossless canonical JSON serialization including element UUIDs and byte spans.
- `manifest.json` — Metadata summary with SHA-256 hashes, scene counts, cast counts, and revision UUID.

### 2. Interchange Fidelity Matrix
Tests bi-directional format conversion and produces an interchange fidelity report:

```bash
mix run examples/live.exs --mode interchange --out examples/_output/interchange
```

**Artifacts generated in `examples/_output/interchange/`:**
- `fidelity.json` — Matrix of supported features and format-specific degradation boundaries.
- Re-imported and validated copies of the screenplay in all three formats.

### 3. Relational Revision Persistence (Requires PostgreSQL)
Demonstrates saving a screenplay to PostgreSQL, applying an atomic edit that modifies an action line, saving the new revision, and reloading both the current head and the original immutable revision:

```bash
export FOUNT_DATABASE_URL="ecto://postgres:postgres@localhost:5432/fount_dev"
mix run examples/live.exs --mode database --out examples/_output/database
```

**Artifacts generated in `examples/_output/database/`:**
- `original.fountain` — Screenplay reconstructed from the historical parent revision.
- `accepted.fountain` — Screenplay reconstructed from the newly committed revision containing the edit.
- `fixture_bindings.json` — Revision hashes, element IDs, and transaction metadata.

---

## Custom Output Directory

You can customize where generated artifacts are placed by passing the `--out` CLI option or setting the `FOUNT_EXAMPLE_OUT` environment variable:

```bash
FOUNT_EXAMPLE_OUT="/tmp/fount_demo" mix run examples/live.exs --mode roundtrip
```
