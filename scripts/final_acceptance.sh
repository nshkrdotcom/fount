#!/usr/bin/env bash
# Phase 16 acceptance runner. Source checks may run without Elixir; runtime mode requires Mix.
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
python3 -m unittest scripts.tests.test_phase_sixteen_source || exit $?

if [[ "$MODE" == "--static" ]]; then
  printf 'Phase 16 source-only acceptance checks passed. Runtime gates were not run.\n'
  exit 0
fi

if ! command -v mix >/dev/null 2>&1; then
  printf 'mix is required for --runtime; runtime gates were not run.\n' >&2
  exit 3
fi

mix ci || exit $?
python3 -m unittest discover -s scripts/tests -p 'test_*.py' || exit $?

for package in fount fount_observe fount_intelligence fount_workshop fount_run; do
  (
    cd "packages/$package" || exit 2
    FOUNT_PACKAGE_BUILD=1 mix hex.build
  ) || exit $?
done

if [[ -n "${FOUNT_DATABASE_URL:-}" ]]; then
  (
    cd packages/fount_workshop || exit 2
    MIX_ENV=test mix test integration
  ) || exit $?
  (
    cd packages/fount_run || exit 2
    MIX_ENV=test mix test integration
  ) || exit $?
else
  printf 'FOUNT_DATABASE_URL is unset; PostgreSQL integration tests were not run by this script.\n'
fi

printf 'Phase 16 automated runtime ladder passed for the gates actually invoked.\n'
printf 'Authorized live-provider checks and optional human/domain studies remain separate explicit evidence.\n'