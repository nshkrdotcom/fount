# Lossless Fountain

Lossless Fountain is the intentionally defensive part of Fount.

## Source is authoritative

`Fount.Source` retains the original binary. `Fount.Fountain.Scanner` walks bytes rather than normalizing strings and records each line's content, terminator, full span, and content span. LF, CRLF, CR, mixed terminators, a missing terminal newline, and even invalid UTF-8 remain representable.

Semantic parsing is conservative when the source is not valid UTF-8, but byte reconstruction still works.

## Byte-covering CST

Every byte belongs to an ordered `Fount.Fountain.CST.Node`. This includes title-page separator lines that have no screenplay meaning; they become `:title_trivia` nodes instead of vanishing.

The central invariant is:

```elixir
Fount.Fountain.CST.render(doc.cst) == doc.source.raw
```

`Fount.render/2` uses the CST reconstruction path. It is intentionally different from `Fount.serialize/2`, which emits a normalized Fountain projection from the semantic IR.

## Spans

`Fount.Source.Span` uses half-open byte offsets. Source spans address the whole lexical construct; content spans address only the semantic text that may be safely replaced.

For example, replacing a parenthetical edits the bytes inside `(` and `)` rather than removing the delimiters. Renaming a character does not overwrite its extension or dual-dialogue marker. Replacing a scene heading leaves a scene number outside the content span intact.

## Fountain constructs covered by the source parser

The initial parser handles the major Fountain 1.1 authoring constructs needed by a headless screenplay engine:

- title page fields and continuations
- scene headings, forced scene headings, and scene numbers
- action and forced action
- character cues, extensions, forced cues, and dual dialogue
- dialogue and parentheticals, including meaningful whitespace-only dialogue
- transitions and forced transitions
- centered text and lyrics
- sections and synopses
- page breaks
- standalone notes
- boneyards
- inline emphasis scanning

Unknown text falls back to action rather than being discarded.

## Validation

`Fount.Validate` checks the lossless invariants rather than merely asking whether parsing produced a struct:

- CST nodes cover the source contiguously
- each node's raw bytes equal its source slice
- source/content spans are valid and nested correctly
- CST screenplay IDs and IR element IDs remain aligned
- IR identities are unique
- scene and dialogue references resolve

These checks are deliberately stronger than the rest of the package's testing philosophy because exact source preservation is a core product promise.
