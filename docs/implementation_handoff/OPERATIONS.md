# Operational contract to finish locally

The complete required command surface is in
`spec_draft_implementation/09_workshop.md`. Its examples are **target release
commands**, not claims that this partial overlay already implements every task.

Complete ordinary import/inspect/export/history; Probe requests/search; writing
sessions/materialization/selection/combination/rebase/audition; explicit
accept/reject; rendering and table read. Strictly validate request files and
command options. No placeholder public command is acceptable.

A candidate must contain actual typed action/dialogue/scene edits and a complete
revision. Session/candidate/report saves never advance the accepted head.
Partial selection recompiles against the original base. Missing group
dependencies are returned as an explicit proposed selection, never selected
silently. Rebase creates a new session with exact source provenance.

Acceptance must validate the actual locked head, candidate base, structurally
valid content, candidate content hash and reviewed report IDs. The supplied
`ReviewGate` only performs the pure portion; it does not replace that transaction.
Required exact constraints cannot be overridden by a model or by a probability.
Semantic concerns/failed checks require recorded writer acknowledgment.

After completing the live entrypoints, run each from its package:

```bash
MIX_ENV=dev mix run examples/live.exs -- --mode all
```

Core `all` uses files and PostgreSQL. Probe modes are `knowledge`, `voice`,
`consequences`, `all`. Workshop modes are `develop`, `alternatives`, `propagate`,
`sequence`, `character`, `notes`, `pass`, `recover`, `investigate`, `all`, and
optional `speech`. Run one mode first with real configured services.

All modes must write truthful `run.json` records. Workshop modes save and reopen
actual candidates, write review packets and render at least one real PDF.
`develop` starts from an empty root; sequence compares two alternatives and the
baseline using identical renderer settings. `--accept-demo` is an explicit
writer action scoped to a newly created demonstration project. No flag means
the accepted head stays unchanged.
