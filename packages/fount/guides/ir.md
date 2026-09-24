# Screenplay IR

`Fount.IR.Script` is format-neutral screenplay structure inside `Fount.Screenplay`. It can be constructed directly from typed data or populated through a Fountain import. The imported CST is retained separately for exact unchanged export.

## Flat ordered elements

`Script.elements` is authoritative for screenplay order. Each `Fount.IR.Element` has:

- stable `id`
- typed `type`
- normalized semantic `text`
- source-backed raw text where available
- source and content spans
- inline formatting marks
- structural attributes such as scene number, character extension, or dual-dialogue state
- origin metadata

Scenes, dialogue blocks, and outline nodes reference element IDs instead of copying their content.

## Structural views

- `Fount.IR.Scene` begins at a scene-heading element and references the ordered elements in that scene.
- `Fount.IR.DialogueBlock` groups a cue with its parenthetical/dialogue body and represents dual-dialogue linkage.
- `Fount.IR.OutlineNode` derives writer-facing hierarchy from Fountain sections.
- `Fount.IR.TitlePage` preserves semantic title-page entries separately from the body stream.

`Fount.IR.rebuild_views/1` makes the derived views deterministic from the element stream.

## Literal cues are not character entities

A parser can know that `MOM (O.S.)` is a character cue without knowing whether `MOM`, `HELEN`, and `YOUNG HELEN` refer to one dramatic entity. Literal cues stay in the IR. Writer-authored cast entries in `Fount.Screenplay.cast` have durable IDs; cue links and other occurrences are separate evidence in `Fount.Screenplay.mentions`.

This prevents inference from becoming canonical screenplay fact.

## Raw and parsed structure coexist

Structured interpretations should never make unusual but legal writing unrepresentable. A scene heading keeps its literal text while `Fount.SceneHeading` can derive context/location/time fields. The same rule should govern future richer parsers: preserve the written form; attach useful normalized structure separately.
