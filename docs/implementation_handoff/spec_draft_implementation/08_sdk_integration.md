# Model integration: Jev and Inference completions

Fount calls **Inference** for all generative completions. The Codex adapter's runtime dependency is `agent_session_manager`; Fount does not call its session API. The local runtime checkout is `~/p/g/n/agent_session_manager`. It was inspected only to verify installation requirements, including its Elixir `~> 1.19` requirement. It is not a fourth implementation target or a required fourth Repomix input.

## Dependencies and runtime setup

Use Elixir 1.19 or a compatible later version throughout this development workspace. Preserve compatible existing dependency versions and update each package's lockfile after resolving the actual dependency graph.

| Consumer | Dependency |
| --- | --- |
| Probe | `{:fount, path: "../fount"}` |
| Probe | `{:system_one_sdk, path: "../../../system_one_sdk/packages/system_one_sdk"}` |
| Probe | `{:inference, path: "../../../inference/apps/inference"}` |
| Workshop | `{:fount, path: "../fount"}`, `{:fount_probe, path: "../fount_probe"}` and the same Inference path |
| Probe and Workshop development commands/examples | `{:agent_session_manager, "~> 0.16.0", only: :dev}` |

The runtime dependency may instead use `path: "../../../agent_session_manager", only: :dev` in the known local workspace. Record which form was tested. Prefer the published dependency in the portable overlay so the recipient with three XMLs can resolve ordinary dependencies without reconstructing another repository. Version 0.16.0 matches the inspected local checkout and the [published package](https://hex.pm/packages/agent_session_manager/0.16.0). Consumers running Workshop outside Mix's development environment install this optional completion runtime in their host application. No runtime dependency belongs in core Fount.

System One's current package manifest depends on sibling `../system_one_contracts`. Reconstruct the System One repository layout from its XML, including that package. Do not replace the public SDK with an HTTP wrapper because an older root guide describes a different layout.

Libraries receive clients/options explicitly. Launchers read `SYSTEM_ONE_API_KEY`, optional `SYSTEM_ONE_BASE_URL`, `FOUNT_JEV_MODEL` (default `jev-latest`), and required `FOUNT_CODEX_MODEL`. Codex authentication is configured through the installed provider's supported login flow. Never embed credentials or assume a model name remains available. A preflight reports missing dependencies, authentication or configuration before starting a writing session.

## Jev construction and questions

The reviewed SDK exposes `new_client/1`, `noul/2`, `choice/2`, `score/2`, `prepare/1`, `prepare!/1`, `evaluate/4`, `evaluate_stream/4`, and `evaluate_many/4` through its public facade. Follow the XML source if overload details differ.

```elixir
client = SystemOneSDK.new_client(
  api_key: api_key,
  base_url: base_url,
  model: jev_model,
  timeout_ms: 60_000,
  retry: false
)

prepared = SystemOneSDK.prepare!(%{
  "mara_knows" => SystemOneSDK.noul(
    "Does the supplied accessible evidence establish that Mara knows Dan forged the ledger?",
    criteria: %{
      "true" => "The accessible evidence establishes her knowledge.",
      "false" => "The accessible evidence does not establish her knowledge."
    }
  )
})

{:ok, response} = SystemOneSDK.evaluate(client, state, prepared, [])
answer = SystemOneSDK.Response.fetch!(response, "mara_knows")
p_true = answer.noul
```

`state` is the SDK-supported UTF-8 state string produced by encoding the explicit perspective packet, not an arbitrary Fount struct. Use string question keys throughout. Questions contain instructions/criteria; evidence belongs in state. Group questions only when they share the same permitted evidence. Knowledge questions and a creative packet containing future secrets must never share a state by convenience.

Choice supports 2–255 options; Score supports 2–10 ordered levels. Use string option labels and an ordered pair list when order matters. Score legends include a concrete explanation of every level. Do not encode screenplay IDs as hidden cues in blind voice labels. Store `Prepared.fingerprint/1` and profile version using public accessors; do not depend on private prepared fields.

## Answer types and workload execution

| Answer | Fields used | Interpretation |
| --- | --- | --- |
| Noul | `noul` | Probability of the supplied proposition. There is no independent `confidence` field. |
| Choice | `choice`, `confidence`, `probabilities`, `option_order` | Preserve the entire distribution and question option order. |
| Score | `score`, `confidence`, `probabilities`, `level`, `label`, `legend`, `levels`, `rubric` | Preserve distribution and rubric. A mean score is not necessarily an attained level. |

Score probability keys are ordinal indices in the SDK answer; JSON serialization represents them as decimal string keys. Decode them through explicit integer parsing within the declared rubric range, keeping label/index mapping intact. Do not compare a string key to an integer and silently lose its probability mass.

The top-level response supplies model, usage, request ID, batch index, elapsed timing and prepared fingerprint when available. Missing metadata remains null. Do not invent token counts, prices, confidence or request IDs. `Response.fetch/2` returns `{:ok, answer}` or `:error`; missing keys become explicit failed items rather than zero-valued answers.

Use `evaluate_stream` for multiple states with the same prepared questions. Initial host defaults: `max_concurrency: 4`, `max_pending: 8`, `ordered: false`, `on_error: :collect`, `task_timeout_ms: 120_000`, `attempt_timeout_ms: 60_000`. These are configurable operational defaults, not model performance claims. The SDK owns worker lifecycle and request batching. Associate success via `response.batch_index` and error via `error.details.batch_index`; never zip an unordered stream to the input list. Assign an immutable request key before dispatch and retain its input mapping.

Group workloads by projection/profile/prepared questions, then map each group's local batch indices back to request keys. Consume the stream completely or cancel through supported SDK ownership semantics. Default Fount policy performs no additional transport retry beyond the configured SDK policy. A user retry reruns failed request keys; it does not duplicate successful reports. Preserve failures in denominators and coverage counts.

Reject malformed distributions through the SDK's validation. Its probability-sum tolerance is not permission to normalize a response silently. Probe thresholds in 07 are application judgments, not calibration claims about screenplay craft. Jev results remain probabilistic, including when repeat requests happen to agree. See the [System One introduction](https://docs.typesafe.ai/introduction) for the product's evaluation model; this specification makes no latency or cost guarantee.

## Inference: structured completions through Codex

```elixir
client = Inference.Client.agent_session!(
  adapter: Inference.Adapters.ASM,
  provider: :codex,
  model: codex_model,
  defaults: [lane: :sdk, run_deadline_ms: 180_000, cwd: completion_directory]
)

capabilities = Inference.capabilities(client)
structured? = Inference.Capability.supported?(capabilities, :response_format_json_schema)

format = {:json_schema, %{name: "fount_proposal", strict: true, schema: proposal_schema}}
# When structured? is true:
{:ok, response} = Inference.complete(client, prompt, response_format: format)
```

Use an empty temporary working directory for the completion runtime. All screenplay context is supplied by Fount in the prompt; the provider must not edit the repository or access the screenplay database. The adapter enforces its completion-only profile. No Fount code calls ASM directly, invokes a second Codex CLI wrapper, or forwards `tools`, `tool_choice`, `host_tools`, `dynamic_tools`, or `allowed_tools` into this adapter.

If structured output is explicitly supported, request it and validate the returned `response.object` locally. If the capability is unknown or unsupported but text completion works, request a single JSON object in text and parse `response.text` with the **same local validator**. Record the response mode. This is use of a supported text completion interface, not a substitute provider. Do not strip arbitrary text until some substring happens to parse: optionally accept one whole JSON code fence, otherwise return a decode error.

Use JSON Schemas as the local canonical contracts. Adapt their representation for a provider's admitted schema subset when necessary, retaining local validation of the full contract. For example, convert an operation union into a required object with nullable fields if the provider requires that shape; decode it into the canonical operation union and reject unused non-null fields. Record and test the translation. Never weaken the edit validator to satisfy a model.

One repair completion is allowed by default for malformed output: supply exact validation errors and the original request, without changing the base revision. A creative repair of a valid candidate is a separate round in 09. Retain provider/model, response mode, request/response hash, usage/cost if supplied, finish reason and timestamps. Do not persist credentials, provider internal reasoning, or raw transport dumps. The supplied model's returned screenplay text is persisted as proposed writing with its provenance.

## Application-owned tool use

An investigation completion returns hypotheses and a list of known Probe calls. Fount validates each call, executes the selected tools itself, then sends evidence-addressed results to a subsequent Inference completion. This supports W09 without native provider tool control. The same pattern serves extraction, strategy development and consequence repair. No model output becomes Elixir code, SQL, shell commands, module names or filesystem paths.

Provider unavailability returns a failed/partial session and existing saved results. It does not turn a live example into an offline demonstration. Unsupported provider additions belong in [13](13_wishlist_and_upstream.md).

## Offline boundary doubles

Use `SystemOneSDK.Test.client/0`, `stub/3`, `stub_sequence/2`, `stub_callback/2`, `requests/1`, and `verify!/1` to exercise the real SDK-facing code without HTTP. Verify while the owning test process is alive, then close the client. Stub exact string question keys and actual answer shapes. Include unordered completion and per-item error coverage where the executor joins results.

Use `Inference.Adapters.Mock` with `adapter_opts: [response_object: value]` for structured responses, `response_text` for text parsing, and configured errors for failure cases. The Mock client uses the adapter's `:model_endpoint` kind. Tests must not instantiate the authenticated Codex runtime. A small scripted completion double can supply a sequence of responses and record requests when the stock mock's single response is insufficient; it must retain Inference's response/error contract.
