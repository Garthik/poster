#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[[ $# -gt 0 ]] || { echo 'Usage: ./scripts/ha.sh app COMMAND [args]' >&2; exit 2; }
export PGPASSWORD="$TICKET_APP_PASSWORD"
export DB_URL="host=localhost port=${TICKET_PROXY_PORT:-5436} dbname=ticket_platform user=ticket_app sslmode=verify-full sslrootcert=$PGSSLROOTCERT"
exec "$@"
