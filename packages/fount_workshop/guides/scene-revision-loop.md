# Scene revision loop

`FountWorkshop.TargetedRewrite.propose/4` takes an accepted screenplay value,
exact action or dialogue element IDs, a writer direction, and an Inference
client. It includes nearby scenes for continuity, asks for replacements keyed
to those IDs, validates the response, and applies typed edits in memory.

`FountWorkshop.TargetedRewrite.run/5` loads the accepted draft from PostgreSQL,
saves a writing session and candidate revision, and returns the candidate ID.
The accepted head stays where it was. Use `FountWorkshop.Review.packet/2` to
inspect the exact source and structural differences; use
`FountWorkshop.Review.accept/4` only after the writer makes a review decision.

`NoteResponse` uses the same exact edit path but removes the addressed note
from the candidate. Other notes remain. `SequenceRebuild` replaces a run of
scenes and retains IDs for unchanged scenes and lines. `CharacterRewrite`
selects one character's dialogue and immediate partner replies across chosen
scenes.
