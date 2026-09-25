# Architecture

Fount is a headless screenplay framework. Fountain and FDX are import/export formats around a canonical typed model.

## Four kinds of truth

Fount keeps four concerns separate:

1. **Source truth** — exact bytes, line endings, whitespace, syntax markers, notes, boneyards, and byte spans.
2. **Screenplay truth** — typed screenplay elements, scenes, dialogue blocks, outline structure, and durable identities.
3. **Interpretive truth** — derived entities, events, relationships, metrics, summaries, NLP, or model output with provenance.
4. **Presentation/operational truth** — pagination, reports, JSON, FDX, production breakdowns, and other projections.

Canonical edits transform an immutable `Fount.Screenplay` and advance its revision. The source-backed `Fount.Document` compatibility path resolves edits to patches, reparses Fountain, reconciles identities, and returns a `Fount.Edit.ChangeSet`.

## CST plus screenplay IR, not an AST alone

A conventional AST would discard exactly the information Fount most needs to retain: whitespace, forcing markers, line terminators, comments/notes, boneyards, and unknown source forms. Fount therefore uses two representations:

- `Fount.Fountain.CST` is a byte-covering concrete syntax tree. Its ordered nodes reconstruct the original Fountain binary exactly.
- `Fount.IR.Script` is the normalized screenplay model callers query and transform.

The CST answers *what was written*. The IR answers *what screenplay structure it represents*.

Fount deliberately does not use a whole-language parser generator. Fountain is line-oriented and context-sensitive: an uppercase line may be a character cue only because of its neighbors; dialogue depends on a preceding cue; notes and boneyards span lines; whitespace-only dialogue can be meaningful. A small byte scanner plus contextual classifier/parser makes those rules explicit while retaining exact source coordinates. A parser combinator could still be appropriate for a future isolated subgrammar.

## Canonical element stream

The semantic core is a single ordered element stream. Scenes, dialogue blocks, and outline nodes are ID-based views over that stream rather than nested copies. This avoids synchronization bugs when an edit would otherwise need to mutate the same logical dialogue in multiple trees.

## Stable identity

Byte offsets are locations, not identities. Fount assigns IDs to structural objects and persists semantic identity anchors separately from Fountain text. After edits or external file changes, reconciliation uses semantic signatures, neighboring signatures, ordinal proximity, and explicit edit hints. The same resolved IDs are applied to CST and IR.

This permits tools to say “replace dialogue `X`” even after material has been inserted earlier in the script.

Reconciliation is best-effort for external source rewrites. If a changed object of the same type cannot be confidently matched, parsing emits `:identity_not_retained`; callers can inspect `doc.diagnostics` before applying annotations or further edits.

## Functional core and persistence boundary

Screenplay construction, editing, analysis, and format projection work on immutable values without a database process. Fount also owns an Ecto/PostgreSQL persistence boundary: migrations, typed current rows, immutable revisions, transactions, and composable queries. The consuming application configures and starts `Fount.Repo`; Fount does not impose an application supervision tree.

## Extension boundaries

- `Fount.Analyzer` — add derived interpretation without changing screenplay truth.
- `Fount.Persistence` — persist the canonical model in PostgreSQL and query its current typed rows.
- `Fount.Persistence` — revision-scoped PostgreSQL storage for accepted drafts, candidates, sessions and reports.
- `Fount.Adapter` — import/export foreign formats while reporting fidelity losses.
- `Fount.Fragment` / `Fount.Builder` — generate valid screenplay source from structured values.

The core intentionally has no dependency on an LLM, vector database, web framework, or editor toolkit. Its relational boundary uses PostgreSQL; pure model APIs do not require a running database.
