# Architecture

Fount is a headless screenplay substrate. Fountain is the preferred authoring surface, not the in-memory architecture.

## Four kinds of truth

Fount keeps four concerns separate:

1. **Source truth** — exact bytes, line endings, whitespace, syntax markers, notes, boneyards, and byte spans.
2. **Screenplay truth** — typed screenplay elements, scenes, dialogue blocks, outline structure, and durable identities.
3. **Interpretive truth** — derived entities, events, relationships, metrics, summaries, NLP, or model output with provenance.
4. **Presentation/operational truth** — pagination, reports, JSON, FDX, production breakdowns, and other projections.

The edit algebra cuts vertically through those layers: a semantic edit resolves to exact source patches, reparses source, reconciles identities, invalidates affected derived annotations, and returns a `Fount.Edit.ChangeSet`.

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

## No hidden mutable runtime

The initial package is deliberately process-free. There is no application supervision tree, cache server, database process, or global registry. Documents are ordinary immutable values. Consumers can place them behind GenServers, web endpoints, collaborative systems, or job processors without Fount imposing a runtime topology.

## Extension boundaries

- `Fount.Analyzer` — add derived interpretation without changing screenplay truth.
- `Fount.Store` — persist source plus reconstructible metadata using any backend.
- `Fount.Adapter` — import/export foreign formats while reporting fidelity losses.
- `Fount.Fragment` / `Fount.Builder` — generate valid screenplay source from structured values.

The core intentionally has no dependency on an LLM, vector database, web framework, editor toolkit, or PostgreSQL client.
