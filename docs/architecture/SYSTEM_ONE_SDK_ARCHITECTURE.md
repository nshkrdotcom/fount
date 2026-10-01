# System One SDK architecture

Snapshot: `155c3309892dfacdebe2a2f1256fa71e03dc545d`. This repository contains four independent Mix projects, not an umbrella. The rich client is SystemOneSDK 0.6.0; the shared wire/inference package is SystemOneContracts 0.1.0. The SDK can use hosted HTTP, a compatible endpoint or an in-process contracts provider.

The diagrams distinguish checked-in implementation from future service exposure. Some overview documents still describe native execution as planned; the inspected source already contains the Bumblebee provider, resident Laya runtime, checkpoint loaders and model intake tools. That does not imply every model/backend combination has been validated or that downloads are automatic. SystemOneServer remains a scaffold with no serving API.

## 1. Ecosystem view

Solid arrows show calls or translated data. Dashed arrows show the planned HTTP server path, which is not implemented at this snapshot.

```mermaid
---
config:
  theme: neutral
---
flowchart TB
  App[Application: Fount Observe or another consumer] --> SDK[SystemOneSDK: semantic API and client]
  SDK --> TS[Providers.TypeSafe]
  SDK --> EP[Providers.Endpoint]
  SDK --> Bridge[Providers.Contract]
  TS --> TSAPI[TypeSafeAPISDK: generated operations and HTTP]
  TSAPI --> Hosted[Hosted TypeSafe System One API]
  EP --> Pristine[Pristine HTTP pipeline]
  Pristine --> Remote[Compatible external System One v1 service]
  Bridge --> Contract[SystemOneContracts.Provider]
  Contract --> Native[SystemOneBumblebee.Provider]
  Contract --> Other[Other in-process contracts provider]
  Native --> Laya[Resident Laya model runtime]
  Laya --> Nx[Nx and Bumblebee model execution]
  Remote -.->|future deployment option| Server[SystemOneServer: scaffold only]
  Server -.->|planned inference seam| Contract
  Wire[SystemOneContracts: v1 DTOs and codecs] -->|shared data contract| EP
  Wire -->|shared data contract| Bridge
  Wire -->|shared data contract| Native
```

Hosted use does not require Bumblebee, Nx, EXLA, Plug or Bandit. The main SDK has no dependency on the optional native/server packages. Native providers and the planned server depend inward on Contracts, not back on the rich SDK. External process/container lifecycle belongs outside the native inference package.

## 2. SDK components

Arrows show calls and data use, not a complete compile-time dependency graph. Provider-specific response types terminate at the adapters and are normalized into SDK results.

```mermaid
---
config:
  theme: neutral
---
flowchart TB
  API[SystemOneSDK public API] --> Questions[Question.Noul, Choice and Score]
  Questions --> Prepared[Prepared: ordered keys, validation and fingerprint]
  API --> Client[Client: provider module and opaque provider state]
  API --> Evaluation[Evaluation]
  API --> Batch[Batch.stream and Batch.many]
  API --> Models[Models and capability helpers]
  Batch --> Evaluation
  Evaluation --> Prepared
  Evaluation --> Normalize[JSON normalization and RequestBudget]
  Normalize --> Client
  Models --> Client
  Client --> Provider[SystemOneSDK.Provider behaviour]
  Provider --> TypeSafe[Providers.TypeSafe]
  Provider --> Endpoint[Providers.Endpoint]
  Provider --> Contract[Providers.Contract and ContractBridge]
  TypeSafe --> TSAPI[TypeSafeAPISDK]
  Endpoint --> Pristine[Pristine, retry policy and transport metadata]
  Contract --> DTO[SystemOneContracts v1 request and response]
  Provider --> Raw[Normalized SystemOneResponse or SDK Error]
  Raw --> Validate[ResponseContract validation]
  Validate --> Enrich[SemanticResponse enrichment]
  Enrich --> Answers[Answer helpers, distributions, usage and timing]
  Evaluation --> Telemetry[Telemetry spans and answer events]
  Client --> Capabilities[RuntimeCapabilities requirements]
  OTP[OTP.Server optional asynchronous wrapper] --> Evaluation
  Testing[Test fixtures, fake transport and Conformance] -.->|offline verification| API
```

`Noul`, `Choice` and `Score` are semantic question families, not text-generation modes. `Prepared` preserves question ordering and identity across calls. The rich SDK owns semantic validation, response enrichment and batch policy. TypeSafeAPISDK owns its provider's HTTP/auth/defaults, generated operations, wire schemas, retries and raw transport metadata; this repo does not recreate that code generation layer.

## 3. One semantic evaluation

The provider seam is selected once in client configuration. Preparation, request-size checks and response validation are common across providers.

```mermaid
---
config:
  theme: neutral
---
sequenceDiagram
  participant App as Application
  participant SDK as SystemOneSDK
  participant Eval as Evaluation
  participant Prep as Prepared
  participant Client as Client and Provider
  participant Impl as Configured adapter
  participant Runtime as Hosted endpoint or in-process runtime
  App->>SDK: evaluate(client, state, questions, options)
  SDK->>Eval: Run semantic evaluation
  Eval->>Prep: Validate question keys, order and payload
  Prep-->>Eval: Prepared questions and fingerprint
  Eval->>Eval: Normalize JSON, validate options and request budget
  Eval->>Client: system_one_prepared
  Client->>Impl: Dispatch with opaque provider state
  alt TypeSafe hosted provider
    Impl->>Runtime: TypeSafeAPISDK generated HTTP operation
  else Compatible endpoint provider
    Impl->>Runtime: v1 DTO through Pristine HTTP
  else Contracts provider
    Impl->>Runtime: Contracts.Provider.system_one with v1 Request
  end
  Runtime-->>Impl: Response or execution error
  Impl-->>Client: SDK response or normalized SDK Error
  Client-->>Eval: Provider result
  Eval->>Eval: Validate response contract and semantic distributions
  Eval->>Eval: Enrich answers, usage, timing and fingerprint
  Eval-->>SDK: Result with telemetry
  SDK-->>App: Success or explicit error
```

This is the success path with errors summarized, not a claim that failed validation continues to dispatch. Invalid input fails before execution; malformed or incompatible output fails at the response boundary. Telemetry spans cover the operation, including failures. Adapter-specific retry/timeout handling stays distinct from batch worker limits.

## 4. Batch and OTP lifecycle

Arrows show ownership and work flow. Streaming is lazy; `many` collects the stream into a list. Each input has an index so callers can associate unordered completion with the original request.

```mermaid
---
config:
  theme: neutral
---
flowchart LR
  Caller[Caller enumerates evaluate_stream] --> Resource[Stream.resource]
  Resource --> Lifecycle[Batch.Lifecycle owner]
  Lifecycle --> Supervisor[Task.Supervisor]
  Inputs[Indexed input states] --> Queue[Bounded pending work]
  Queue --> Tasks[Concurrent evaluation tasks]
  Supervisor -->|supervises| Tasks
  Tasks --> Eval[Evaluation.run per input]
  Eval --> Output[Indexed successes or collected errors]
  Output --> Order[Ordered or completion-order results]
  Order --> Caller
  Controls[Concurrency, max_pending, task and attempt timeouts] --> Queue
  Cancel[Cancellation, early halt or caller exit] --> Lifecycle
  Lifecycle -->|cleanup| Supervisor
  OTP[Optional OTP.Server] -->|async work| Eval
  Eval -->|reply or error| OTP
```

Batch owns its task lifecycle rather than leaving work running when enumeration stops. The OTP helper supports application-owned GenServer integration and pending task replies; it is not SystemOneServer and does not expose an HTTP endpoint. The library has no mandatory global client supervisor.

## 5. Native runtime detail

This view zooms into the optional `system_one_bumblebee` package. Solid arrows show loading or inference; initialization and the inference path are separated into groups.

```mermaid
---
config:
  theme: neutral
---
flowchart TB
  Request[Contracts v1 Request] --> Provider[SystemOneBumblebee.Provider]
  subgraph Load[Model selection and initialization]
    Registry[ModelRegistry: configured IDs and aliases]
    Manifest[ModelManifest and immutable ArtifactPin]
    Artifacts[Artifacts: download and checksum validation]
    ServingSupervisor[ServingSupervisor]
    Serving[Serving: resident adapter state]
    Adapter[ModelAdapter: Laya path]
    Profile[Explicit RuntimeProfile: backend and compiler]
    Registry --> Manifest
    Manifest --> Artifacts
    Artifacts --> Serving
    ServingSupervisor -->|supervises| Serving
    Serving --> Adapter
    Profile --> Serving
  end
  Provider --> Registry
  Provider --> Serving
  Adapter --> Runtime[Laya.Runtime]
  subgraph Model[Resident Laya model]
    Config[Config and calibration data]
    Tokenizer[Tokenizer and preprocessing]
    Encoder[ModernBERT encoder and loaded parameters]
    Head[Custom decision head and loaded parameters]
    Decode[Calibration, decoding and probability output]
    Config --> Tokenizer
    Tokenizer --> Encoder
    Encoder --> Head
    Head --> Decode
  end
  Runtime --> Config
  Runtime --> Tokenizer
  Artifacts -->|reviewed checkpoint files| Encoder
  Artifacts -->|reviewed checkpoint files| Head
  Decode --> Response[Contracts v1 Response and Usage]
  Response --> Provider
```

`Serving` owns initialization and state lifetime; it supplies a fast immutable snapshot so inference runs outside the GenServer mailbox. The Laya runtime loads encoder/head parameters, tokenizer and calibration once, then batches the questions within a request through resident state. The registry does not let requests choose arbitrary Hugging Face repositories. Artifact acquisition uses configured manifests, HfHub download support and checksum/manifest validation. EXLA is optional; the host supplies backend/compiler choices explicitly.

Model intake/checkpoint accounting and fake adapters support preparation and offline verification. Their presence is not a promise of unqualified production readiness. HTTP authentication, service routing and container lifecycle are outside this package.

## 6. Boundary summary

| Boundary | Owns | Does not own |
| --- | --- | --- |
| SystemOneSDK | Semantic questions, preparation, response validation, batching, telemetry, OTP helpers, runtime requirements and conformance | Model checkpoint storage or an HTTP server |
| SystemOneContracts | v1 DTOs/codecs, ordered question entries, error/capability vocabulary and inference-provider behaviour | HTTP transport, client retries or model lifecycle |
| TypeSafeAPISDK | Hosted TypeSafe HTTP/auth, generated operations and provider wire formats | Fount interpretation or candidate acceptance |
| SystemOneBumblebee | Configured models, pinned artifacts, resident native execution | Hosted credentials, HTTP exposure or container management |
| SystemOneServer | Planned v1 HTTP facade; current scaffold | A currently available serving implementation |

Fount consumes the rich SDK only through Observe's `Providers.SystemOne`: neutral questions become SDK questions, `prepare` and `evaluate_stream` run, and SDK-native results/errors become neutral observations. Fount's completion writing uses Inference separately; the two paths are not interchangeable.

## Source map

All links refer to the reviewed commit:

- [SDK provider behaviour](https://github.com/nshkrdotcom/system_one_sdk/blob/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_sdk/lib/system_one_sdk/provider.ex), [Client](https://github.com/nshkrdotcom/system_one_sdk/blob/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_sdk/lib/system_one_sdk/client.ex), [Evaluation](https://github.com/nshkrdotcom/system_one_sdk/blob/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_sdk/lib/system_one_sdk/evaluation.ex).
- [Batch](https://github.com/nshkrdotcom/system_one_sdk/blob/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_sdk/lib/system_one_sdk/batch.ex), [batch lifecycle](https://github.com/nshkrdotcom/system_one_sdk/blob/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_sdk/lib/system_one_sdk/batch/lifecycle.ex), [OTP helper](https://github.com/nshkrdotcom/system_one_sdk/blob/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_sdk/lib/system_one_sdk/otp/server.ex).
- [Provider adapters](https://github.com/nshkrdotcom/system_one_sdk/tree/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_sdk/lib/system_one_sdk/providers), [contracts provider seam](https://github.com/nshkrdotcom/system_one_sdk/blob/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_contracts/lib/system_one_contracts/provider.ex).
- [Native package implementation](https://github.com/nshkrdotcom/system_one_sdk/tree/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_bumblebee/lib/system_one_bumblebee), [resident Laya runtime](https://github.com/nshkrdotcom/system_one_sdk/blob/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_bumblebee/lib/system_one_bumblebee/models/laya/runtime.ex), [server scaffold](https://github.com/nshkrdotcom/system_one_sdk/blob/155c3309892dfacdebe2a2f1256fa71e03dc545d/packages/system_one_server/lib/system_one_server.ex).
