#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}"
EXPECTED_MIGRATION="${EXPECTED_MIGRATION:-002_event_description}"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

run_sql_test() {
    local name="$1"
    local file="$2"

    echo
    echo "==> $name"
    if [[ "$file" == "tests/schema.sql" ]]; then
        psql "$DB_URL" -v ON_ERROR_STOP=1 -v expected_migration="$EXPECTED_MIGRATION" -f "$ROOT_DIR/$file"
    else
        psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/$file"
    fi
    echo "PASS: $name"
}


run_sql_test "Schema structure and migration version" "tests/schema.sql"
run_sql_test "Integrity constraints / negative cases" "tests/constraints.sql"
run_sql_test "Business lifecycle scenarios" "tests/lifecycle.sql"

echo
echo "All PostgreSQL tests passed."
