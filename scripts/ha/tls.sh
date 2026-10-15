#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
secure="$(psql_node proxy ticket_app "$TICKET_APP_PASSWORD" -Atqc 'SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()')"
[[ "$secure" == t ]] || { echo 'FAIL: connection is not encrypted' >&2; exit 1; }
echo 'PASS: verified TLS connection (sslmode=verify-full)'
# sslmode=disable must be rejected by pg_hba on the active PostgreSQL server.
if PGSSLMODE=disable PGSSLROOTCERT= PGPASSWORD="$TICKET_APP_PASSWORD" \
   psql -X -h localhost -p "${TICKET_PROXY_PORT:-5436}" -U ticket_app -d ticket_platform \
     -Atqc 'SELECT 1' >/dev/null 2>&1; then
  echo >&2 'FAIL: unencrypted TCP connection was accepted'; exit 1
fi
echo 'PASS: unencrypted TCP connection refused by pg_hba.conf'
