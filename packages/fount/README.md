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

Fount is a headless screenplay framework with a format-independent canonical model. Fountain and FDX are import/export adapters. Untouched Fountain imports retain exact bytes and CST for lossless export; structured authoring can begin without either format.

## Design

Fount has four kinds of truth:

1. **Source truth** - exact bytes, line endings, whitespace, syntax markers, comments, notes, boneyards, and source spans.
2. **Screenplay truth** - normalized typed screenplay elements, scenes, dialogue blocks, outline structure, and durable IDs.
3. **Interpretive truth** - annotations from deterministic analyzers, NLP, or model-backed systems, each tied to source revision and provenance.
4. **Presentation/operational truth** - pagination, timing, reports, JSON, FDX, production breakdowns, and other projections.

Canonical edits transform immutable `Fount.Screenplay` values and preserve stable IDs. The older `Fount.Document` API remains for source-backed Fountain edits: it creates source patches, reparses and reconciles identities.

## Quick use

```elixir
{:ok, doc} = Fount.parse("""
INT. KITCHEN - NIGHT

MARA
Don't.
""")

Fount.render(doc) == doc.source.raw

scene = doc |> Fount.scenes() |> hd()
{:ok, changed, change_set} =
  Fount.apply(doc, Fount.Edit.set_scene_heading(scene.id, "INT. KITCHEN - DAWN"))
```

Create canonical screenplay content directly from typed elements:

```elixir
script = Fount.Screenplay.new(scenes: [
  %{heading: "INT. KITCHEN - NIGHT", elements: [
    %{type: :character, text: "MARA"},
    %{type: :dialogue, text: "Don't."}
  ]}
])

dialogue = Enum.find(script.ir.elements, &(&1.type == :dialogue))
{:ok, revised} = Fount.Screenplay.apply(script, Fount.Edit.replace_text(dialogue.id, "Wait."))
Fount.Screenplay.to_fountain(revised)
```

## Persistence

`Fount.Persistence` is the canonical relational boundary. Fount owns its Ecto Repo, migrations, schemas, queries and transactions; PostgreSQL is the primary backend. The screenplay transformation functions remain usable without starting the Repo. Current scenes, elements, turns, cast and mentions are typed rows, while immutable revision snapshots provide history. See the [persistence guide](guides/persistence.md).

`Fount.Store.Filesystem` and `Fount.Store.SQLite` remain compatibility stores for source-backed Fountain documents. SQLite v1 is not the canonical relational model. It remains optional through Exqlite.

## Why no whole-language parser generator?

Fountain is line-oriented and context-sensitive. Whether an uppercase line is a character cue depends on neighboring empty lines; dialogue depends on the preceding cue; boneyards can span lines; notes have their own multiline rule; exact whitespace and mixed line endings matter. Fount therefore uses a custom byte-preserving scanner, a context-aware parser, and a CST. General parser combinators remain appropriate for small future subgrammars, but are not the architecture of the Fountain parser.

## Guarantees and limits

Untouched Fountain renders byte-for-byte from its CST, including line endings, trivia, malformed notes, and unknown lines. Structural classification is conservative and contextual. Stable IDs survive source edits when a semantic match or explicit edit hint identifies the same object; an unmatched changed object gets an `:identity_not_retained` diagnostic. Arbitrary source rewrites can change IDs.

FDX and JSON are adapters, not the canonical model. FDX supports practical spec-script interchange and returns `losses` for known unsupported production metadata and styling. Do not assume an arbitrary FDX file round-trips exactly.

Filesystem saves can use `expected_revision: doc.revision.id` to reject an external edit before saving. This is a single-writer optimistic check, not a cross-process transaction. SQLite supports `Fount.Store.SQLite.init/1` and a caller-owned open connection via `Fount.Store.SQLite.new(conn: conn)`. The caller owns and closes that handle.

Scene-heading decomposition has English default time terms and accepts `time_terms:` or `extra_time_terms:` in `Fount.SceneHeading.parse/2`; raw heading text is always retained.

The separate [Fount Workshop](https://github.com/nshkrdotcom/fount/tree/main/packages/fount_workshop) app adds model proposals, PDF export, and dated submission checks without bringing those dependencies into the core.

Add `{:exqlite, "~> 0.41"}` to a host application only when using the legacy `Fount.Store.SQLite` workflow.

## Quality checks

From `packages/fount`, run:

```bash
mix deps.get
mix format --check-formatted
mix deps.unlock --check-unused
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
mix docs
mix hex.build
```
