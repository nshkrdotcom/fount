# Fount creative writing implementation plan

**Goal:** Deliver nine usable screenplay writing workflows with real candidate pages, supported by precise screenplay tools, PostgreSQL history and professional output.

**Architecture:** Core owns deterministic screenplay values and persistence. Probe owns source-grounded inspection and model evaluation. Workshop composes those with Inference completions into strategies, candidates and explicit writer decisions.

**Tech stack:** Elixir 1.19+, Ecto/PostgreSQL, the supplied System One SDK and Inference, Codex completion runtime, existing Fountain/FDX code, afterwriting PDF integration.

**Spec:** Read [01](01_features_and_research.md), [01a](01a_creative_workflows.md) and the API contracts in 04–09 before executing this plan. Complete each step yourself or through the recipient's already authorized execution method. This handoff does not require a particular agent orchestration tool or an installed skill package.

## Global constraints

- All W01–W09 workflows are required. The agent toolbelt alone is incomplete.
- Modify Fount freely; do not modify the supplied SDK/Inference repositories to mask a missing feature.
- PostgreSQL is the only application store; source file import/export remains real.
- Default tests in all three packages are offline; examples and explicit integration checks use real services.
- Generated writing remains proposed until explicit acceptance. Reports never become authored facts automatically.
- Codex through Inference is the required completion route. The provider wishlist is separate.
- Exactly three live entrypoints, with modes, cover the functionality; no fake example responses.

## Review focus

The task checks below address: foreign/stale IDs entering a proposal; hidden/future text contaminating knowledge checks; partial selection dropping a required repair; misleading page-saving claims after rendering failure; and session resume repeating accepted or successful work. Each is a practical screenplay-editing failure, not a reason to build a general formal verification system.

## File ownership and removal map

Paths are relative to Fount. Names below are intended code locations; consolidate adjacent private helpers if they have no independent behavior. Keep public APIs as specified.

| Area | Modify existing files | Add files |
| --- | --- | --- |
| Core values/edits | `packages/fount/lib/fount/{screenplay,edit,query,index,validate,writer,revision}.ex`, `annotation/target.ex`, `edit/{op,change_set}.ex`, IR and cast structs | `lib/fount/{target,slice,change_impact,authored_item}.ex` under core package |
| Interchange | Core `fountain/{parser,inline,serializer}.ex`, `adapter/{json,fdx}.ex`, persistence codec | Core `lib/fount/canonical_json.ex` if shared encoding behavior warrants it |
| PostgreSQL | Core `persistence.ex`, `persistence/{schema,codec,query}.ex`, `repo.ex`, config and mix aliases | Core `priv/repo/migrations/20260924000000_create_writing_model.exs` |
| Probe | New package | `packages/fount_probe/mix.exs`, `.formatter.exs`, `lib/fount_probe.ex`, `lib/fount_probe/{tools,state,profile,executor,report,search,extraction}.ex`, tool modules and profiles |
| Writing | Workshop `proposal.ex`, `preview.ex`, `acceptance.ex`, root facade | Workshop `lib/fount_workshop/{brief,session,strategy,candidate,context,review,workflows}.ex`, `workflows/` functions/modules, `priv/prompts/`, `priv/writing_profiles/` |
| Output | Workshop `export/pdf.ex`, `table_read.ex`, `submission.ex` | Workshop `lib/fount_workshop/speech/espeak.ex`, public Mix tasks |
| Commands/examples | Package manifests, READMEs and config | Each package `lib/mix/tasks/`, `examples/live.exs`; fixture/support files |

Remove `packages/fount/lib/fount/store/filesystem.ex`, `store/sqlite.ex`, their store interface if unused, obsolete store tests and `exqlite` dependency. If `store/snapshot.ex` contains useful interchange codec logic, move that behavior into the canonical JSON adapter rather than retaining a second application store. Replace the four old migration files with the single fresh-schema migration and explain fresh-database setup. Update all callers, tests, scripts and docs that mention deleted APIs. Do not delete unrelated source files simply because they were absent from a proposed new layer.

## Task 1 — Exact editable screenplay values

**Consumes:** existing Document/CST/IR parser. **Produces:** typed Target, indexed Screenplay, slices, full edit batch and structural diff APIs in 05.

- [ ] Extend target/codec shapes and cast/query indexing; preserve original source bytes and introduce content/render hash semantics.
- [ ] Add focused tests to core `test/screenplay_test.exs`, `test/edit_test.exs`, and new `test/sequence_edit_test.exs`: import fixture, replace a line, split/merge a scene, retain chosen IDs, reject foreign targets and malformed dual groups.
- [ ] Run `mix test test/screenplay_test.exs test/edit_test.exs test/sequence_edit_test.exs` in core; new unsupported behavior must fail before implementing it.
- [ ] Implement the operation union in 05 and `contracts/operations.json`, local-ID compiler, authored items, slices and ChangeImpact. One candidate revision per successful batch; no-op does not create one.
- [ ] Run those tests plus existing parser/FDX/lossless tests. Review an actual before/after Fountain string for the sequence operations.

A focused new API assertion can use a fixture helper returning a real imported Screenplay plus dynamic bindings:

```elixir
{:ok, candidate, changes} = Fount.Screenplay.apply(base, [
  %{"kind" => "replace_text", "target" => %{"kind" => "element", "id" => line_id},
    "value" => "Hold the lamp. I need both your hands."}
])
assert candidate.revision.id != base.revision.id
assert Fount.Query.node(candidate, line_id).text == "Hold the lamp. I need both your hands."
assert Fount.Query.node(base, line_id).text != Fount.Query.node(candidate, line_id).text
assert changes.base_revision == base.revision.id
```

The helper imports the original fixture and resolves exact unique text; it does not fake the model. Add it as `test/support/screenplay_fixture.ex` and include test support in that package's test compile paths.

## Task 2 — Real revisions, sessions and candidates in PostgreSQL

**Consumes:** Task 1 canonical values. **Produces:** Persistence functions and fresh Ecto schema from 04.

- [ ] Translate `contracts/schema.sql` into the fresh migration and Ecto schemas, with one revision loader for current/history/candidate state.
- [ ] Add offline codec/value validation to core `test/persistence_codec_test.exs`. Move live DB cases to `integration/persistence_test.exs`; default startup must no longer start a Repo.
- [ ] Implement create/load/history/save_session/save_candidate/save_report/save_edit/accept_candidate/reject_candidate with exact parent/head rules and transactional acceptance.
- [ ] Implement a small Workshop store boundary and in-memory test double with the same outcomes. It is for offline orchestration tests, not a new user-selectable backend.
- [ ] Run core default tests. In a fresh explicit test database run `mix test integration/persistence_test.exs`, covering the five integration scenarios in 11. Record unavailable database checks honestly.
- [ ] Remove old application stores/migrations/dependencies and update setup docs in the same change.

## Task 3 — One complete creative slice: develop and audition

**Consumes:** canonical edits, sessions/candidates and supplied Inference. **Produces:** W01 and the basic W02 path with real saved candidate pages.

- [ ] Add Inference dependencies and client construction at launcher boundaries as in 08. Create empty root + brief, Context packet, Strategy/Proposal decoding and `Session.start/4`.
- [ ] Add Workshop `test/develop_test.exs` with two scripted Inference strategy/proposal responses. Assert two different candidate structures, one unchanged accepted base, real source exports and retained neighboring IDs for a bridge.
- [ ] Implement generation via Inference completions, candidate compilation/storage and `Review.export/4`. Add strategy materialization, simple audition and rejection.
- [ ] Run `mix test test/develop_test.exs test/canonical_workflow_test.exs` in Workshop. Update the existing workflow test to the new explicit candidate semantics.
- [ ] Add `mix fount.write`, `fount.materialize`, `fount.session`, `fount.audition` and the develop/alternatives modes of the one Workshop live script. Run a real develop mode when credentials are available; save real generated pages.

This step exposes the creative product early. Continue adding required checks in subsequent tasks; it is not a release completion point.

## Task 4 — Evidence, Jev execution and writer constraints

**Consumes:** slices/context plus System One SDK. **Produces:** Probe package, T01–T05, T10 foundations, profiles/report envelope and candidate checks.

- [ ] Create Probe Mix project with dependencies/config in 08; implement state/evidence validators and the audience/character/blind projections in 06.
- [ ] Add Probe `test/state_test.exs`, `test/executor_test.exs`, `test/constraints_test.exs`, `test/knowledge_test.exs`, `test/voice_test.exs` for hidden/future leaks, unordered responses, negative intent, reveal retraction and speaker leakage.
- [ ] Implement prepared-question grouping, actual SDK stream indexing, report coverage, constraints, exact prefix trace and voice distribution aggregation. Add inventory/extraction/search with explicit inspected scope.
- [ ] Run Probe tests using SDK Test clients and Inference Mock. Verify missing items remain errors/unknown rather than zero scores.
- [ ] Wire candidate checking into W01/W02 and add the Probe live script with real Jev and Inference modes. Generated pages remain usable even when a semantic check is uncertain, with explicit review status.

## Task 5 — Story changes, dependencies and sequence rebuilding

**Consumes:** Probe reports, typed multi-scene edits, current/historical models. **Produces:** W03/W04 and T06/T07/T08/T12.

- [ ] Implement candidate event/prop/state extraction, pairwise support testing, dependency traversal with visited sets, chronology-aware continuity and exact before/after comparison.
- [ ] Add Probe `test/dependencies_test.exs`, `test/continuity_test.exs`, `test/compare_test.exs`; test missing evidence, alternate support, cyclic links, preexisting failures and separate clue ablations.
- [ ] Add Workshop `test/propagate_test.exs`, `test/sequence_test.exs`: delayed confession changes the earlier accusation; required key setup survives; five scenes become three; two strategies yield distinct actual edits.
- [ ] Implement consequence maps, repair groups, protected requirements and requested repair round. Sequence routes use `replace_sequence`, preserve retained IDs and call actual renderer for page targets.
- [ ] Run affected tests and real propagate/sequence modes when services are available. A renderer failure must leave page count unavailable and the session partial where page measurement was requested.

## Task 6 — Creative character/pass/note workflows

**Consumes:** context, cast, semantic checks and sequence repair. **Produces:** W05/W06/W07 and T09/T11.

- [ ] Implement responsive-dialogue/exposition/action opportunity tools and character workspace selection. Keep references distinct from appearances and speaking links.
- [ ] Add Workshop `test/character_test.exs`, `test/notes_test.exs`, `test/passes_test.exs`; verify multi-scene changes, partner replies, partial note resolution, visual replacement and genuine typed action/dialogue proposals.
- [ ] Implement the six writing profiles and character progression/agency direction; do not turn every pass into word substitution.
- [ ] Implement note origin/solution/group links and resolve notes only through selected accepted edits. Preserve conflicting and unrelated notes.
- [ ] Run the affected tests, then live character/notes/pass modes. Review candidate pages and any retained check concerns.

## Task 7 — Combine, recover, rebase and resume

**Consumes:** complete candidates/group dependencies and historical values. **Produces:** full W02/W08, safe selective acceptance and durable continuation.

- [ ] Add Workshop `test/combine_test.exs`, `test/recover_test.exs`, `test/session_resume_test.exs` and update `test/revision_test.exs` for overlap conflicts, pinned A/B passages, historical identity recovery, stale bases and failed-branch resume.
- [ ] Implement group closure, selective recompilation, range combination and requested connective generation. Three-way rebase handles deterministic disjoint edits and exposes real conflicts.
- [ ] Implement exact restore/adapt with source/current/proposed comparison and copied-from lineage. Store operations/reference maps so reopen preserves UUIDs.
- [ ] Implement atomic review/accept/reject CLI and history export. Verify a candidate cannot be accepted with report hashes from another candidate.
- [ ] Run affected tests and explicit PostgreSQL acceptance checks. Demonstrate alternatives/recover with real pages and persistence.

## Task 8 — Investigation that writes remedies

**Consumes:** all Probe tool families and candidate generation. **Produces:** W09 and T13, agent-facing tool catalog.

- [ ] Add Probe `test/planning_test.exs` and Workshop `test/investigate_test.exs`: structured known tool selection, evidence-driven hypothesis revision, three strategies and two materialized remedies.
- [ ] Implement application-owned completion/tool rounds, one follow-up by default, strategy contrast and call/state limits with partial/resumable output.
- [ ] Expose catalog schemas via `FountProbe.tools/0` and `mix fount.probe`; all listed tools must have real dispatch functions and validated parameters.
- [ ] Run tests and the live investigate mode. Check the result leads to actual screenplay alternatives and cites only inspected evidence.

## Task 9 — Professional outputs and complete live coverage

**Consumes:** complete screenplay/candidate workflows. **Produces:** reliable F01/F08 and all three complete example entrypoints.

- [ ] Update Workshop `test/pdf_export_test.exs` to use a process double; move actual rendering to `integration/pdf_test.exs`. Add tests for failed rendering, source omission and real count availability rules.
- [ ] Implement runtime renderer configuration, title/spec profiles, table-read JSON/HTML and optional espeak WAV. Update existing table-read/submission tests without hardcoding disputed craft rules.
- [ ] Finish all CLI commands in 09 and the exact three example entrypoints in 10, including all workflow modes and `--accept-demo` behavior.
- [ ] Run real core I/O/PostgreSQL, Probe models, Workshop PDF/models/DB, and optional speech when installed. Inspect real PDF layout and collect truthful run manifests.
- [ ] Verify FDX/JSON/Fountain fidelity and preservation of notes/omissions/dual dialogue across supported paths. Record actual format losses.

## Task 10 — Final verification, overlay and local handoff

- [ ] In each package run `mix format --check-formatted`, `mix compile --warnings-as-errors`, and `mix test` with live services unavailable. Resolve failures in the owning feature; do not broaden into unrelated framework work.
- [ ] Complete the F/W feature map with actual modules, tests and live mode status. Search code/docs for stale removed stores, obsolete target fields and placeholder public functions.
- [ ] Write the follow-on docset and `CONTINUE_PROMPT.md` exactly as required by 14, including the three local repository paths and actual known limitations.
- [ ] Build the full-file ZIP overlay and deletion manifest. Dry-run its application against the reconstructed baseline; compare extracted hashes and changed-file inventory.
- [ ] Deliver the ZIP, manifest, handoff and concise verification report. Do not represent unexecuted service checks as passing.

## Required outcome

Each task serves a specified writer operation or prerequisite. The final release is the full feature set, not the first milestone. No new distributed services, generalized workflow framework or universal scoring system is part of this plan. Interface corrections discovered in the actual XML may be made with an explicit note, while retaining the promised writing behavior.
