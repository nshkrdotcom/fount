# Verification provenance

For the later local QA execution, see [LOCAL_QA_2026-09-24.md](LOCAL_QA_2026-09-24.md). For subsequent feature implementation and its checks, see [STAGE2_STATUS_2026-09-24.md](STAGE2_STATUS_2026-09-24.md). The historical source-only and earlier-run records below remain separate.

## This continuation pass: application execution NOT RUN

No application/runtime check was executed. This includes:

| Check | Status in this pass |
| --- | --- |
| `mix deps.get` or dependency resolution | **not run** |
| `mix format` / `mix format --check-formatted` | **not run** |
| Elixir/Mix compilation, including warnings as errors | **not run** |
| All existing and new ExUnit tests | **not run** |
| PostgreSQL create/migrate/query/integration/concurrency | **not run** |
| Codex/Inference/Agent Session Manager completions | **not run** |
| Jev/System One requests | **not run** |
| Afterwriting/Poppler PDF generation or visual inspection | **not run** |
| eSpeak/audio generation or playback | **not run** |
| Credo, Dialyzer, ExDoc, Hex build, CI | **not run** |

Source was inspected and authored using the provided APIs. Artifact inventory, byte hashes, JSON decoding and ZIP membership can be checked with Python without running the application. The separate delivered `fount-delivery-report.json` records exactly which packaging checks actually ran. A packaging pass does not establish Elixir syntax, SQL correctness, accepted workflow completion or screenplay quality. Review was a self-review; no independent reviewer/subagent ran.

## Previously recorded local results (2026-09-24, BEFORE this overlay)

The continuation input reports the following earlier local runs. These were not reproduced here and must not be relabeled as newly passed:

| Package | Earlier recorded evidence |
| --- | --- |
| Core | 56 offline tests; four PostgreSQL integration tests; real roundtrip/database modes |
| Probe | Nine offline tests; old knowledge mode with three real System One evaluations |
| Workshop | 23 offline tests; ten PostgreSQL/PDF integration tests; real Codex modes for develop, rewrite, sequence, notes, pass, character, recover and table read |

The earlier checkout reportedly resolved Hex Inference 0.4.1 and Hex Agent Session Manager 0.16.0. Its earlier sequence attempt rendered six pages before and six after: **zero page savings**. One generated note response had a wrong pronoun; additional nearby context corrected one retry, not the general continuity problem. Speech was not run because no eSpeak executable was installed. The old overlay manifest and packaging report do not certify this source.

## Exact next commands

Inspect/apply using SETUP first. Then for each of `packages/fount`, `packages/fount_probe`, `packages/fount_workshop` execute and record separately:

```bash
env -u SYSTEM_ONE_API_KEY -u FOUNT_DATABASE_URL -u FOUNT_CODEX_MODEL mix deps.get
env -u SYSTEM_ONE_API_KEY -u FOUNT_DATABASE_URL -u FOUNT_CODEX_MODEL mix format --check-formatted
env -u SYSTEM_ONE_API_KEY -u FOUNT_DATABASE_URL -u FOUNT_CODEX_MODEL MIX_ENV=test mix compile --warnings-as-errors
env -u SYSTEM_ONE_API_KEY -u FOUNT_DATABASE_URL -u FOUNT_CODEX_MODEL MIX_ENV=test mix test
```

The authored `scripts/verify_handoff.sh --offline` collects these commands and results; it was not itself run against the application here. A missing formatter/dependency or warning must be fixed rather than skipped. After corrections, rerun the full package tests and optionally Credo/Dialyzer/docs using the package's actual available aliases/dependencies.

With the explicitly configured fresh `FOUNT_DATABASE_URL`, migrate as in SETUP and then:

```bash
(cd ~/p/g/n/fount/packages/fount && MIX_ENV=test mix test integration)
(cd ~/p/g/n/fount/packages/fount_workshop && MIX_ENV=test mix test integration)
```

Install/confirm the PDF prerequisites before Workshop integration. These integrations may deliberately inject offline completion responses while exercising actual PostgreSQL/PDF; they are not live Codex proof. Add the missing acceptance tests identified in FEATURES and KNOWN_GAPS, especially the full W03/W04/W05 and selective acceptance cases.

Real examples use exactly this invocation form, once from the owning package for every applicable mode:

```bash
MIX_ENV=dev mix run examples/live.exs -- --mode MODE --out /tmp/fount-live/MODE
```

Replace `MODE` with the literal mode from OPERATIONS, not a guessed alias. Run each new writer mode with authorized configuration. Read generated candidate pages and actual PDFs. Compare only measured PDF counts under identical settings and title-page treatment. Record the generated revision/session/candidate/report IDs and artifact hashes without secrets. Run speech only when installed and configured; otherwise mark it not run.

## Acceptance evidence to collect

For every F/W/T case, distinguish source implemented, test passed/failed, real example passed/failed/partial, not run, and remaining implementation. Require correct fixture outcomes, not merely successful process exits. In particular, preserve both bridge neighbor identities, demonstrate selection and third-candidate joins, prove repairs around the reveal movement, render both distinct sequence routes, inspect character partner responses and secrets, accept only selected note groups, compare exact/adapted recovery, and show three evidence-based strategies with two written remedies.

Retain original failures and repaired reruns as separate records. Do not overwrite this source-only provenance with claims that this agent ran the local checks.
