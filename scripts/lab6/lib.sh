#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TICKET_SECRETS_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"
LAB6_PRIVATE="$TICKET_SECRETS_DIR/lab6"
LAB6_ARTIFACTS="$ROOT_DIR/artifacts/lab6"
mkdir -p "$LAB6_ARTIFACTS/logs"
compose() { docker compose -f "$ROOT_DIR/docker-compose.lab6.yml" "$@"; }
require_secrets() {
  local file
  for file in root-user root-password app-password rs-keyfile; do
    [[ -s "$LAB6_PRIVATE/$file" ]] || { echo 'Run bash scripts/lab6.sh init first' >&2; return 2; }
  done
}
runner() { require_secrets; compose run --rm -T --no-deps runner "$@" < /dev/null; }
snapshot() {
  compose ps -a > "$LAB6_ARTIFACTS/logs/compose-status.txt" 2>&1 || true
  compose logs --no-color --tail 250 mongo1 mongo2 mongo3 > "$LAB6_ARTIFACTS/logs/mongo.log" 2>&1 || true
}
