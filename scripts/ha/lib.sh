#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TICKET_SECRETS_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"
COMPOSE=(docker compose -f "$ROOT_DIR/docker-compose.ha.yml")
if [[ ! -f "$TICKET_SECRETS_DIR/primary.env" ]]; then
  echo "Missing secrets: run ./scripts/ha.sh init first" >&2
  exit 2
fi
# External credentials are not written to logs or command arguments.
set -a
# shellcheck disable=SC1091
source "$TICKET_SECRETS_DIR/primary.env"
source "$TICKET_SECRETS_DIR/roles.env"
set +a
export PGSSLMODE=verify-full
export PGSSLROOTCERT="$TICKET_SECRETS_DIR/tls/ca.crt"
export PGCONNECT_TIMEOUT=3
pghost() {
  case "$1" in
    primary) printf 'localhost %s\n' "${TICKET_PRIMARY_PORT:-5434}" ;;
    replica) printf 'localhost %s\n' "${TICKET_REPLICA_PORT:-5435}" ;;
    proxy)   printf 'localhost %s\n' "${TICKET_PROXY_PORT:-5436}" ;;
    restore) printf 'localhost %s\n' "${TICKET_RESTORE_PORT:-5437}" ;;
    *) echo "unknown node $1" >&2; return 2 ;;
  esac
}
psql_node() {
  local node="$1" username="$2" pass="$3"
  shift 3
  local h p
  read -r h p < <(pghost "$node")
  PGPASSWORD="$pass" psql -X -v ON_ERROR_STOP=1 \
    -h "$h" -p "$p" -U "$username" -d ticket_platform "$@"
}
