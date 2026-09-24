# Editing and Generation

`Fount.Screenplay.apply/2` edits the canonical typed model with immutable values. The older source-backed `Fount.Edit.apply/3` path remains for exact Fountain documents.

## Edit pipeline

For `Fount.Document`, an operation such as `Fount.Edit.replace_text/2` follows this path:

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

For the canonical model, `Fount.Screenplay.plan_character_rename/3` identifies confirmed cues to change and exact named references in action, dialogue, and parentheticals for writer review. `accept_character_rename/2` updates the authored cast name and confirmed cues at one new revision; it leaves literary phrasing untouched. The plan rejects a changed base revision.

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

The legacy `Fount.Document` builder emits Fountain and reparses it through the lossless parser. `Fount.Screenplay.new/1` also supports direct typed construction without Fountain punctuation, including sections and synopses outside scenes. Canonical model edits keep stable IDs and regenerate Fountain on export.

## Agent/tool contract

Tool-using models should operate on IDs and validated operations rather than rewriting entire screenplay blobs. The same interface is useful to CLIs, IDEs, batch refactoring tools, collaborative systems, and web editors, so the core itself contains no AI-specific code.
