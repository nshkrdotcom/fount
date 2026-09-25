#!/usr/bin/env bash
# Local-only application verification. Not executed by the source-writing agent.
# Deliberately does not create/drop a database, render PDFs or contact a model.
set -u
set -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:---offline}" != "--offline" || $# -gt 1 ]]; then
  printf 'Usage: bash scripts/verify_handoff.sh [--offline]\n' >&2
  exit 2
fi
OUT="${FOUNT_VERIFY_OUT:-/tmp/fount-handoff-offline-$(date +%Y%m%dT%H%M%S)-$$}"
mkdir -p "$OUT"
printf 'package\tcheck\tstatus\texit_code\tlog\n' > "$OUT/status.tsv"
FAILED=0
run_check() {
  local package="$1" check="$2"
  shift 2
  local log="$OUT/${package}-${check}.log"
  printf '\n===== %s / %s =====\n' "$package" "$check"
  (
    cd "$ROOT/packages/$package" || exit 2
    unset SYSTEM_ONE_API_KEY FOUNT_DATABASE_URL FOUNT_CODEX_MODEL
    "$@"
  ) > "$log" 2>&1
  local code=$?
  local status=passed
  if [[ $code -ne 0 ]]; then status=failed; FAILED=1; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$package" "$check" "$status" "$code" "$log" >> "$OUT/status.tsv"
  tail -n 40 "$log"
}
for package in fount fount_probe fount_workshop; do
  run_check "$package" deps_get mix deps.get
  run_check "$package" format mix format --check-formatted
  run_check "$package" compile env MIX_ENV=test mix compile --warnings-as-errors
  run_check "$package" test env MIX_ENV=test mix test
done
printf '\nActual results: %s/status.tsv\n' "$OUT"
printf 'PostgreSQL, PDF, providers and speech were not requested by this offline script.\n'
exit "$FAILED"
