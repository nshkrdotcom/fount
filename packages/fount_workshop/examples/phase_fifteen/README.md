# Phase 15 — read, share, resume, and usefulness

This example maps the Phase-15 acceptance cases onto the public Workshop APIs and existing CLI.

- **A09:** `FountWorkshop.TableRead.packet/3` works without TTS; `record_reaction/2` links a human reaction to the exact screenplay revision and refuses a TTS observer.
- **A10:** existing `Acceptance` and `Session.resume_view/2` keep stale-branch protection, idempotent acceptance, rejected/proposed sibling state, and the accepted head across resume.
- **A11:** `FountWorkshop.Share.export/4` writes clean Fountain/FDX from accepted canon while excluding private notes/boneyards/development structure/session metadata and surfacing FDX losses.
- **A12:** `FountWorkshop.Usefulness` records helpful, kept-original, and generic/unhelpful outcomes separately and never emits a screenplay score or automatic winner.

The deterministic implementation is covered by `test/writer_workflows/phase_fifteen_read_share_resume_test.exs` and `phase_fifteen_usefulness_test.exs`.

For the coherent provider-free capture → explore → revise → compare → accept/reject → export → resume command sequence, see `guides/read-share-resume-and-usefulness.md`.

The optional D046 comparative human study is not executed by this source delivery. No live-provider, PostgreSQL, TTS, PDF, or human-study result is claimed here.
