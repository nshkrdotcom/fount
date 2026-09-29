# Phase 06 browser harness

Pinned runner: `@playwright/test` 1.63.0, Chromium only. The harness drives the real authenticated LiveView host and the deterministic no-credential demo adapter. It does not replace ExUnit or database integration tests.

Run from the repository root with `scripts/run_phase06_browser.sh`. The runner expects PostgreSQL at `FOUNT_DATABASE_URL`; it executes Core → Run → host migrations, builds host assets, starts the host on port 4011, and then runs the browser acceptance suite. PDF verification is a separate runtime gate because it requires Afterwriting plus Poppler tools.
