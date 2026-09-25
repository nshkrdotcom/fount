# Verification as of 2026-09-24

This is a partial implementation. `PACKAGING_VERIFICATION.json` applies only
to the supplied overlay, not to subsequent source changes in this checkout.

## Passed

| Check | Result |
| --- | --- |
| `mix deps.get` in all three Fount packages | Passed. Probe and Workshop resolve Inference 0.4.1 and Agent Session Manager 0.16.0 from Hex. |
| `mix format --check-formatted` in all three packages | Passed after formatting the Probe live script. |
| `MIX_ENV=test mix compile --warnings-as-errors` without provider and database variables | Passed in all three packages. |
| Offline `MIX_ENV=test mix test` without provider and database variables | Core 56 passed; Probe 9 passed; Workshop 23 passed. |
| Core PostgreSQL integration | Four tests passed against the new `fount_blitz_dev2` database, including immutable history, candidate acceptance, exact Fountain import and report evidence. |
| Workshop PostgreSQL and PDF integration | Ten tests passed together across develop, note, pass, recover, sequence, targeted rewrite and PDF renderer files. |
| Core real examples | `roundtrip` and `database` modes passed. |
| Probe live `knowledge` mode | Passed through `/home/home/scripts/with_bash_secrets`; three real System One evaluations were saved in `.blitz/live-probe-secrets/knowledge.json`. No credential value was written to the report. |
| Workshop live `develop` mode | Passed without acceptance. Two real Codex candidate scripts and actual PDFs were saved in `.blitz/live-workshop-retry/`; the accepted revision stayed at the empty root. One PDF was visually inspected and shows conventional script layout with embedded Courier Prime. |
| Workshop live `develop --accept-demo` mode | Passed in a fresh project. Two distinct candidate scripts and six-page PDFs were saved in `.blitz/live-workshop-accept-retry/`. A direct PostgreSQL query confirmed the accepted head equals the chosen candidate revision. One page was visually inspected. |
| Workshop live `rewrite` mode | Passed through Inference/Codex. An exact dialogue element changed from “We bill by the berth, not by altitude.” to “We bill for the berth. Floating's optional.” The candidate was reopened from PostgreSQL, Fountain and a six-page PDF were exported, and the accepted head stayed unchanged. Output: `.blitz/live-workshop-rewrite-retry/`. |
| Sequence rebuilding in PostgreSQL | One integration test passed: selected scenes were replaced, surviving IDs were retained, the candidate reopened and the accepted head remained unchanged. |
| Workshop live `sequence` mode | Passed through Inference/Codex. Five selected scenes became three, the exact service-gate key line survived, the candidate reopened, and the accepted head stayed at the base. Baseline and candidate PDFs were both six pages under the same settings, so measured page savings were **zero**. The candidate page was visually inspected. Output: `.blitz/live-workshop-sequence/`. |
| Workshop live `notes` mode | Passed through Inference/Codex with a PostgreSQL-backed candidate and six-page PDF. The first run introduced a wrong accountant pronoun; after adding nearby scene context, the second run preserved “her,” made Dan's response cost him control of the original ledger, removed only the addressed note, and left the accepted head unchanged. Output: `.blitz/live-workshop-notes-context/`. |
| Workshop live `pass` mode | Passed with the `dialogue_subtext` profile through Inference/Codex. The selected exchange became more responsive on the page, the candidate reopened from PostgreSQL, a six-page PDF rendered, and the accepted head stayed unchanged. Output: `.blitz/live-workshop-pass/`. |
| Workshop live `character` mode | Passed through Inference/Codex. Dan's dialogue and Mara's immediate replies changed across three scenes, including the key handoff and ledger confession. The candidate reopened from PostgreSQL, a six-page PDF rendered, and the accepted head stayed unchanged. Output: `.blitz/live-workshop-character/`. |
| Workshop live `table_read` mode | Passed with the real original fixture: 29 ordered speaking turns were exported to JSON and HTML, alongside a six-page screenplay PDF. Output: `.blitz/live-workshop-table-read/`. |
| Workshop live `recover` mode | Passed with real revision history. A key-setup action beat was cut from the accepted draft, then restored into a separate saved candidate at its former position with its original element ID. The accepted cut draft stayed unchanged and the candidate PDF rendered. Output: `.blitz/live-workshop-recover/`. |

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
- A live note response called the accountant “him” although later scenes use
  “her.” Nearby scene context was added to targeted rewrites; the second live
  response uses “her.” This shows why a complete continuity check is still
  required for arbitrary generated edits.

## Still required

The full F01–F09, W01–W09 and T01–T13 acceptance cases are not complete.
The legacy filesystem/SQLite store code and dependency have been removed.
Most Probe tools and creative workflows, complete CLI coverage, speech
verification, final overlay generation and the
follow-on handoff are outstanding. No release-complete claim is made here.

`FountWorkshop.Speech.Espeak` and the live `speech` mode have not been executed:
neither `espeak-ng` nor `espeak` is installed in this environment. Requesting
speech mode fails explicitly until a real executable is configured.
