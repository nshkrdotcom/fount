# Editing and Generation

Fount edits canonical source rather than allowing arbitrary mutation of IR structs.

## Edit pipeline

An operation such as `Fount.Edit.replace_text/2` follows this path:

1. resolve the stable target ID
2. resolve its exact content/source span
3. create one or more `Fount.Edit.Patch` values
4. validate and apply patches to the source binary
5. parse the resulting source
6. reconcile old and new identities
7. rebuild indexes/views
8. invalidate annotations affected by changed elements, scenes, dialogue blocks, or outline nodes
9. return a `Fount.Edit.ChangeSet`

A change set records operations, steps, patches, affected IDs, before/after revisions, and snapshots required for exact undo/redo of source plus identities and annotations.

## Syntax-aware operations

Specialized operations preserve Fountain meaning. Examples:

- renaming an uppercase cue to mixed case adds `@` when necessary
- changing a conventional scene heading to `MONTAGE` adds `.` when necessary
- scene numbers, character extensions, dual markers, and parenthetical delimiters sit outside replaceable content spans

`replace_text/2` remains deliberately literal for callers that want exact control.

## Structured generation

`Fount.Fragment` and `Fount.Builder` let a tool create screenplay constructs without knowing Fountain punctuation:

```elixir
builder =
  Fount.Builder.new()
  |> Fount.Builder.title("Title", "Example")
  |> Fount.Builder.scene("INT. LAB - NIGHT", [
    Fount.Fragment.action("Rain rattles the glass."),
    Fount.Fragment.dialogue("Mara", "We're late.", extension: "V.O.")
  ])

{:ok, doc} = Fount.Builder.to_document(builder)
```

Generated Fountain is always reparsed through the same canonical parser; generation does not create a competing mutable document representation.

## Agent/tool contract

Tool-using models should operate on IDs and validated operations rather than rewriting entire screenplay blobs. The same interface is useful to CLIs, IDEs, batch refactoring tools, collaborative systems, and web editors, so the core itself contains no AI-specific code.
