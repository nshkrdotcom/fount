# Architecture

FountRun sits above Core and Workshop. Core never imports Run. Run uses Workshop for investigation, writing, checking, rebase, review packets and exports; canonical acceptance remains a Core transaction.

The host supplies one shared Repo and trusted `FountRun.ActorContext`. Request/CLI JSON cannot choose its own actor, owner, Repo module, provider client or artifact root. `FountRun.Engine.step/4` performs a short claim transaction, releases database locks, then executes a closed stage handler. External model or reviewer calls never run while the Run row lock is held.

## Closed pipeline

The default registry is `intake → investigate → plan → write → check → iterate → decide → deliver`. A passing Phase 05 check schedules `decide`; strategy gating still happens before any pages are generated. `decide` either completes a candidate, opens exact human approval/rebase decisions, or drives a registered automated approver. Delivery remains a separate durable action because its destination and filesystem policy are trusted host configuration rather than screenplay decision data.

## Claims, controls and fencing

PostgreSQL `now()` is the lease clock. Claims bind plan version, policy version and fencing token. Pause prevents new dispatch but lets an already-owned worker checkpoint safely. Stop fences running work, cancels queued work, supersedes pending decisions and approval attempts, increments fencing, and never deletes saved candidates/results. A delayed callback therefore cannot accept after stop.

Same-base/same-scope plan changes append a complete snapshot with expected-version plus command-id replay identity. Base/scope changes create a linked successor run. Policy updates are also complete snapshots. Both fence work bound to the prior version even when screenplay pages are unchanged. Resource/iteration accounting walks the parent-run chain so a successor cannot reset consumed limits.

## Decisions and approval

All writer decisions use the persisted decision row and canonical `submit_decision/4` transition. The context fingerprint covers prompt/options/candidate/base/check binding and authorized principal; response submission additionally binds plan/policy versions. Replays require the same respondent and exact response fingerprint.

`approve_run/4` and CLI `approve` verify the supplied decision belongs to the supplied run, build the exact `approve` response, then delegate. They do not implement a second acceptance path.

Approval-attempt durability is ordered:

1. persist exact candidate/plan/policy/packet/principal/fence identity;
2. record callback intent before an external automated reviewer call;
3. persist the exact safe review/recommendation;
4. construct and persist one stable Core approval id/payload;
5. recheck current run authorization, plan/policy/fence and stop/pause state;
6. call `Fount.Persistence.accept_candidate/3` under the required run → screenplay → candidate lock order;
7. commit the Core acceptance and Run accepted-attempt outcome together.

A saved review resumes without another reviewer callback. A saved approval payload reuses its id. `unknown` reviewer outcomes require a reconciliation callback or remain paused/partial; the original reviewer is never blindly re-called. Acceptance acknowledgement loss replays to the existing Core acceptance.

## Rebase and replacement

If canonical head differs from the reviewed candidate base, `decide` opens a rebase checkpoint. `FountWorkshop.Rebase` produces a new candidate on current canon and a linked successor run, then schedules a fresh check. Existing approvals remain bound to the old candidate/base and fail closed.

Human replacement text is parsed into a new Core candidate and also returns to a fresh check. Reviewed candidate bytes are never invisibly modified.

## Delivery boundary

Exports are rooted under trusted `artifact_root`. Each format has a durable identity, result checksum and relative output location. Standard serializers are Core/Workshop serializers, not alternate Run renderers. The bundle manifest is written last and records candidate-vs-accepted identity, plan/policy fingerprints, content/check identity, and per-format success/failure.

Phase 06 may present these APIs in a web UI, but does not change their authorization, persistence or acceptance semantics.
