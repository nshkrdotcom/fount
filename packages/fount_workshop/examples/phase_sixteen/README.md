# Phase 16 final acceptance walkthrough

This is an execution map, not a new writer workflow. The machine-readable `acceptance_matrix.json` records W01–W12/A01–A12 evidence ownership, proposed runtime commands, assertions, output classes, and the source-delivery `NOT_RUN` state without pretending tests ran. Runtime QC records actual evidence in the docset and may update the matrix status/revision fields when it intentionally commits that evidence.

From the repository root, the source-writing environment can run:

```bash
bash scripts/final_acceptance.sh --static
```

A runtime-QC checkout with Elixir/Mix runs:

```bash
bash scripts/final_acceptance.sh --runtime
```

Codex should also execute the focused writer demonstrations that carry the final acceptance cases:

```text
Phase 12: A01, A03, A10 discovery/session cases
Phase 13: A02, A04, A05 cinematic/voice/rehearsal cases
Phase 14: A06, A07, A08 notes/consequence/research cases
Phase 15: A09, A10, A11, A12 read/share/resume/usefulness cases
```

The Phase-15 provider-free capture → explore → revise → compare → accept/reject → export/read → resume path remains the final integrated writer path. Phase 16 verifies it together with the earlier scenarios; it does not add a hidden provider call or a second canonical editing path.

When PostgreSQL, PDF/TTS dependencies, or provider authorization are unavailable, record those gates as `NOT_RUN`. Do not translate deterministic fixtures into human-preference or creative-quality claims.
