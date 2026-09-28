# Discovery, session modes, and scene exploration

Phase 12 adds a writer-first discovery layer without creating a second screenplay model. Canon stays in Fount Core. Session-owned discovery material lives in `writing_sessions.progress.discovery`, and generated or writer-authored pages remain Workshop candidates until explicit acceptance.

## Modes

New requests explicitly select one of four writer-facing modes:

- `draft` writes or continues without requiring pre-write analysis;
- `explore` keeps materially different possibilities available without selecting a winner;
- `inspect` is a bounded evidence/interpretation mode and does not auto-materialize pages;
- `revise` creates a scoped candidate for comparison and review.

The legacy `diagnose` spelling remains accepted for compatibility, but discovery presentation normalizes it to `inspect`. `Session.switch_mode/4` is explicit and writes a mode-history entry. The immutable opening request remains unchanged; subsequent execution reads the saved explicit current mode.

`Session.open/4` is provider-free. It validates the same `Request`, records resource preflight, initializes discovery state and changes no screenplay content. `Session.start/4` keeps its generation behavior and still requires an explicit `Inference.Client`.

## Evolving brief and fragments

`FountWorkshop.Discovery` stores optional desired experience, current question, audience/context, formal constraints, protected strengths and permission to depart. Unknown values are allowed. Updates retain before/after history.

Fragments are writer-owned records with kinds `image`, `line`, `action`, `relationship`, `research_question`, `ending`, or `fragment`. They may be unattached, linked to a canonical scene ID, adopted into a candidate, or retired without deletion. Wanted/connective classification is independently changeable and historical.

`reverse_outline/3` derives cards from the canonical scene IDs and heading IDs. Any supplied scene function is labeled `interpretation`; absent functions remain `unknown`. `propose_reorder/4` requires an exact permutation of the base scene identities and stores only a noncanonical reorder proposal.

## Writer-origin candidates without a model call

`FountWorkshop.Candidate.manual/4` accepts explicit typed Fount edit operations, marks the change group `writer_edit`, compiles it against the immutable session base and sends it through the existing checks/persistence/review path. `FountWorkshop.Candidate.edit/4` can then edit that candidate again. Neither operation needs Inference when no semantic constraint requires Observe.

This is the human-only route used by `mix fount.manual` and `mix fount.edit`. Capture, reverse outline, brief edits, mode switches, candidate comparison, acceptance and export all have provider-free CLI paths. Database persistence is still required for those durable commands.

## Treatment contracts

For `workflow: "alternatives"`, an optional `options.treatments` list can bind each requested route to a finite treatment ID, one mechanism kind (`action`, `revelation`, `relationship`, or `mixed`) and a writer instruction. When treatments are supplied, each strategy must also return:

- the exact `treatment_id` and `mechanism_kind`;
- at least one likely tradeoff;
- preserved material through the existing `preserves` field;
- `brief_departure` with an explicit boolean and reason.

Treatment count must equal the request's `alternatives` count. If `allow_brief_departure` is false, a route cannot silently claim a departure. The prompt explicitly forbids winner/quality ranking and mere paraphrase as diversity.

The default Explore count remains three and the workflow schema caps alternatives at five. Draft defaults to one route. Existing callers that do not request treatment contracts retain the older strategy payload contract.

## Writer decisions

`Discovery.keep_both/4` records an explicit decision while leaving both candidates proposed. `Discovery.reject_all/5` rejects the supplied candidates through the existing acceptance store boundary and records the aggregate decision. Neither action changes canon.

Successful CLI acceptance records the selected candidate back into discovery only after the existing candidate acceptance succeeds. `Session.resume_view/2` then exposes current mode, selected candidate, pending question and one optional next action without re-running generation or analysis.

See `examples/phase_twelve/README.md` for the provider-free fragment → candidate → manual edit → acceptance CLI walk-through and `test/writer_workflows/phase_twelve_scene_exploration_test.exs` for deterministic generated treatment fixtures.
