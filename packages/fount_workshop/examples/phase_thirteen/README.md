# Phase 13 cinematic revision fixture

This directory documents the deterministic Phase-13 writer demonstration. The source-writing handoff does not claim that it was executed here.

The corresponding ExUnit files are:

- `test/writer_workflows/phase_thirteen_pass_profiles_test.exs` — W04 shipped cinematic pass surfaces;
- `test/writer_workflows/phase_thirteen_voice_test.exs` — A04 exact protected voice/Unicode/code-switching behavior;
- `test/writer_workflows/phase_thirteen_rehearsal_test.exs` — A05 noncanonical rehearsal/adoption boundary;
- `test/writer_workflows/phase_thirteen_comparison_test.exs` — A02 two actual quiet revisions plus a rejected generic control.

## A02 demonstration shape

The original scene keeps the supplied dramatic fact and ambiguity: Mara places Dan's key beside a cooling cup, waits, and leaves without speaking. A protected `DAN (V.O.)` repeats `Not today. Not today.`

The two candidate pages make different cinematic moves without adding explanatory Mara dialogue:

1. visual: steam thins while she waits;
2. sound/space: the refrigerator clicks off and the room falls quiet.

`FountWorkshop.Comparison.compare/2` must show those as actual action changes, with zero language delta and a passing protected-text check. A deliberately fluent control replaces the repeated line with an explicit forgiveness speech; comparison exposes the actual language change and the fixture rejects that candidate. The rejection is a deterministic scenario record, not evidence that a human study ran.

## A04 demonstration shape

The protected line combines repetition and multilingual Unicode. `Request.validate/2` converts it into a required `pin_text` constraint. A candidate that changes only action passes; a candidate that normalizes the protected line fails the deterministic constraint. Voice context also preserves writer-selected source exemplars and explicitly requires writer/human review for language/cultural authenticity.

## A05 demonstration shape

A rehearsal records `Dan once stole a boat` under session progress with `canonical: false`. Before adoption, `Rehearsal.generation_context/1` returns no material and the screenplay is unchanged. Explicit adoption creates a traceable project-room record that can inform later generation while remaining labelled noncanonical. Rejected rehearsal inventions remain excluded.

## Runtime QC

Codex should run the focused Phase-13 ExUnit tests, the complete workspace regression ladder, PostgreSQL durability checks where relevant, and the source-contract tests. Optional human comparison is separate and nonblocking under D046. Stop before Phase 14.
