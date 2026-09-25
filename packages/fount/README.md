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

**A headless screenplay engine and relational authoring platform for Elixir.**

Fount treats screenplays as structured, queryable data rather than flat text files. It decouples screenplay truth from external syntax: Fountain and Final Draft (FDX) serve as lossless import and export boundaries, while your screenplay exists as an immutable, typed model backed by PostgreSQL and Ecto.

---

## The Four Truths

Screenplay systems fail when they conflate formatting quirks with dramatic structure. Fount enforces four distinct architectural layers:

```text
┌──────────────────────────────────────────────────────────────┐
│  1. SOURCE TRUTH                                             │
│  Exact imported bytes, CST, trivia, and syntax spans         │
└──────────────────────────┬───────────────────────────────────┘
                           │ import / project
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  2. SCREENPLAY TRUTH                                         │
│  Canonical elements, scenes, dialogue turns, durable UUIDs   │
└──────────────────────────┬───────────────────────────────────┘
                           │ analyses / resolution
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  3. INTERPRETIVE TRUTH                                       │
│  Authored cast, aliases, byte-anchored mentions, assertions  │
└──────────────────────────┬───────────────────────────────────┘
                           │ render / layout
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  4. PRESENTATION TRUTH                                       │
│  Laid-out PDF pages, eighths, timing, and rehearsal audio    │
└──────────────────────────────────────────────────────────────┘
```

1. **Source Truth:** Exact imported bytes, comments, boneyards, and line endings. Untouched files round-trip byte-for-byte.
2. **Screenplay Truth:** Format-independent elements, scenes, and dialogue blocks identified by durable UUIDs.
3. **Interpretive Truth:** Authored characters, aliases, byte-anchored occurrences, and evidence-backed claims tied to revisions.
4. **Presentation Truth:** Laid-out PDF pages, page eighths, timing estimates, and audio table reads.

---

## Quickstart

### 1. Parse Lossless Fountain

Import raw Fountain text into an exact Concrete Syntax Tree (CST) and semantic Intermediate Representation (IR):

```elixir
{:ok, doc} = Fount.parse("""
EXT. BRICK HOUSE - NIGHT

SARAH
We have to keep moving.

She checks the perimeter.
""")

# Untouched source round-trips byte-for-byte:
Fount.render(doc) == doc.source.raw
```

### 2. Author a Canonical Screenplay

Build a screenplay directly from typed data without needing Fountain punctuation:

```elixir
alias Fount.Screenplay

script = Screenplay.new(
  title: [title: "TERMINUS", credit: "written by", author: "Jane Doe"],
  scenes: [
    %{
      heading: "INT. BUNKER - NIGHT",
      elements: [
        %{type: :character, text: "SARAH"},
        %{type: :dialogue, text: "The signal is gone."},
        %{type: :action, text: "A distant rumble shakes the dust."}
      ]
    }
  ]
)
```

### 3. Atomic Edits and Revision Advancement

Apply pure transformations to elements or scenes. Edits validate constraints, advance the revision hash, and compute semantic diffs:

```elixir
dialogue_element = Enum.find(script.ir.elements, &(&1.type == :dialogue))

{:ok, revised} = Screenplay.apply(
  script,
  Fount.Edit.replace_text(dialogue_element.id, "The signal is back.")
)

# Export the revised canonical model to Fountain:
fountain_text = Screenplay.to_fountain(revised)
```

### 4. Cast, Aliases, and Byte-Anchored Mentions

Decouple dialogue cues from character identity. Track character presence vs. spoken references across scenes:

```elixir
alias Fount.Cast.{Character, Alias, Mention}

# 1. Author the canonical character
sarah = %Character{id: Fount.Id.v4(), display_name: "Sarah Connor"}

# 2. Map aliases (cues vs direct address)
alias_cue = %Alias{character_id: sarah.id, alias: "SARAH", kind: :cue}

# 3. Track exact byte-anchored mentions in script elements
mention = %Mention{
  element_id: dialogue_element.id,
  character_id: sarah.id,
  surface: "SARAH",
  byte_start: 0,
  byte_end: 5,
  role: :speaker_cue,
  status: :confirmed
}
```

### 5. Relational Persistence with Ecto

Save canonical screenplays, normalized current rows, and immutable revision snapshots into PostgreSQL:

```elixir
# Start Fount.Repo in your supervision tree, then persist:
{:ok, script} = Fount.Persistence.save(Fount.Repo, "my-feature", script)

# Reload at the latest revision:
{:ok, loaded} = Fount.Persistence.load(Fount.Repo, "my-feature")
```

---

## Documentation Guides

Explore comprehensive guides on Fount's subsystems:

* [**Architecture Overview**](guides/architecture.md) — The Four Truths model, poncho workspace design, and functional core boundaries.
* [**Lossless Fountain**](guides/lossless-fountain.md) — Byte-covering scanner, concrete syntax trees, and exact round-tripping.
* [**Screenplay IR**](guides/ir.md) — Flat element streams, structural views, and durable object identities.
* [**Cast & Mentions**](guides/cast-and-mentions.md) — Normalized character entities, alias resolution, and rename ripple plans.
* [**Editing & Generation**](guides/editing.md) — Structured operations, immutable transforms, diffing, and undo/redo change sets.
* [**Annotations & Analysis**](guides/annotations-and-analysis.md) — Provenance tracking, confidence scoring, and metric boundaries.
* [**Relational Persistence**](guides/persistence.md) — Ecto schemas, PostgreSQL transactions, migrations, and query interfaces.
* [**Format Adapters**](guides/adapters.md) — Fountain, Final Draft (FDX), and JSON projection boundaries.
* [**Design Research**](guides/research.md) — Precedents and lessons from Beat, Story Architect (STARC), BookNLP, and ScreenPy.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Source continuation (2026-09-24)

The continuation adds canonical interchange, revision-aware inspection and writer-session/candidate APIs with CLI and real-only example modes. This pass is **uncompiled and untested**; it is not a release-completion claim. Read the [implementation handoff](../../docs/implementation_handoff/README.md) for actual source coverage, explicit missing functionality, safe application and local verification.
