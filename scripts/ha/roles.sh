#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
psql_node primary ticket_root "$POSTGRES_PASSWORD" \
  -v admin_pw="$TICKET_ADMIN_PASSWORD" \
  -v app_pw="$TICKET_APP_PASSWORD" \
  -v analyst_pw="$TICKET_ANALYST_PASSWORD" \
  -v repl_pw="$TICKET_REPLICATION_PASSWORD" \
  -f "$ROOT_DIR/infra/ha/roles.sql"
