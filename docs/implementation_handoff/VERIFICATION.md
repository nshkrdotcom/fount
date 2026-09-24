# Verification as of 2026-09-24

This is a partial implementation. `PACKAGING_VERIFICATION.json` applies only
to the supplied overlay, not to subsequent source changes in this checkout.

## Passed

| Check | Result |
| --- | --- |
| `mix deps.get` in all three Fount packages | Passed. Probe and Workshop resolve Inference 0.4.1 and Agent Session Manager 0.16.0 from Hex. |
| `mix format --check-formatted` in all three packages | Passed after formatting the Probe live script. |
| `MIX_ENV=test mix compile --warnings-as-errors` without provider and database variables | Passed in all three packages. |
| Offline `MIX_ENV=test mix test` without provider and database variables | Core 56 passed; Probe 9 passed; Workshop 14 passed. |
| Core PostgreSQL integration | Four tests passed against the new `fount_blitz_dev2` database, including immutable history, candidate acceptance, exact Fountain import and report evidence. |
| Workshop PostgreSQL and PDF integration | Two develop/database tests and three renderer tests passed. |
| Core real examples | `roundtrip` and `database` modes passed. |
| Probe live `knowledge` mode | Passed through `/home/home/scripts/with_bash_secrets`; three real System One evaluations were saved in `.blitz/live-probe-secrets/knowledge.json`. No credential value was written to the report. |
| Workshop live `develop` mode | Passed without acceptance. Two real Codex candidate scripts and actual PDFs were saved in `.blitz/live-workshop-retry/`; the accepted revision stayed at the empty root. One PDF was visually inspected and shows conventional script layout with embedded Courier Prime. |
| Workshop live `develop --accept-demo` mode | Passed in a fresh project. Two distinct candidate scripts and six-page PDFs were saved in `.blitz/live-workshop-accept-retry/`. A direct PostgreSQL query confirmed the accepted head equals the chosen candidate revision. One page was visually inspected. |
| Workshop live `rewrite` mode | Passed through Inference/Codex. An exact dialogue element changed from “We bill by the berth, not by altitude.” to “We bill for the berth. Floating's optional.” The candidate was reopened from PostgreSQL, Fountain and a six-page PDF were exported, and the accepted head stayed unchanged. Output: `.blitz/live-workshop-rewrite-retry/`. |
| Sequence rebuilding in PostgreSQL | One integration test passed: selected scenes were replaced, surviving IDs were retained, the candidate reopened and the accepted head remained unchanged. |
| Workshop live `sequence` mode | Passed through Inference/Codex. Five selected scenes became three, the exact service-gate key line survived, the candidate reopened, and the accepted head stayed at the base. Baseline and candidate PDFs were both six pages under the same settings, so measured page savings were **zero**. The candidate page was visually inspected. Output: `.blitz/live-workshop-sequence/`. |

The development database was newly created in an isolated local PostgreSQL
cluster on port 55432. Existing databases were not dropped or reset.

## Failed and corrected

- The first live Codex run timed out on its second completion. The completed
  first candidate is now saved with a partial session, and the completion
  stream timeout is set through the published Agent Session Manager option.
- A later explicit acceptance demonstration produced an orphan dialogue line
  in Codex's second candidate. Fount rejected that candidate, preserved the
  first, and left the accepted head untouched. Dialogue cue coherence is now
  checked by the local completion validator, allowing its single repair
  attempt before materialization. A new live acceptance run then passed.
- Repeated candidate acceptance returned a database row. It now returns
  `{:error, :already_accepted}`; the PostgreSQL integration test passes.
- The first targeted rewrite DB test failed because `targeted_rewrite` was not
  one of the schema's workflow categories. The session now uses `pass` with
  `kind: targeted_rewrite` in its request. The test and live retry pass.

## Still required

The full F01–F09, W01–W09 and T01–T13 acceptance cases are not complete.
The legacy filesystem/SQLite stores remain in source and must be removed when
their callers are migrated. Most Probe tools and creative workflows, complete
CLI coverage, table-read/speech output, final overlay generation and the
follow-on handoff are outstanding. No release-complete claim is made here.
