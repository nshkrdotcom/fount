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

**The canonical headless screenplay substrate, semantic intermediate representation (IR), lossless Fountain parser, and screenplay compilation runtime.**

Fount is designed from first principles for script analysis, deterministic transformation algebra, and AI/agentic screenwriting workflows.

---

## The Four Kinds of Truth

Fount strictly decouples screenplay reality into four distinct architectural layers:

```text
┌──────────────────────────────────────────────────────────────┐
│  1. SOURCE TRUTH                                             │
│  Exact Fountain text + concrete syntax + source spans        │
└──────────────────────────┬───────────────────────────────────┘
                           │ lossless parse / project
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  2. SCREENPLAY TRUTH                                         │
│  Typed screenplay structure & durable element UUID identity  │
└──────────────────────────┬───────────────────────────────────┘
                           │ analyses / resolution
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  3. INTERPRETIVE TRUTH                                       │
│  Entities, beats, events, relationships, NLP, AI annotations │
└──────────────────────────┬───────────────────────────────────┘
                           │ projections
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  4. PRESENTATION / OPERATIONAL TRUTH                         │
│  Pages, timing, eighths, reports, FDX, PDF, breakdown sheets │
└──────────────────────────────────────────────────────────────┘

             EDIT / PATCH / DIFF ALGEBRA
       cuts vertically through the whole system
```

1. **Source Truth (`CST`)**: Exact character-for-character reproduction, formatting delimiters, line endings, comments, boneyards, and source spans. Untouched Fountain round-trips with zero loss (`print(parse(source)) == source`).
2. **Screenplay Truth (`IR`)**: First-class typed domain model (`Scene`, `Heading`, `Action`, `DialogueBlock`, `Parenthetical`, `Transition`, `Shot`). Every meaningful node retains durable, position-independent identity (`UUID`).
3. **Interpretive Truth (`Annotations`)**: Inferred data (narrative beats, dramatic polarities, entity coreference, character interaction networks, semantic actions) anchored to nodes via provenance-tracked annotations without polluting the screenplay model.
4. **Presentation & Operational Truth (`Projections`)**: Read-only derived views including page-eighth calculations, pagination fragments, FDX interchange, PDF typesetting, and production breakdown reports.

---

## Architectural Principles

- **Lossless Fountain Round-Trip**: The Concrete Syntax Tree preserves whitespace, comments, forced syntax, and indentation.
- **Durable Identity**: Structural elements possess persistent IDs so mutations and downstream annotations survive upstream insertions and reorderings.
- **Screenplay Edit Algebra**: Modifications occur via explicit `ChangeSet` operations (`insert_scene`, `replace_dialogue`, `move_element`, `split_action`), yielding complete audit trails, deterministic undo/redo, and safe agent execution.
- **Format Adapters**: Fountain is the native text surface. FDX and other external formats are pure bidirectional adapters with explicit fidelity reporting.
- **Agent Interface**: LLMs interact with constrained semantic operations against the screenplay IR rather than blindly overwriting large raw text files.

---

## Repository Structure

This repository is structured as a Poncho project:

```text
.
├── LICENSE
├── CHANGELOG.md
├── README.md
├── assets/
│   └── fount.svg
└── packages/
    └── fount/          # Core Fount engine and Mix project
```

---

## License

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom
