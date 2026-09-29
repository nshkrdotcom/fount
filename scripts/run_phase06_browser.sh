#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/apps/fount_web"
: "${FOUNT_DATABASE_URL:?FOUNT_DATABASE_URL is required}"

export MIX_ENV=test
export FOUNT_OWNER_ID="${FOUNT_OWNER_ID:-browser-owner}"
export FOUNT_OWNER_TOKEN="${FOUNT_OWNER_TOKEN:-browser-owner-token}"
export FOUNT_ARTIFACT_ROOT="${FOUNT_ARTIFACT_ROOT:-$ROOT/_artifacts/phase06-browser}"
export PHX_SERVER=true
export PORT="${PORT:-4011}"
export FOUNT_WEB_BASE_URL="${FOUNT_WEB_BASE_URL:-http://127.0.0.1:$PORT}"

mkdir -p "$FOUNT_ARTIFACT_ROOT"
cd "$APP"
mix fount_web.migrate
mix assets.build
mix phx.server >"$ROOT/_phase06_browser_server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT INT TERM

n=0
until curl -fsS "$FOUNT_WEB_BASE_URL/login" >/dev/null 2>&1; do
  n=$((n + 1))
  if [ "$n" -ge 60 ]; then
    cat "$ROOT/_phase06_browser_server.log" >&2 || true
    exit 1
  fi
  sleep 1
done

cd "$APP/browser"
npm ci
npx playwright test
