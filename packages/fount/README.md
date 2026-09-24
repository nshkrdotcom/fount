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

Fount is a headless screenplay framework. Fountain is its preferred authoring surface, but Fountain text, the screenplay model, inferred analysis, and rendered/operational outputs are deliberately separate layers.

## Design

Fount has four kinds of truth:

1. **Source truth** - exact bytes, line endings, whitespace, syntax markers, comments, notes, boneyards, and source spans.
2. **Screenplay truth** - normalized typed screenplay elements, scenes, dialogue blocks, outline structure, and durable IDs.
3. **Interpretive truth** - annotations from deterministic analyzers, NLP, or model-backed systems, each tied to source revision and provenance.
4. **Presentation/operational truth** - pagination, timing, reports, JSON, FDX, production breakdowns, and other projections.

Edits are explicit operations that create source patches and `Fount.Edit.ChangeSet` values. The source is reparsed and identities are reconciled rather than allowing arbitrary mutation of internal structs.

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

## Persistence

`Fount.Store` is the persistence boundary.

- `Fount.Store.Filesystem` is the default recommendation: `.fountain` remains canonical and a `.fount.json` sidecar stores identity anchors, annotations, and revision metadata. It is portable and Git-friendly.
- `Fount.Store.SQLite` is built in for applications that need transactional storage, revision history, indexed document lists, or many annotations without scattering sidecar files.
- PostgreSQL is intentionally not a core dependency. A future server-oriented package can implement the same behavior without changing Fount's domain layer.

## Why no whole-language parser generator?

Fountain is line-oriented and context-sensitive. Whether an uppercase line is a character cue depends on neighboring empty lines; dialogue depends on the preceding cue; boneyards can span lines; notes have their own multiline rule; exact whitespace and mixed line endings matter. Fount therefore uses a custom byte-preserving scanner, a context-aware parser, and a CST. General parser combinators remain appropriate for small future subgrammars, but are not the architecture of the Fountain parser.

## Guarantees and limits

Untouched Fountain renders byte-for-byte from its CST, including line endings, trivia, malformed notes, and unknown lines. Structural classification is conservative and contextual. Stable IDs survive source edits when a semantic match or explicit edit hint identifies the same object; an unmatched changed object gets an `:identity_not_retained` diagnostic. Arbitrary source rewrites can change IDs.

FDX and JSON are adapters, not the canonical model. FDX supports practical spec-script interchange and returns `losses` for known unsupported production metadata and styling. Do not assume an arbitrary FDX file round-trips exactly.

SQLite is optional for consumers. Add `{:exqlite, "~> 0.41"}` to the host application's dependencies when using `Fount.Store.SQLite`; the filesystem store needs no native database dependency.

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
