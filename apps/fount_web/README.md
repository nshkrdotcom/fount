# FountWeb

`apps/fount_web` is the one-owner Phoenix LiveView host for the five Fount libraries. It is deliberately thin: Core owns canonical screenplay truth and acceptance, Workshop owns generated/revised pages, Intelligence interprets Observe measurements, and Run owns durable plans, policies, decisions, approval attempts, controls, resource records, progress, and delivery. The host owns authentication, session-derived identity, Repo/process startup, runtime services, worker supervision, browser rendering, upload bounds, and artifact-root authorization.

## Analysis service configuration

Every normal worker is constructed with the host-owned Observe service. Development/test defaults to credential-free `Fount.Observe.Sandbox` fixtures alongside the scripted Inference adapter. Production defaults to `FOUNT_OBSERVE_MODE=system_one` and builds the provider only through `Fount.Observe.provider/1`; FountWeb never constructs or imports native `SystemOneSDK` clients/types.

Production System One configuration is explicit:

```text
FOUNT_OBSERVE_MODE=system_one                 # default in prod
FOUNT_SYSTEM_ONE_ENDPOINT_KIND=typesafe      # or endpoint
SYSTEM_ONE_MODEL=<nonblank model id>
SYSTEM_ONE_API_KEY=<required for typesafe; optional for endpoint>
SYSTEM_ONE_BASE_URL=<optional typesafe override; required for endpoint>
```

Invalid/missing required configuration fails during runtime configuration or worker construction without printing values. `FOUNT_OBSERVE_MODE=compatibility` is the only production no-Observe lane; it is opt-in, visibly labeled, and records semantic analysis as `not_run` rather than success. `sandbox` is refused in production. Provider handles/credentials remain process-local and are never part of Run plans, steps, progress, Core rows or host mapping rows.

## Local deterministic launch

The default development configuration is a credential-free deterministic demo. The default token (`fount-demo-owner-token`) is intentionally non-secret and safe only for loopback development. A deployed host must set `FOUNT_OWNER_ID`, `FOUNT_OWNER_TOKEN`, `FOUNT_DATABASE_URL`, `FOUNT_ARTIFACT_ROOT`, `SECRET_KEY_BASE`, and `PHX_HOST`.

```bash
cd apps/fount_web
mix deps.get
mix fount_web.migrate       # Core -> Run -> host
mix assets.setup
mix assets.build
mix phx.server
# http://127.0.0.1:4000/login
```

The Hex and browser dependency locks were resolved during Phase 06 runtime QC and are committed. On a fresh checkout, use `FOUNT_SYSTEM_ONE_SDK_PATH` when resolving dependencies if the local System One SDK is supplied as a path rather than through Hex.

## Authenticated writer surfaces

The signed session contains only the configured owner id after a constant-time token check. Request parameters never construct `FountRun.ActorContext` or a principal. Every Run route is first resolved through `fount_web_runs`/`fount_web_projects` for the authenticated owner; the host then builds the trusted context server-side.

- `/projects/new` — bounded Fountain/FDX intake and deterministic Phase 06 journey selection.
- `/runs/:id/setup` — gates/completion with an explicit warning that accepted pages may advance canon.
- `/runs/:id/timeline` — durable PostgreSQL progress plus pause/resume/stop and unknown/partial resource visibility.
- `/runs/:id/decisions` — exact decision id/context fingerprint/plan version/policy version submission; stale forms reload durable state.
- `/runs/:id/review` — actual canonical base and stored candidate pages, structural diff, and persisted checks.
- `/runs/:id/exports` — standard bundle plus optional PDF/table read; format failures remain visible and independently retryable.
- `/artifacts/:run_id/:delivery_id` — owner-authorized, checksum-verified, server-rooted downloads. Browser-supplied file paths are never accepted.

The LiveView subscribes to Run worker telemetry only as a wakeup. A periodic `FountRun.progress/3` reload is the correctness path, so reconnect/socket loss does not own state.

## Deterministic journeys

`FountWeb.Journeys.fixture_fountain/0` is a rights-cleared three-scene fixture with dialogue and a protected train-platform beat. The demo adapter is a real `Inference.Adapter` implementation with no credential and `cost: nil` (unknown, never converted to zero). The same deterministic host composition also supplies Sandbox measurements through the real Workshop → Intelligence → Observe lane.

1. `opening`: human route choice -> checked opening candidate -> candidate-labeled delivery; canonical base remains unchanged.
2. `reveal`: human route choice -> intentionally violating first candidate -> protected-material repair -> exact human final approval -> delivery on request.
3. `dialogue`: selected scene only -> dialogue change -> configured service approval; the approval attempt records `demo-service` and any failure/fallback remains durable and visible.
4. `analysis`: selected scene only -> prewrite Intelligence -> human strategy route -> dialogue candidate -> Revision Intelligence -> layered check -> candidate-only completion; canonical base remains unchanged.

The deterministic adapter is an acceptance fixture and does not certify screenplay quality or generated writing quality.

## Browser acceptance

The maintained harness is `browser/` with `@playwright/test` 1.63.0 and Chromium. Run it from the repository root:

```bash
FOUNT_DATABASE_URL=ecto://... scripts/run_phase06_browser.sh
```

The runner migrates Core -> Run -> host, builds assets, starts the app on `127.0.0.1:4011`, and drives the retained U01-U05 coverage plus the integrated H03-H05 analysis/reconnect journey. The review surface shows safe prewrite/revision packet status (`complete`, `partial`, `failed`, or `not-run`) and separates semantic advisory checks from authoritative required Run/Core checks. Runtime QC must execute the maintained suite; this offline source delivery does not claim it passed.

PDF is never faked. It remains an explicit format failure unless Afterwriting and the configured Poppler checks are actually available.

## Build/release inventory

See `../../docs/implementation_handoff/PHASE_06_BUILD_AND_RELEASE.md` for the five-library + host build/release inventory.
