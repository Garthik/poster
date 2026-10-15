#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export PGPASSWORD="$TICKET_ADMIN_PASSWORD"
export DB_URL="host=localhost port=${TICKET_PRIMARY_PORT:-5434} dbname=ticket_platform user=ticket_admin sslmode=verify-full sslrootcert=$PGSSLROOTCERT"
"$ROOT_DIR/scripts/migrate.sh"
psql_node primary ticket_admin "$TICKET_ADMIN_PASSWORD" -f "$ROOT_DIR/infra/ha/grants.sql"
echo 'Migrations and grants applied with nonsuperuser ticket_admin.'
