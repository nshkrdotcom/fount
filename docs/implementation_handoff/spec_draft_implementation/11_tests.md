# Feature-focused verification

## Default policy in all three packages

`mix test` is offline. It must run with model credentials unset and with PostgreSQL, renderer, speech and Codex services unavailable. Default tests use real parsers, typed edits, validation, diffs and temporary files. Substitute external service/process/storage boundaries only. A real SDK Test client and Inference Mock adapter are appropriate; fixed outputs under `examples/` are not.

Do not start an Ecto Repo, migrate a database, fetch a model catalog or launch a renderer from `test_helper.exs`, application startup, aliases, default test modules or default setup hooks. Remove existing service-starting default aliases. Put real integration files outside the default `test/` path, for example `integration/`, and invoke them explicitly after configuring the service. Test-only store doubles prove application behavior; they do not prove PostgreSQL transactions.

Keep existing meaningful parser/format/edit regressions. Replace obsolete filesystem/SQLite store tests with the new feature tests; do not preserve removed APIs just to keep old assertions green. Avoid a test for every trivial struct field, generated accessor or profile sentence. Test the behavior a writer or agent depends on.

## Minimum behavior matrix

| Feature / risk | Default offline verification | Explicit integration / live evidence |
| --- | --- | --- |
| F01 source preservation | CRLF/Unicode/inline notes/boneyard/dual fixture imports and unchanged Fountain bytes export; edited spec output omits comments; supported FDX types survive with declared losses | Core example writes/reimports actual files |
| F02 typed edits | Move/split/merge retain selected IDs; invalid dangling block fails the whole batch; new local refs allocated once; unknown/foreign IDs rejected | Core example edits and reloads |
| F03 history/candidates | Workshop store double: candidate save does not call head-update; stale accept returns a conflict; partial groups recompute from base | PostgreSQL save/load/history/candidate/accept tests below |
| F04 metadata | Authored brief/fact/intent separated from reports; deleted targets make items unresolved; note resolution follows accepted groups | Reopen accepted and historical metadata |
| F05 retrieval | Source/excerpt equality; excluded historical/omitted text stays excluded; requested exhaustive scan reports coverage | Probe current/history search |
| F06 tools | Projection tests, result joining, meaningful reducers and unknown/error outcomes | Probe real Noul/Choice/Score and evidence |
| F07 review | Base hash/IDs and report references match; structural and source diffs name actual changes; generated provenance can't claim writer origin | Workshop reopen review packet then accept |
| F08 output | Renderer argument/spec-source construction through process double; table read maps confirmed cast and dual groups; process failure propagated | Real PDF inspection and optional actual WAV |
| W01 develop/bridge | Scripted strategies produce two different candidate structures; empty root works; adjacent IDs and exit constraints retained | Real generated pages from empty brief and inserted bridge |
| W02 alternatives/combine | Overlapping groups surface conflict; selected A/B passages pinned; generated join gets new ID; source attribution retained | Actual audition and combined candidate |
| W03 change/repair | Scripted delayed reveal changes accusation too; dependent group selection checked; baseline failure distinguished from new failure | Jev before/after plus actual repaired pages |
| W04 sequence/cut | Five scenes -> three with retained required setup; independent routes; page count absent when renderer fails | Same renderer baseline/alternatives and real page deltas |
| W05 character | Only confirmed character material selected; partner reply change disclosed; three scenes updated and outcomes checked | Character-wide pages and evidence |
| W06 notes | Local and sequence note addressed by different groups; partial acceptance resolves only selected solution; unrelated note retained | Real note-driven proposals and DB resolution |
| W07 passes | Selection/profile instructions drive typed dialogue, action and comedy edits; no requirement that a joke is funny | Separate real completions and pages |
| W08 recovery | Source/current/proposed comparison; verified historical ID restoration; foreign copy gets new ID; obsolete fact flagged | Actual earlier revision and adapted key setup |
| W09 investigation | Static tool allowlist; evidence round changes hypothesis; two remedies materialized; limits return partial | Real investigation, three strategies, two written remedies |

## Critical fixtures and assertions

1. **Perspective leak:** put an explicit secret in an author's note, hidden character-cue identity, a later scene and an unheard aside. Audience/character states exclude each inaccessible source; creative context can include them as labeled context. A character present in a room is not automatically entitled to its hidden action paragraph. Unknown access remains unknown.
2. **Reveal retraction:** supply probabilities `[0.1, 0.85, 0.35, 0.9]` at four legal prefixes. Preserve both crossings and reversal; never binary-search an assumed one-way curve. A removed clue's score change is comparative evidence, not proof of causation.
3. **Unordered stream:** results for indices 2, 0 and an error for 1 associate correctly; error stays in attempted count, and missing answer keys do not become zero.
4. **Negative intent:** positive proposition “Mara knows Dan forged it,” expected false. `p=0.9` fails; `p=0.1` passes. Unknown context produces insufficient evidence independently of numeric threshold.
5. **Blind voice:** no original cue/name/ID/scene clue reaches the state. Identical lines after normalization cannot enter both training and test sets. Missing and rejected items do not enter attribution denominators; fixed profiles used in before/after comparison.
6. **Combination:** A and B both replace the same element. Selection without precedence returns both passages as a conflict. Explicit selection plus a permitted connective rewrite preserves the winning exact text and reruns impacted checks.
7. **Partial notes:** accepting a local group does not resolve a note that also requires an unselected structural repair. A rejected candidate's proposed note removals never affect the accepted draft.
8. **Retry/resume:** after one successful stored candidate and one failed completion, resume targets the failed branch. It neither repeats successful provider calls nor accepts the existing candidate.

Use small, legible scripted responses at service boundaries. Test actual end-to-end pure candidate compilation and context creation, rather than asserting private functions were called in a particular order.

## Real PostgreSQL checks, explicitly invoked

Run in an explicitly selected disposable development/test database with the real migrations. Use Ecto SQL sandbox or per-test unique project keys. Never drop a user database from a test helper.

- Load the same typed model at head, old revision and proposed revision. Preserve cast links, order, authored items, source artifacts and generated provenance.
- Save/accept one candidate atomically. Inject a failure after revision preparation inside the transaction; neither head nor acceptance row partially advances.
- Race two acceptances from the same base. Exactly one wins; the other receives a stale-head conflict. Repeating the successful acceptance returns its existing result without a duplicate row.
- Try a reference into another screenplay/revision and verify composite FK rejection. Check heading/cue/dual deferred constraints with a valid normal insertion and an invalid final state.
- Store a comparison report referencing two revisions; reload and resolve both evidence scopes. History follows parents, excluding unaccepted alternatives from the accepted timeline.

These five scenarios cover real persistence risks. No need to fuzz every SQL field, build a generic transactional model checker or write a custom database correctness framework.

## Commands and gates

From each of the three package directories:

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Run default tests with service credentials removed by the command environment. The final handoff supplies exact commands for explicit `mix test integration/...` files and live examples. A command not executed is recorded as not run, with its reason. Warnings-as-errors applies to project compilation; if an upstream dependency emits an unrelated warning, report its source and avoid rewriting dependencies merely to silence it.

The final feature audit checks every F/W row against code, test and live entrypoint/mode. It must distinguish implemented, default-tested, integration-tested and live-demonstrated. Default mocks do not establish that a real model returns the desired artistic result. Live runs do not replace regression tests for edit/persistence behavior.
