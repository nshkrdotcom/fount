#!/usr/bin/env bash
# Final acceptance runner: retained Phase-16 library audit plus Phase-06 web-host integration.
set -u
set -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---runtime}"
if [[ "$MODE" != "--static" && "$MODE" != "--runtime" ]]; then
  printf 'Usage: bash scripts/final_acceptance.sh [--static|--runtime]\n' >&2
  exit 2
fi

cd "$ROOT" || exit 2
python3 scripts/final_acceptance.py || exit $?
python3 scripts/phase06_acceptance.py || exit $?
python3 -m unittest discover -s scripts/tests -p 'test_*.py' || exit $?

if [[ "$MODE" == "--static" ]]; then
  printf 'Final source-only acceptance checks passed. Elixir/PostgreSQL/browser/PDF runtime gates were not run.\n'
  exit 0
fi

if ! command -v mix >/dev/null 2>&1; then
  printf 'mix is required for --runtime; runtime gates were not run.\n' >&2
  exit 3
fi

mix ci || exit $?

for package in fount fount_observe fount_intelligence fount_workshop fount_run; do
  (
    cd "packages/$package" || exit 2
    FOUNT_PACKAGE_BUILD=1 mix hex.build
  ) || exit $?
done

if [[ -n "${FOUNT_DATABASE_URL:-}" ]]; then
  (
    cd packages/fount || exit 2
    MIX_ENV=test mix ecto.migrate
    MIX_ENV=test mix test integration
  ) || exit $?
  (
    cd packages/fount_workshop || exit 2
    MIX_ENV=test mix test integration
  ) || exit $?
  (
    cd packages/fount_run || exit 2
    MIX_ENV=test mix test integration
  ) || exit $?
  (
    cd apps/fount_web || exit 2
    MIX_ENV=test mix fount_web.migrate
    MIX_ENV=test mix test integration
  ) || exit $?

  if command -v npm >/dev/null 2>&1; then
    (
      cd apps/fount_web/browser || exit 2
      npm install --package-lock-only --ignore-scripts --no-audit --no-fund
      npm ci
      npx playwright install chromium
    ) || exit $?
    scripts/run_phase06_browser.sh || exit $?
  else
    printf 'npm is unavailable; Phase 06 browser acceptance was NOT_RUN.\n' >&2
    exit 4
  fi
else
  printf 'FOUNT_DATABASE_URL is unset; PostgreSQL and browser integration tests were NOT_RUN.\n' >&2
  exit 4
fi

printf 'Final automated runtime ladder passed for the gates invoked.\n'
printf 'Authorized live-provider checks and optional human/domain studies remain separate explicit evidence.\n'
