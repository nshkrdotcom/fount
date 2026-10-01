# Fount architecture

Snapshot: `de5e9549794368bf38ab774bdf304ce4c76c28ca`. Fount is a Phoenix host over five independently built screenplay packages. PostgreSQL stores screenplay revisions, candidate writing, analysis and durable runs. The accepted draft changes through Core's validated acceptance transaction, not merely when pages are generated or saved.

## 1. System view

Arrows show requests or data movement. External model services are optional and explicitly configured; the development launcher uses deterministic analysis and a demo completion adapter.

```mermaid
---
config:
  theme: neutral
---
flowchart TB
  Writer[Writer] --> Browser[Browser]
  Files[Fountain and FDX files] --> Web
  Browser <-->|HTTP and LiveView websocket| Web
  subgraph Host[Phoenix host]
    Web[FountWeb: authentication, projects and workspaces]
    Run[FountRun: durable workflow execution]
    Workshop[FountWorkshop: candidate writing and review]
    Intelligence[Fount.Intelligence: screenplay investigation]
    Observe[Fount.Observe: bounded measurements]
    Core[Fount: screenplay model and persistence]
    Web --> Run
    Web --> Workshop
    Web --> Core
    Run --> Workshop
    Workshop --> Intelligence
    Workshop --> Core
    Intelligence --> Observe
    Intelligence --> Core
    Observe --> Core
  end
  Observe -->|configured measurements| SDK[SystemOneSDK]
  SDK --> Service[TypeSafe or compatible System One endpoint]
  Observe -->|offline alternative| Sandbox[Deterministic fixtures]
  Workshop -->|configured completions| Inference[Inference]
  Inference --> Completion[Completion adapter or ASM-backed session]
  Core --> DB[(PostgreSQL)]
  Run --> DB
  Web --> DB
  Workshop --> Export[Fountain, FDX and PDF exports]
  Export --> Disk[Host-controlled artifact directory]
  Disk --> Web
```

The Web host owns credentials, owner identity, Repo startup, workers and artifact paths. Library calls receive those services explicitly. There is no requirement for a vector database, live provider or separate System One server to inspect a screenplay locally.

## 2. Package dependencies

Here `A --> B` means **A depends on B**, not execution order. Repeated direct Core dependencies are included because they define the shared model boundary.

```mermaid
---
config:
  theme: neutral
---
flowchart LR
  Web[apps/fount_web] --> Run[fount_run]
  Web --> Observe[fount_observe]
  Web --> Core[fount]
  Run --> Workshop[fount_workshop]
  Run --> Core
  Workshop --> Intelligence[fount_intelligence]
  Workshop --> Core
  Intelligence --> Observe
  Intelligence --> Core
  Observe --> Core
  Observe --> SDK[system_one_sdk ~> 0.6.0]
  Web --> Inference[inference ~> 0.5.1]
  Workshop --> Inference
  Workshop --> ASM[agent_session_manager ~> 0.17.3]
  Core --> Ecto[Ecto SQL and Postgrex]
```

Only Observe owns System One integration. Only Workshop owns completion integration. ASM is a published dependency; the live launcher selects it through `Inference.Adapters.ASM`. No lower package imports Run or the Phoenix host. The root workspace orchestrates independent package builds; it is not an Elixir umbrella.

## 3. Analysis components

Solid arrows show selected input, calls or results. The pure interpretation boundary receives explicit values and evidence; provider handles stay in the acquisition shell.

```mermaid
---
config:
  theme: neutral
---
flowchart TB
  Model[Selected screenplay and exact revision] --> Select[Core Selection, Inventory, Search and SourceEvidence]
  Select --> Runner[Intelligence Runner and writer playbooks]
  subgraph Pure[Pure interpretation]
    World[StoryWorld: entities, events and causal records]
    Time[Temporal: partial story-time constraints]
    Reader[Reader: forward presentation checkpoints]
    Diagnosis[Diagnosis: hypotheses and missing evidence]
    World --> Time
    World --> Reader
    Time --> Diagnosis
    Reader --> Diagnosis
  end
  Runner --> World
  Diagnosis -->|EvidenceNeed values| Runner
  Runner --> Context[Acquisition.ContextBuilder]
  Context --> Request[Observe Request, Question and Lens]
  Request --> Executor[Observe Executor: validation and association]
  Registry[Installed sensor and projection Registry] --> Executor
  Executor <-->|bounded L1 reuse| Cache[Memory or ETS cache]
  Executor --> Call[ProviderCall: task ownership and cancellation]
  Call --> Adapter[Providers.SystemOne]
  Call --> Sandbox[Sandbox fixtures]
  Adapter --> SDK[prepare and evaluate_stream]
  SDK --> Results[Neutral observations and distributions]
  Sandbox --> Results
  Results --> Runner
  Runner --> Reports[Revision-bound reports and saved records]
```

Source order, story-time order and causality are separate coordinates. The Reader cannot consume evidence from future pages. Exact search does not dispatch providers. Intelligence can request missing evidence and diagnose a concern, but cannot write or accept screenplay pages. The L1 cache is not durable analytical storage.

## 4. Editing and acceptance

This sequence covers manual and generated candidate work. A draft save, note edit or cast rename does not itself advance the accepted head.

```mermaid
---
config:
  theme: neutral
---
sequenceDiagram
  actor Writer
  participant UI as FountWeb
  participant WS as Workshop session and review
  participant Gen as Inference completion
  participant Core as Fount.Persistence
  participant DB as PostgreSQL
  Writer->>UI: Select exact revision and operation
  UI->>WS: Open validated session with trusted services
  alt Generated writing
    WS->>Gen: Structured completion with bounded resources
    Gen-->>WS: Proposed pages or explicit error
  else Manual writing or authored-item edit
    UI->>WS: Validated edits and exact targets
  end
  WS->>Core: Save candidate against base revision
  Core->>DB: Persist candidate, provenance and dependencies
  DB-->>UI: Candidate saved, accepted head unchanged
  Writer->>UI: Review exact candidate and checks
  UI->>WS: Typed approval and trusted authority
  WS->>Core: Review.accept validation and Core acceptance
  Core->>DB: Transaction checks candidate base against current head
  alt Approval valid and base current
    DB-->>Core: New accepted revision and updated head
    Core-->>UI: Accepted result
  else Stale, conflicting or unauthorized
    DB-->>Core: Reject without advancing head
    Core-->>UI: Explicit conflict or denial
  end
```

Source-backed edits reconcile stable IDs after parsing and retain exact revision/source anchors. Changed note targets become `stale_changed`; deleted targets become `unresolved`. Remapping is explicit. Analysis annotations remain separate from writer-authored items.

## 5. Runtime and workflow control

Arrows show supervision, notification or stage dispatch, as labeled. The shared Repo has migrations from Core, Run and the host.

```mermaid
---
config:
  theme: neutral
---
flowchart TB
  Supervisor[FountWeb.Supervisor] -->|supervises| Repo[Fount.Repo]
  Supervisor -->|supervises| Endpoint[Phoenix Endpoint]
  Supervisor -->|supervises| PubSub[Phoenix.PubSub]
  Supervisor -->|supervises| Registry[WorkerRegistry]
  Supervisor -->|supervises| Dynamic[WorkerSupervisor]
  Supervisor -->|supervises| Events[RunEvents]
  Supervisor -->|supervises| Bootstrap[WorkerBootstrap]
  Bootstrap -->|restores authorized work| Dynamic
  Dynamic -->|supervises| Worker[FountRun.Worker]
  Worker -->|claim and checkpoint| Engine[FountRun.Engine]
  Engine --> Claim[Short database claim transaction]
  Claim --> Dispatch[Closed stage handler outside row lock]
  Dispatch --> Stages[Intake, investigate, plan, write, check, iterate, decide, deliver]
  Stages --> Workshop[Workshop services]
  Stages -->|checkpoint and decisions| Repo
  Claim --> Repo
  Controls[Pause, stop, plan and policy updates] --> Engine
  Fence[Lease, plan version, policy version and fencing token] --> Claim
  Events -->|notifications| PubSub
  PubSub -->|refresh persisted state| Live[LiveView workspaces]
  Endpoint --> Live
  Registry --- Worker
```

Model calls and reviewer calls execute outside Run row locks. Pause blocks new dispatch; stop fences old work while retaining saved results. Plan/policy updates use versioned snapshots. Decisions bind the authorized respondent and exact context. Reconnects reload persisted state; LiveView notifications are not the durable record. Browser draft recovery is distinct from server candidate storage.

## 6. Stored data view

This is a reduced logical map of actual table relationships, not a complete DDL diagram. `HOST_RUNS` maps a project to a Core Run row. Most entities also carry screenplay/revision and owner bindings beyond the edges shown.

```mermaid
---
config:
  theme: neutral
---
erDiagram
  PROJECTS ||--|| SCREENPLAYS : selects
  SCREENPLAYS ||--o{ REVISIONS : history
  SCREENPLAYS ||--o| REVISIONS : accepted_head
  REVISIONS ||--o{ REVISIONS : parent_of
  SCREENPLAYS ||--o{ IMPORT_ARTIFACTS : imports
  REVISIONS ||--o{ SCENES : contains
  REVISIONS ||--o{ ELEMENTS : contains
  SCREENPLAYS ||--o{ WRITING_SESSIONS : sessions
  WRITING_SESSIONS ||--o{ WRITING_CANDIDATES : proposes
  REVISIONS ||--o{ WRITING_CANDIDATES : base_for
  SCREENPLAYS ||--o{ RUNS : workflows
  PROJECTS ||--o{ HOST_RUNS : owns
  RUNS ||--o| HOST_RUNS : host_mapping
  RUNS ||--o{ RUN_PLANS : versions
  RUNS ||--o{ RUN_POLICIES : versions
  RUNS ||--o{ RUN_STEPS : executes
  RUNS ||--o{ RUN_DECISIONS : requests
  WRITING_CANDIDATES ||--o{ TOOL_CANDIDATES : host_binding
  PROJECTS ||--o{ TOOL_CANDIDATES : owns
  RUNS ||--o{ TABLE_READS : packets_and_progress
  RUNS ||--o{ USEFULNESS_RECORDS : recorded_outcomes
```

`PROJECTS`, `HOST_RUNS`, `TOOL_CANDIDATES`, `TABLE_READS` and `USEFULNESS_RECORDS` denote the `fount_web_*` tables; `RUN*` denotes `fount_run*`. An accepted-head edge is a selected reference, not a second revision store. The project/screenplay link is unique in the host. The map omits analysis tables, authoring drafts/commands, delivery records and the rest of the typed screenplay rows to keep the main relationships readable.

## 7. Core representation and edit pipeline

Arrows show transformations. The byte-preserving source representation and the normalized screenplay model answer different questions; reports and analysis do not replace either.

```mermaid
---
config:
  theme: neutral
---
flowchart LR
  Fountain[Fountain bytes] --> Scan[Byte scanner and contextual parser]
  Scan --> CST[Fountain CST: exact bytes and spans]
  Scan --> IR[IR.Script: ordered element stream]
  FDX[FDX import] --> Adapter[Format adapter and fidelity report]
  Adapter --> Screenplay[Immutable Fount.Screenplay]
  IR --> Screenplay
  CST --> Document[Source-backed Fount.Document]
  IR --> Document
  Edits[Typed Fount.Edit operations] --> Transform[Canonical model transformation]
  Screenplay --> Transform
  Transform --> Revision[New revision and ChangeSet]
  Document --> Patch[Resolved source patches and reparse]
  Edits --> Patch
  Patch --> Identity[Stable ID reconciliation]
  Identity --> Revision
  Revision --> Views[Scene, dialogue and outline ID-based views]
  Revision --> Persistence[Persistence codec and transaction boundary]
  Revision --> Projection[Fountain, FDX, JSON and inspection projections]
```

Offsets locate text; stable IDs identify objects. Scenes/dialogue/outline are views over a single ordered element stream. External rewrites use best-effort reconciliation and emit diagnostics when identity cannot be retained. Pure model construction and edits need no running database; storing or accepting a revision uses the PostgreSQL boundary.

## Inspection and output coverage

The viewer, editor and analysis workspace sit alongside provider-free literal search, cast profiles, location/scene inspection and writer notes. Table-read packets retain source identity and optimistic versioned progress; TTS is available only when configured. Usefulness records separate engineering facts from optional human judgments. Project dashboards and imports remain owner-scoped and capped. Fountain/FDX fidelity reporting and PDF inspection are output concerns, not screenplay truth; PDFs use Afterwriting 1.17.3 with PDFKit 0.20.2 and external PDF inspection utilities.

## Source map

All links refer to the reviewed commit:

- [Host application and supervision](https://github.com/nshkrdotcom/fount/blob/de5e9549794368bf38ab774bdf304ce4c76c28ca/apps/fount_web/lib/fount_web/application.ex), [routes](https://github.com/nshkrdotcom/fount/blob/de5e9549794368bf38ab774bdf304ce4c76c28ca/apps/fount_web/lib/fount_web/router.ex), [host service configuration](https://github.com/nshkrdotcom/fount/blob/de5e9549794368bf38ab774bdf304ce4c76c28ca/apps/fount_web/lib/fount_web/services.ex).
- [Core architecture](https://github.com/nshkrdotcom/fount/blob/de5e9549794368bf38ab774bdf304ce4c76c28ca/packages/fount/guides/architecture.md), [Observe architecture](https://github.com/nshkrdotcom/fount/blob/de5e9549794368bf38ab774bdf304ce4c76c28ca/packages/fount_observe/guides/architecture.md), [Intelligence architecture](https://github.com/nshkrdotcom/fount/blob/de5e9549794368bf38ab774bdf304ce4c76c28ca/packages/fount_intelligence/guides/architecture.md).
- [Workshop architecture](https://github.com/nshkrdotcom/fount/blob/de5e9549794368bf38ab774bdf304ce4c76c28ca/packages/fount_workshop/guides/architecture.md), [Run architecture](https://github.com/nshkrdotcom/fount/blob/de5e9549794368bf38ab774bdf304ce4c76c28ca/packages/fount_run/guides/architecture.md).
- [Core migrations](https://github.com/nshkrdotcom/fount/tree/de5e9549794368bf38ab774bdf304ce4c76c28ca/packages/fount/priv/repo/migrations), [Run migrations](https://github.com/nshkrdotcom/fount/tree/de5e9549794368bf38ab774bdf304ce4c76c28ca/packages/fount_run/priv/repo/migrations), [host migrations](https://github.com/nshkrdotcom/fount/tree/de5e9549794368bf38ab774bdf304ce4c76c28ca/apps/fount_web/priv/repo/migrations).
