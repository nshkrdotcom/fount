# Candidates and differences

Generative completions pass through `FountWorkshop.Writing.Completion`, which
uses Inference and a local validator. A completion cannot name an unknown
target ID or bypass `Fount.Screenplay.apply/3`. Invalid output gets one repair
attempt. A failed later route leaves earlier saved candidates in a partial
session for resume.

`FountWorkshop.Review.packet/2` loads the actual candidate and base revision.
It contains exact Fountain for both, a Myers source difference, a structural
difference, change groups, lineage and check references. Candidate pages can
be reopened, exported and rendered before acceptance.

The supplied `ReviewGate` checks review content and acknowledged concerns.
`Fount.Persistence.accept_candidate/3` then locks the candidate and accepted
head, checks the base and content hash, records acceptance, and moves the head
atomically. `Review.reject/3` preserves a rejected candidate for history.
