# Final integration and acceptance

Phase 16 closes the implementation program by verifying the product that already exists rather than adding a second writing system.

The repository now has five libraries: canonical screenplay work in `fount`, neutral measurements in `fount_observe`, evidence-grounded interpretation in `fount_intelligence`, writer-controlled generation/revision in `fount_workshop`, and durable orchestration state in `fount_run`. Canon still advances only through the existing explicit review/acceptance path.

## What the final audit covers

The final acceptance ladder checks the five-library dependency graph, Core/Shell purity, the System One and Inference ownership boundaries, absence of Probe/old package residue, safe declarative assets, cache/provenance identity, non-linear temporal and forward-reader regressions, package/Hex allowlists, documentation, and the existing W01–W12/A01–A12 writer demonstrations.

Run the source-only checks without provider or database credentials:

```bash
bash scripts/final_acceptance.sh --static
```

The runtime-QC environment runs the full ladder:

```bash
bash scripts/final_acceptance.sh --runtime
```

That command does not silently invent missing gates. PostgreSQL integrations run only when `FOUNT_DATABASE_URL` is configured. Authorized live Observe/Workshop checks and any human/domain study remain separate evidence and must be reported as run or not run.

## Writer-facing proof

The final audit reuses the actual demonstrations from Phases 12–15 instead of replacing them with a synthetic “final demo” that bypasses the product:

- A01–A03: discovery and genuinely different scene treatments;
- A04–A05: voice protection and noncanonical rehearsal;
- A06–A08: conflicting notes, reveal consequences, and research/factual-status handling;
- A09–A12: human table-read evidence, stale/resumed decisions, clean sharing, and honest usefulness records.

The corresponding tests exercise the same candidate, review, screenplay, Store/Session, Intelligence/Observe, Fountain/FDX, and acceptance surfaces used by ordinary workflows. Phase 16 adds audit/traceability around those paths; it does not create a privileged acceptance shortcut.

## Claims deliberately not made

Green engineering checks do not establish that Fount is creatively superior, that a model understands an audience, that generated speech measures performance, that a screenplay is marketable, or that a submission venue will accept a script. Optional human studies remain separate from automated engineering evidence, and skipped studies remain visible validation debt.