#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MONGO_SECRET_FILE="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}/lab5-mongo.env"
export MONGO_HOST_PORT="${MONGO_HOST_PORT:-27018}"
# Keep PG credential handling from the previous HA lab; never place passwords in project.
if [[ -f "${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}/roles.env" && -z "${DB_URL:-}" ]]; then
  HA_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"
  set -a
  # shellcheck disable=SC1090
  source "$HA_DIR/roles.env"
  set +a
  export PGPASSWORD="$TICKET_ADMIN_PASSWORD"
  export PGSSLMODE=verify-full
  export PGSSLROOTCERT="$HA_DIR/tls/ca.crt"
  export DB_URL="host=localhost port=${TICKET_PROXY_PORT:-5436} dbname=ticket_platform user=ticket_admin sslmode=verify-full sslrootcert=$PGSSLROOTCERT"
fi
DB_URL="${DB_URL:-$("$ROOT_DIR/scripts/resolve_db_url.sh")}"; export DB_URL
mongo_env() {
  [[ -f "$MONGO_SECRET_FILE" ]] || { echo "Mongo secrets absent. Run ./scripts/lab5.sh init" >&2; return 2; }
  # shellcheck disable=SC1090
  source "$MONGO_SECRET_FILE"
  export MONGO_ROOT_USER MONGO_ROOT_PASSWORD MONGO_HOST_PORT
}
mongo_compose() { mongo_env; docker compose -f "$ROOT_DIR/docker-compose.lab5.yml" "$@"; }
run_mongo() {
  local file="$1"; mongo_env
  mongo_compose exec -T mongo mongosh --quiet \
    --username "$MONGO_ROOT_USER" --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin --file "/work/mongo/$file"
}
pg() { command -v psql >/dev/null || { echo 'psql is required' >&2; return 127; }; psql "$DB_URL" -X -v ON_ERROR_STOP=1 "$@"; }
