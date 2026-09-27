# Observe architecture

`Question` declares neutral Noul/choice/score questions. `Request` separates canonical provenance/evidence from effective semantic input. `Lens` loads only installed declarative assets and hashes effective questions, context/output contracts and projection identity. `Registry` is the only executable sensor/projection lookup; data cannot name modules or functions.

`Executor` validates request IDs and limits, checks an optional L1 cache, acquires permitted misses through `ProviderCall`, associates responses by batch index, validates distributions, and constructs fresh revision-bound observations. Missing, duplicate and malformed associations are explicit failures. Cached result content and question/provider/input identities are checked before reuse.

`ProviderCall` owns its task supervisor and wall-time/cancellation boundary. `Providers.SystemOne` alone converts neutral questions to the supplied SDK's public constructors, prepares them and consumes `evaluate_stream/4`. Native responses/errors terminate there. `Sandbox` executes fixed JSON fixture data without a network dependency.

`Cache.Memory` implements L1 reuse in a caller-owned, size-limited process. Intelligence retains responsibility for higher-order interpretation and eventual L2 persistence/recomputation. Observe does not rank screenplay quality, diagnose a whole story, call Inference or accept edits.

Source projections preserve actual selected spans and audience/character access. Canonical selection, inventory, exact search and source-evidence validation belong to `fount`, not to this measurement package.

## Phase 2 boundaries

`MeasurementSpec` compiles validated data declarations, not executable assets.
`OutputContract` hashes and validates the represented output shape. `Request` owns
the one canonical semantic-input serializer. The provider adapter calls that same
serializer, and current targets/evidence remain on each new Observation.

`Cache.ETS` is private DB-free L1, not durable L2 storage. `Recording` provides
non-probabilistic human/deterministic/imported records outside probabilistic
playbooks. `SceneQuestion` presents measured values and supplied source evidence,
not StoryWorld, Reader or Diagnosis functionality from later phases. Native SDK
types still terminate only in `Providers.SystemOne`; Inference stays in Workshop.
