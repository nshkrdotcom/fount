# Browser acceptance harness

Pinned runner: `@playwright/test` 1.63.0, Chromium only. The harness drives the real authenticated LiveView host. Deterministic browser mode composes the credential-free scripted Inference adapter with the credential-free `Fount.Observe.Sandbox` provider; it therefore exercises the real Run → Workshop → Intelligence → Observe path without a paid/live provider.

Run from the repository root with `scripts/run_phase06_browser.sh`. The historical script name is retained because it is the maintained browser entry point. The runner expects PostgreSQL at `FOUNT_DATABASE_URL`; it executes Core → Run → host migrations, builds host assets, starts the host on port 4011, and then runs the browser acceptance suite. PDF verification is a separate runtime gate because it requires Afterwriting plus Poppler tools.

The H03-H05 journey creates a candidate-only selected-scene revision and asserts persisted/visible prewrite Intelligence, candidate Revision Intelligence, semantic advisory checks, authoritative required checks, reconnect persistence, and unchanged canonical base. Production System One mode is configured separately and is not exercised by this deterministic browser gate.

## Phase 04 viewer scenarios

`browser/tests/phase04_viewer.spec.mjs` extends the maintained harness with the read-only Phase 04 workspace: escaped canonical IR/title/dual-dialogue rendering, analyzer-backed indices, stable scene anchors, dialog focus/Escape behavior, narrow/dark/reduced-motion layouts, Run-bound candidate/accepted revision selection, structural diff presentation, stale identity fallback, reload/reconnect persistence and owner isolation. These scenarios are runtime gates and must be executed locally; the offline overlay does not certify them.
