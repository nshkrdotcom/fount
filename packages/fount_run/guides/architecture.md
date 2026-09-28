# Architecture

FountRun sits above Fount Core's canonical screenplay persistence. Core never imports Run. The Phase 02 package depends on Core only because it needs revision/candidate/session/report identity and canonical hashing; Workshop execution is deliberately not a dependency until Run actually orchestrates it in a later phase.

Run accepts a caller-supplied Repo. Its application starts an empty supervisor and performs no provider work. Authentication/project ownership remain host responsibilities represented by a trusted `FountRun.ActorContext`; request JSON cannot supply an actor type or owner.

The database is the durable timeline. Immutable plan/policy snapshots and events are protected from update/delete. Mutable projections (run/step/attempt/decision/usage/delivery) use constrained transitions. The Phase 02 lease helper only stores an already-decided active lease; claim/renew/reclaim semantics are Phase 03.
