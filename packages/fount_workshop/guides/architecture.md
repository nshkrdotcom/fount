# Workshop architecture

Fount owns screenplay values, exact edits and PostgreSQL revisions. Fount.Intelligence
owns source-grounded inspection and Jev calls. FountWorkshop uses Inference to
write candidate pages, saves them through `Fount.Persistence`, and renders
reviewable outputs.

A writer starts with an accepted draft or an empty root, requests a writing
operation, inspects the saved candidate and its Fountain/PDF output, then makes
an explicit review decision. `FountWorkshop.Review.accept/4` accepts `(repo, candidate_id, approval, authority)`. The typed approval binds the exact review/candidate/check set and the authority is trusted host context constructed outside request payloads. PostgreSQL compares the candidate base with the current accepted head in the same transaction. A stale candidate cannot overwrite
another accepted revision.

The current writer operations are `Develop`, `TargetedRewrite`,
`SequenceRebuild`, `CharacterRewrite`, `NoteResponse`, `Pass` and `Recover`.
They are screenplay-specific operations, not a generic agent runtime.
`examples/live.exs` is the one executable real-service example entrypoint for
this package; its modes show actual candidates and outputs.