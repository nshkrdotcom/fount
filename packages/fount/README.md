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

**The headless screenplay engine and relational authoring platform for Elixir.**

Screenplays are not flat text files, and they are not word-processor documents. A screenplay is a rigorous, multi-layered dramatic blueprint containing scene hierarchies, dialogue cadence, character presence, temporal continuity, and physical action.

For decades, writers have been forced to choose between the proprietary, opaque file formats of traditional desktop software (Final Draft `.fdx`) and flat plain text (Fountain `.fountain`). Flat text lacks durable object identity, making automated analysis, revision branching, and character tracking fragile. Proprietary formats corrupt story structure by conflating page geometry with narrative truth.

**Fount solves this by treating screenplays as structured, queryable data.** Fountain and Final Draft serve as lossless import and export boundaries, while your screenplay exists as an immutable, typed model with durable element identities, revision branching, and relational persistence backed by PostgreSQL and Ecto.

---

## The Four Truths of Screenplay Architecture

Screenplay systems break down when formatting quirks interfere with dramatic structure. Fount separates narrative reality into four strict architectural tiers:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│  1. SOURCE TRUTH                                                        │
│  Exact imported bytes, Concrete Syntax Tree (CST), trivia, comments,     │
│  boneyards, and line-ending preservation. Untouched files round-trip.   │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ import / project
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  2. SCREENPLAY TRUTH                                                    │
│  Format-independent canonical model. Scenes, elements, dialogue blocks, │
│  and outline nodes anchored by durable UUIDs across revisions.          │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ analyses / resolution
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  3. INTERPRETIVE TRUTH                                                  │
│  Canonical cast rosters, character aliases, byte-anchored mentions,     │
│  and evidence-backed dramaturgical assertions tied to revisions.        │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ render / layout
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  4. PRESENTATION TRUTH                                                  │
│  Laid-out PDF pages, eighths measurements, timing calculations,         │
│  and rehearsal audio table reads. Formatting changes never mutate story.│
└─────────────────────────────────────────────────────────────────────────┘
```

1. **Source Truth:** Preserves every raw byte, indentation, writer comment, and boneyard tag. When you import and re-export an untouched Fountain file, it produces a byte-for-byte identical output.
2. **Screenplay Truth:** Canonical, semantic Intermediate Representation (IR). Every scene, action paragraph, character cue, parenthetical, and dialogue turn has a permanent UUID (`element_id`, `scene_id`).
3. **Interpretive Truth:** Resolves character presence vs. spoken references. Tracks whether `"DAN"` is a speaker cue, a direct address, or an off-screen reference, anchored to precise byte spans.
4. **Presentation Truth:** Purely downstream layout. Page counts, line budgets, and timing models derive from the screenplay truth—they never dictate it.

---

## Core Capabilities

- **Lossless Fountain Roundtripping:** High-performance scanner and parser generating an exact Concrete Syntax Tree (CST). Never drops writer comments (`/* notes */`), boneyards (`/* ... */`), or custom title page keys.
- **Multi-Format Interchange:** Native, bi-directional conversion between Fountain, Final Draft (`.fdx`), and lossless Canonical JSON.
- **Relational PostgreSQL Persistence:** Full Ecto integration. Store screenplays with complete revision trees, branch points, and immutable snapshots. Every previous draft is retrievable; no cut scene is ever lost.
- **Atomic Edit Algebra:** Functional transformations (`replace_text`, `insert_elements`, `delete_elements`, `reorder_scenes`) that validate structural constraints, advance cryptographic revision hashes, and produce Myers diffs.
- **Cast & Alias Disambiguation:** Distinguishes between physical character entities (`Sarah Connor`) and transient cues (`SARAH`, `VOICE ON RADIO`, `SARAH (O.S.)`), keeping dialogue attribution pristine.

---

## Quickstart

### 1. Lossless Fountain Parsing

Parse Fountain text into a structured document and verify byte-for-byte fidelity:

```elixir
source = """
Title: TERMINUS
Credit: written by
Author: Jane Doe

EXT. HIGH DESERT - DUSK

Wind whips through the rusted fence.

SARAH
(whispering)
Don't move.
"""

# Parse into exact CST and Screenplay IR
{:ok, doc} = Fount.parse(source)

# Untouched files round-trip byte-for-byte:
Fount.render(doc) == source # => true
```

### 2. Authoring a Canonical Screenplay

Construct screenplays programmatically using typed data structures:

```elixir
alias Fount.Screenplay

script = Screenplay.new(
  title: [title: "TERMINUS", credit: "written by", author: "Jane Doe"],
  scenes: [
    %{
      heading: "INT. BUNKER - NIGHT",
      elements: [
        %{type: :character, text: "SARAH"},
        %{type: :parenthetical, text: "(whispering)"},
        %{type: :dialogue, text: "The signal is gone."},
        %{type: :action, text: "A distant rumble shakes the dust from the pipes."}
      ]
    }
  ]
)

# Export directly to standard Fountain or Final Draft:
fountain_text = Screenplay.to_fountain(script)
{:ok, fdx} = Screenplay.to_fdx(script)
```

### 3. Immutable Edits & Revision Diffs

Apply atomic edits to scenes or dialogue. Every edit validates grammar, advances the revision hash, and captures structural diffs:

```elixir
dialogue_element = Enum.find(script.ir.elements, &(&1.type == :dialogue))

# Apply an atomic edit operation
{:ok, revised_script, changeset} = Screenplay.apply(
  script,
  Fount.Edit.replace_text(dialogue_element.id, "The signal is back. It's moving.")
)

# Inspect the semantic change:
changeset.operations
# => [%Fount.Edit.Op{kind: :replace_text, target_id: "...", ...}]

# Revision content hashes advance immutably:
revised_script.revision.id != script.revision.id # => true
```

### 4. Cast Intelligence & Byte-Anchored Mentions

Decouple dialogue cues from underlying character identities:

```elixir
alias Fount.Cast.{Character, Alias, Mention}

# 1. Register canonical character
marcus = %Character{id: Fount.Id.v4(), display_name: "Marcus Vance"}

# 2. Map speaking cues and nicknames
alias_cue = %Alias{character_id: marcus.id, alias: "MARCUS", kind: :cue}
alias_nick = %Alias{character_id: marcus.id, alias: "Mark", kind: :dialogue_reference}

# 3. Track exact byte-anchored mentions in script elements
mention = %Mention{
  element_id: dialogue_element.id,
  character_id: marcus.id,
  surface: "Mark",
  byte_start: 14,
  byte_end: 18,
  role: :direct_address,
  status: :confirmed
}
```

### 5. PostgreSQL Revision Persistence

Save canonical screenplays, normalized scene rows, and immutable draft snapshots to PostgreSQL:

```elixir
# Start Fount.Repo in your application supervision tree:
{:ok, _} = Fount.Repo.start_link(url: System.fetch_env!("DATABASE_URL"))

# Save a screenplay under a unique key:
{:ok, saved} = Fount.Persistence.save(Fount.Repo, "my-feature-slug", script)

# Reload the screenplay at the latest accepted head:
{:ok, current_draft} = Fount.Persistence.load(Fount.Repo, "my-feature-slug")

# Reopen an exact historical draft by revision UUID:
{:ok, draft_v1} = Fount.Persistence.load_revision(
  Fount.Repo, 
  saved.id, 
  "rev-b84f2910-..."
)
```

---

## Executable Live Examples

Fount includes complete executable scripts demonstrating multi-format export, roundtrip verification, and PostgreSQL revision branching:

```bash
# Export screenplay to Fountain, FDX, and Canonical JSON:
mix run examples/live.exs --mode roundtrip --out examples/_output/roundtrip

# Test multi-format interchange fidelity:
mix run examples/live.exs --mode interchange --out examples/_output/interchange

# Test PostgreSQL persistence and historical revision reload:
mix run examples/live.exs --mode database --out examples/_output/database
```

Consult the [**Examples Guide**](examples/README.md) for full instructions, prerequisites, and output manifests.

---

## Comprehensive Guides

Explore in-depth documentation covering Fount's internal subsystems:

* [**Architecture Overview**](guides/architecture.md) — The Four Truths, functional core boundaries, and data lifecycles.
* [**Lossless Fountain**](guides/lossless-fountain.md) — Concrete Syntax Trees, trivia preservation, and roundtrip mechanics.
* [**Screenplay IR**](guides/ir.md) — Flat element streams, structural scene hierarchies, and durable UUIDs.
* [**Cast & Mentions**](guides/cast-and-mentions.md) — Character normalization, alias resolution, and rename ripple plans.
* [**Editing & Generation**](guides/editing.md) — Atomic edit operations, changeset validation, and Myers diffing.
* [**Annotations & Analysis**](guides/annotations-and-analysis.md) — Source provenance, confidence scoring, and metric bounds.
* [**Relational Persistence**](guides/persistence.md) — PostgreSQL schemas, transaction boundaries, and immutable snapshots.
* [**Format Adapters**](guides/adapters.md) — Fountain, Final Draft (`.fdx`), and JSON projection boundaries.
* [**Design Research**](guides/research.md) — Lessons and precedents from Beat, Story Architect (STARC), and ScreenPy.
* [**Live Examples**](examples/README.md) — Executable interchange and persistence test scripts.

---

## The Fount Ecosystem

Fount is the foundation of a modular three-tier screenplay framework:

1. **[Fount](https://hexdocs.pm/fount)**: The headless screenplay engine, lossless CST parser, and relational revision store.
2. **[Fount Probe](https://hexdocs.pm/fount_probe)**: The dramaturgical auditor and diagnostic engine. 100% read-only inspection for character knowledge, continuity, scene mechanics, and voice attribution.
3. **[Fount Workshop](https://hexdocs.pm/fount_workshop)**: The writer's studio. Bounded AI revision loops with Myers diffs, beat recovery, competition submission checks, and PDF publishing.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
