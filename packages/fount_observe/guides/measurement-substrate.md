# Inspect one scene question without surrendering the draft

`Fount.Observe.SceneQuestion.ask/5` returns measured answers, exact passages supplied
for those answers, current revision identity, and resource accounting. It never
writes candidate pages or accepts an edit. The measurement may be uncertain; an
unavailable provider produces an unavailable result, not a negative verdict.

```elixir
alias Fount.Observe.{Question, SceneQuestion}
model = Fount.parse!("INT. HALL - NIGHT\n\nMara pockets a key.\n")
  |> Fount.Screenplay.from_document()
target = %{"kind" => "scene", "id" => hd(model.ir.scenes).id}
questions = [visible: Question.noul("Does the action describe something observable?")]
provider = Fount.Observe.Sandbox.new!(%{"scene_question" => %{"visible" => 0.9}})
{:ok, packet} = SceneQuestion.ask(provider, model, target, questions)
```

This is a synthetic fixture result, explicitly marked `simulation: true`. It tests
the workflow, not the quality of the model or screenplay. Evidence lists contain
verified source input, not a claim that the provider has proved its reasoning.

Run `mix run examples/phase_two.exs` for noul, ordered choice, and rubric answers,
an unavailable-provider case, private-note exclusion, and an unchanged-source
assertion. `examples/live.exs` is a separate opt-in live path.

## One model input, one content identity

`Projection.at/4` remains the inspection API, including its source envelope.
`Projection.request/5` builds a `Request` with the envelope separated from model
input. A normal call to `evaluate/4` infers the common projection for its inline
lens; an explicitly selected lens must match each request's projection.

`Request.semantic_input/1` is the exact canonical JSON string both hashed and sent
to SystemOneSDK. It contains `state` and typed semantic `context`, not target IDs,
revision IDs, run IDs, or evidence pointers. Explicit-state callers still control
all of their state JSON; Observe does not heuristically erase authored fields.

`Request.dependencies/1` and each Observation retain current source targets,
evidence hashes, and revision identities. Context Fact evidence pointers must
resolve to the request's supplied evidence. The same semantic measurement can be
reused after a revision, but each Observation gets freshly bound evidence,
dependencies, lens provenance and run identity.

## Typed context and output shape

`Context.validate_contract/1` accepts closed required/optional slot declarations,
with installed neutral primitive types or explicitly declared JSON literals.
Unknown types, nested executable fields and open slots fail. `Context.from_map/2`
roundtrips the storage representation without atom creation or module lookup from
input strings. `Context.semantic_map/1` excludes Fact evidence IDs; `to_map/1`
retains them for storage. Identical complete context envelopes are shape-validated
once within an acquisition run; each request's source binding is checked separately.

`OutputContract.for_question/1` returns a logical ID, a canonical data shape and its
SHA-256 digest. The digest describes the serialized answer, required fields,
variants, domains and ordering; it is not a hash of code, formatting or docstrings.
Changed question wording changes the measurement specification but not an
unchanged answer shape. Stale cached shapes or changed raw values cause a miss and
reacquisition. No historical output readers or shape adapters are supplied.

## Calibration does not erase the original answer

`MeasurementResult.value`, `distribution`, and `normalized_raw` retain the raw
normalized provider result, including ordered probabilities and provider-reported
confidence/scalar. `calibration` is a separate optional derived view. Its asset
hash participates in the measurement specification and Observation provenance.

The installed `identity` asset only renormalizes a derived view; it is not an
empirical calibration. A caller may supply a safe temperature asset with a
positive temperature from 0.05 through 20. Experimental transforms remain labeled
experimental. An `empirical` declaration additionally requires a model and corpus
hash, but the runtime labels that claim as an asset-author declaration, not an
independently verified human study. A mismatched model yields
`calibration_unavailable`. Provider confidence is never relabeled calibrated.

```elixir
calibration = %{"id" => "project.tactic", "method" => "temperature",
  "temperature" => 1.5, "validation" => "experimental", "model" => "fixture"}
# Pass calibration: calibration or calibration: "identity" to evaluate/4.
```

## Cache, privacy and model stability

`Cache.ETS.start_link/1` creates a private, process-owned ETS cache with LRU eviction,
TTL expiry, entry count and entry-byte caps. `Cache.Memory` remains available.
Both implement the same DB-free L1 callback contract. Durable L2 storage remains
an Intelligence/host responsibility and is not introduced by this phase.

```elixir
{:ok, cache} = Fount.Observe.Cache.ETS.start_link(max_entries: 500, ttl_ms: 300_000)
opts = [cache: {Fount.Observe.Cache.ETS, cache}, privacy_namespace: "project-private"]
```

A namespace is mandatory whenever a cache is supplied. Cache identity includes
the effective measurement specification, exact semantic input, model/provider
fingerprint and semantic execution parameters. It excludes revision provenance.
Every cache hit revalidates output shape, normalized raw value, distribution,
calibration, diagnostics and content identity. Cache outages are misses, not
invented answers; cache errors do not silently convert failed acquisition into
negative evidence.

`cache_policy: :stable_only` is the default: unknown/mutable identities are not
cached. `:session` explicitly permits reuse within the provider's session.
`:durable` refuses unstable identity before dispatch. A model name that looks
versioned is not proof of immutability. The hosted/generic SystemOne constructor
therefore remains `mutable_alias_or_unknown`; it records requested and reported
model identity, SDK version, endpoint digest and a private session identifier
without publishing the endpoint or key. A model override is not covered by a
stability assertion for a different model. Secrets stay in the opaque client.

## Preflight, actual work and partial results

`Fount.Observe.preflight/3` runs no provider, cache or budget operations. It returns
target/question counts, exact semantic-input byte counts, measurement-spec bytes
and active caps. Wire-request bytes, reuse, token price and money remain unknown
when they cannot be established. Semantic bytes are not advertised as wire bytes.

`max_states`, `max_context_bytes`, `max_questions`, `max_question_bytes`, timeouts,
concurrency and a shared `Budget` control acquisition. `max_request_bytes` is
forwarded to the inspected SDK's wire-size guard. Optional `max_provider_requests`
caps initial dispatches and forces retries off; combining an explicit finite
request cap with `retry: true` is rejected. Without that cap, SDK retry behavior
is retained and actual totals are only reported where the SDK supplies enough
information. The shared Budget counts scheduled states, not dollars or tokens.

Actual accounting distinguishes scheduled states, successful states, reused work,
reported retry/usage data and unknown spend. Cache-hit metadata is not billed as
new work. Failed/timeout requests may have consumed provider resources; their
unreported totals are `nil`, not guessed zero. A cancelled/expired scheduled state
is conservatively not refunded from the shared state budget.

The SystemOne adapter sends each normalized completed result to the call
coordinator. Total timeout, cancellation or later transport failure preserves
those completed results. Missing indexes receive typed errors; duplicate indexes
are still rejected. Runtime QC must verify SDK worker cleanup and real provider
cancellation behavior rather than infer it from an offline source inspection.

## Safe lens declarations

`Lens.validate/1` accepts a data-only declaration built from installed sensors,
projections, closed context schemas, question overrides, interpretation thresholds,
and numeric resource requests. It cannot resolve executable module/function names,
URLs, provider credentials or remote schemas. A project lens's requested caps can
only reduce the caller's effective host caps. Lens descriptions and interpretation
thresholds are retained in Observation provenance but do not change raw model
measurement identity when the effective questions/input contract are unchanged.

## Deterministic, human and imported observations

These paths need no model or database. A rule computes a value in its own caller;
Observe does not accept executable callbacks in assets. Use `Recording.record/3`
with `origin: "deterministic"` or `"human"`, an explicit producer, question kind,
and a validated literal output contract. The resulting distribution is `nil`;
there is no fabricated confidence or probability. A producer SHA may identify a
specific deterministic rule; absence of one is not treated as immutable identity.

```elixir
alias Fount.Observe.{OutputContract, Recording, Request}
{:ok, request} = Request.new(model, "intent-note", %{"passage" => "Mara pockets a key."})
contract = OutputContract.literal("project.intent_note", %{"type" => "string"})
{:ok, observation} = Recording.record(request, "Keep the ambiguity.",
  contract: contract, origin: "human", producer: "writer", kind: "scene.intent")
packet = Recording.export(observation)
{:ok, imported} = Recording.import_record(request, packet, contract: contract)
```

Imports require a matching active contract, semantic input and projection identity.
They retain the original producer/measurement identity while creating a fresh
current-revision Observation and explicitly marking imported provenance. They do
not import stale source spans or mutate the screenplay. These values are not
silently fed to playbooks that require probabilistic distributions.

## Fixture files

`Sandbox.fixture/3` constructs a serializable record bound to semantic input,
question semantics, projection and output-contract digests. `Sandbox.load/2` reads
only a local regular JSON file with a byte cap, a closed packet shape and no
duplicate bindings. Changed input or questions yield a missing fixture error;
stale output shapes yield `stale_contract`, never an inferred answer. Direct
`Sandbox.new!/2` fixtures remain supported for existing deterministic playbooks.

Run `mix run examples/fixture_file.exs` for the installed data-only fixture.

## Verification status

Phase 2 runtime QC executed the focused tests and examples, four-package `mix ci`,
isolated database integrations, writer demonstrations, package builds, and one
authorized synthetic TypeSafe measurement. See the docset's
`handoffs/PHASE_02_RUNTIME_QC_REPORT.md` for commands and limitations. No human
usefulness or calibration study is claimed.
