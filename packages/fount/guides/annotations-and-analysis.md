# Annotations and Analysis

Interpretation is derived data, not screenplay truth.

## Annotation model

`Fount.Annotation` targets a structural ID and optionally a source span. It records a namespace/kind, arbitrary value, provenance, confidence, and dependencies. Provenance can identify the producer, producer version, model, source revision, and creation time.

That one mechanism can represent deterministic metrics and future NLP/model output without adding fields to `Fount.IR.Scene` for every possible interpretation.

Potential annotation families include:

- character/entity resolution and aliases
- locations and props
- events and actions
- beats, goals, conflict, reveals, or scene polarity
- dialogue classifications and style metrics
- continuity observations
- summaries and retrieval passages
- embeddings
- lint/coverage notes
- production breakdown tags

## Invalidation

Edits identify structurally affected IDs. Fount drops annotations targeting those IDs or depending on them; unaffected annotations remain. Persisted sidecars are pruned again at load if source was changed externally and targets disappeared.

## Built-in analyzers

The initial package includes intentionally small deterministic analyzers:

- `Fount.Analyzers.Characters`
- `Fount.Analyzers.CharacterEntities`
- `Fount.Analyzers.Locations`
- `Fount.Analyzers.Dialogue`

They demonstrate the contract without pretending that heuristic entity/coreference or dramatic interpretation belongs in the parser.

## Semantic graph

`Fount.Semantics.Graph` provides typed entity, mention, relation, and event containers for richer analysis systems. These structures stay separate from canonical IR and can therefore contain competing or uncertain interpretations with provenance.
