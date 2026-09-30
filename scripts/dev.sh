#!/usr/bin/env bash
set -euo pipefail

help() {
  cat <<'HELP'
Fount local development

Usage: ./scripts/dev.sh [up|setup|start|help] [options]

  up       Set up dependencies, database and assets, then start Phoenix (default).
  setup    Set up development only; leave the server stopped.
  start    Compile and start the prepared development server in this terminal.
  help     Show this help. Also: -h, --help.

Options:
  --sdk-path PATH      System One SDK package directory containing mix.exs.
                       Defaults to ../system_one_sdk/packages/system_one_sdk.
  --database-url URL   PostgreSQL URL (default: local fount_dev, postgres/postgres).
  --port PORT         Local HTTP port (default: 4000).

Examples:
  ./scripts/dev.sh setup
  ./scripts/dev.sh start
  ./scripts/dev.sh up --port 4050
  ./scripts/dev.sh setup --sdk-path /path/to/system_one_sdk/packages/system_one_sdk

Run from any directory using this script's path. Requires Elixir/Mix, npm,
and a running PostgreSQL server. Setup creates the database if missing and
applies Core -> Run -> host migrations; it never drops or resets a database.
This launcher uses development mode and deterministic Sandbox providers.
Settings apply only to this script and its children, not your calling shell.
The server stays in the foreground; press Ctrl+C to stop it.
HELP
}

fail() { printf 'Error: %s\nRun %s --help for usage.\n' "$1" "$0" >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
action=up
if (($#)) && [[ $1 != -* ]]; then action=$1; shift; fi
sdk_path=${FOUNT_SYSTEM_ONE_SDK_PATH:-"$root/../system_one_sdk/packages/system_one_sdk"}
database_url=${FOUNT_DATABASE_URL:-ecto://postgres:postgres@localhost/fount_dev}
port=${PORT:-4000}
while (($#)); do
  case $1 in
    -h|--help) help; exit 0 ;;
    --sdk-path|--database-url|--port)
      option=$1
      (($# >= 2)) && [[ -n $2 ]] || fail "$option needs a value"
      case $option in
        --sdk-path) sdk_path=$2 ;;
        --database-url) database_url=$2 ;;
        --port) port=$2 ;;
      esac
      shift 2 ;;
    *) fail "Unknown option: $1" ;;
  esac
done
case $action in help) help; exit 0 ;; setup|start|up) ;; *) fail "Unknown command: $action" ;; esac
[[ $port =~ ^[0-9]{1,5}$ ]] || fail 'Port must be a number between 1 and 65535'
((10#$port >= 1 && 10#$port <= 65535)) || fail 'Port must be between 1 and 65535'
[[ -f $sdk_path/mix.exs ]] || fail 'SDK package not found. Use --sdk-path PATH to select the directory containing mix.exs.'
sdk_path=$(cd -- "$sdk_path" && pwd -P)
command -v mix >/dev/null || fail 'Elixir/Mix is missing from PATH. Install the project toolchain first.'
if [[ $action != start ]]; then
  command -v npm >/dev/null || fail 'npm is missing from PATH. Install Node.js/npm for development setup.'
fi

# Process-local build/runtime inputs. Never source this script into your shell.
export MIX_ENV=dev FOUNT_OBSERVE_MODE=sandbox
export FOUNT_SYSTEM_ONE_SDK_PATH="$sdk_path" FOUNT_DATABASE_URL="$database_url" PORT="$port"
unset FOUNT_PACKAGE_BUILD
app="$root/apps/fount_web"
cd -- "$app"
run() {
  local label=$1
  shift
  printf '\n%s\n' "$label"
  local result=0
  "$@" || result=$?
  if ((result)); then
    printf '\n%s failed (exit %s). Server was not started.\n' "$label" "$result" >&2
    if [[ $label == *database* ]]; then
      printf 'Check that PostgreSQL is running and use --database-url if its local connection differs.\n' >&2
    fi
    exit "$result"
  fi
}
printf 'Fount development | SDK: %s | port: %s | Sandbox analysis\n' "$sdk_path" "$port"
if [[ $action != start ]]; then
  run 'Fetching Elixir dependencies' mix deps.get
  run 'Creating development database if missing' mix ecto.create -r Fount.Repo
  run 'Migrating development database (Core -> Run -> host)' mix fount_web.migrate
  (cd -- "$root/packages/fount_workshop" && run 'Installing PDF renderer dependencies' npm ci)
  run 'Installing asset builder' mix assets.setup
  run 'Building browser assets' mix assets.build
fi
if [[ $action == setup ]]; then
  printf '\nSetup complete. Start Phoenix with: %s start\n' "$0"
  exit 0
fi
run 'Checking development compilation (run setup if dependencies are missing)' mix compile
printf '\nOpen http://127.0.0.1:%s/login\n' "$port"
if [[ ${FOUNT_OWNER_TOKEN:-fount-demo-owner-token} == fount-demo-owner-token ]]; then
  printf 'Local demo login token: fount-demo-owner-token\n'
else
  printf 'Login with your configured owner token.\n'
fi
printf 'Phoenix runs in this terminal. Ctrl+C stops it.\n\n'
exec mix phx.server
