#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}"
EXPECTED_MIGRATION="${EXPECTED_MIGRATION:-002_event_description}"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

psql "$DB_URL" -v ON_ERROR_STOP=1 -v expected_migration="$EXPECTED_MIGRATION" -f "$ROOT_DIR/tests/schema.sql"
