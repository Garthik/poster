#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}"
BASE_NO_DB="${BASE_URL%/*}"
STAMP="$(date +%s)_$$"
CLEAN_DB="ticket_platform_clean_${STAMP}"
UPGRADE_DB="ticket_platform_upgrade_${STAMP}"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

cleanup() {
    psql "$BASE_NO_DB/postgres" -v ON_ERROR_STOP=1 -q <<SQL >/dev/null
SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
 WHERE datname IN ('$CLEAN_DB', '$UPGRADE_DB')
   AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS $CLEAN_DB;
DROP DATABASE IF EXISTS $UPGRADE_DB;
SQL
}
trap cleanup EXIT

printf '\n==> Creating clean-install database\n'
psql "$BASE_NO_DB/postgres" -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE $CLEAN_DB"

printf '\n==> Running all migrations on clean database\n'
CLEAN_URL="$BASE_NO_DB/$CLEAN_DB"
DB_URL="$CLEAN_URL" "$ROOT_DIR/scripts/migrate.sh"
DB_URL="$CLEAN_URL" psql "$CLEAN_URL" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/seeds/002_seed_data.sql"
DB_URL="$CLEAN_URL" "$ROOT_DIR/scripts/run_tests.sh"

printf '\n==> Verifying migration idempotency on clean-install database\n'
DB_URL="$CLEAN_URL" "$ROOT_DIR/scripts/migrate.sh"

printf '\n==> Creating previous-version database\n'
psql "$BASE_NO_DB/postgres" -v ON_ERROR_STOP=1 -q -c "CREATE DATABASE $UPGRADE_DB"
UPGRADE_URL="$BASE_NO_DB/$UPGRADE_DB"

printf '\n==> Installing v1 only\n'
DB_URL="$UPGRADE_URL" "$ROOT_DIR/scripts/migrate.sh" --target 001_init

printf '\n==> Verifying v1 state\n'
psql "$UPGRADE_URL" -v ON_ERROR_STOP=1 -q <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM app.schema_migrations WHERE version = '001_init'
    ) THEN
        RAISE EXCEPTION '001_init is not installed';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM app.schema_migrations
        WHERE version = '002_event_description'
    ) THEN
        RAISE EXCEPTION '002_event_description must not be installed in v1';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'app'
          AND table_name = 'events'
          AND column_name = 'description'
    ) THEN
        RAISE EXCEPTION 'events.description must not exist in v1';
    END IF;
END
$$;
SQL

printf '\n==> Applying upgrade v1 -> v2\n'
DB_URL="$UPGRADE_URL" "$ROOT_DIR/scripts/migrate.sh"

printf '\n==> Verifying v2 state\n'
psql "$UPGRADE_URL" -v ON_ERROR_STOP=1 -q <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM app.schema_migrations WHERE version = '001_init'
    ) THEN
        RAISE EXCEPTION '001_init disappeared after upgrade';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app.schema_migrations WHERE version = '002_event_description'
    ) THEN
        RAISE EXCEPTION '002_event_description was not installed';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'app'
          AND table_name = 'events'
          AND column_name = 'description'
    ) THEN
        RAISE EXCEPTION 'events.description is missing after upgrade';
    END IF;
END
$$;
SQL

printf '\n==> Loading seed and running tests after upgrade\n'
DB_URL="$UPGRADE_URL" psql "$UPGRADE_URL" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/seeds/002_seed_data.sql"
EXPECTED_MIGRATION=002_event_description DB_URL="$UPGRADE_URL" "$ROOT_DIR/scripts/run_tests.sh"

printf '\n==> Verifying migration idempotency after upgrade\n'
EXPECTED_MIGRATION=002_event_description DB_URL="$UPGRADE_URL" "$ROOT_DIR/scripts/migrate.sh"

COUNT=$(psql "$UPGRADE_URL" -Atqc "SELECT count(*) FROM app.schema_migrations;" )
if [[ "$COUNT" != "2" ]]; then
    echo "ERROR: expected exactly 2 applied migrations after idempotent rerun, got $COUNT" >&2
    exit 1
fi

echo
echo "PASS: clean install and v1 -> v2 upgrade checks passed."
