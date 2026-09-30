# Browser acceptance harness

Pinned runner: `@playwright/test` 1.63.0, Chromium only. The harness drives the real authenticated LiveView host. Deterministic browser mode composes the credential-free scripted Inference adapter with the credential-free `Fount.Observe.Sandbox` provider; it therefore exercises the real Run → Workshop → Intelligence → Observe path without a paid/live provider.

Run from the repository root with `scripts/run_phase06_browser.sh`. The historical script name is retained because it is the maintained browser entry point. The runner expects PostgreSQL at `FOUNT_DATABASE_URL`; it executes Core → Run → host migrations, builds host assets, starts the host on port 4011, and then runs the browser acceptance suite. PDF verification is a separate runtime gate because it requires Afterwriting plus Poppler tools.

The H03-H05 journey creates a candidate-only selected-scene revision and asserts persisted/visible prewrite Intelligence, candidate Revision Intelligence, semantic advisory checks, authoritative required checks, reconnect persistence, and unchanged canonical base. Production System One mode is configured separately and is not exercised by this deterministic browser gate.

## Phase 04 viewer scenarios

`browser/tests/phase04_viewer.spec.mjs` extends the maintained harness with the read-only Phase 04 workspace: escaped canonical IR/title/dual-dialogue rendering, analyzer-backed indices, stable scene anchors, dialog focus/Escape behavior, narrow/dark/reduced-motion layouts, Run-bound candidate/accepted revision selection, structural diff presentation, stale identity fallback, reload/reconnect persistence and owner isolation. These scenarios are runtime gates and must be executed locally; the offline overlay does not certify them.

For a complete automated phase cycle, use repository `scripts/run_runtime_qc.py --phase NN --output /absolute/new/qc-directory`. It supplies the browser harness a separate local database from ExUnit, while retaining both Phase 04 and existing Phase 06 browser files. Scene selection, reduced-motion scrolling, keyboard input isolation and repeated dialog lifecycle assertions execute in the Phase 04 file. The agent repairs failures and retries without a human review step.

## Phase 05 authoring scenarios

`browser/tests/phase05_authoring.spec.mjs` covers the interactive Fountain editor and recovery lifecycle: 300 ms debounced preview, Unicode/paste/IME composition, last-valid preview for invalid raw input, text undo/redo, editor/preview/split modes, narrow layout, durable reload, two-tab optimistic conflict and fork recovery, noncanonical manual candidate save, durable Run AI handoff, and separate exact candidate acceptance. It is retained alongside the Phase 04 viewer and original Phase 06 regression journeys and is executed by `scripts/run_runtime_qc.py --phase 5 ...`.
