#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-$("$ROOT_DIR/scripts/resolve_db_url.sh")}"
EVENT_NAME="${EVENT_NAME:-Symphony Night}"
OUT_DIR="$ROOT_DIR/artifacts/locks"
A_LOG="$OUT_DIR/session_A.txt"
B_LOG="$OUT_DIR/session_B.txt"
DIAG_LOG="$OUT_DIR/diagnostics.txt"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

mkdir -p "$OUT_DIR"
rm -f "$A_LOG" "$B_LOG" "$DIAG_LOG"

EVENT_ID="$(
    psql "$DB_URL" -X -At -v ON_ERROR_STOP=1 -v event_name="$EVENT_NAME" <<'SQL'
SELECT id
FROM app.events
WHERE name = :'event_name'
ORDER BY id DESC
LIMIT 1;
SQL
)"

if [[ -z "$EVENT_ID" ]]; then
    echo "ERROR: event '$EVENT_NAME' not found. Run seed data first." >&2
    exit 1
fi

PGAPPNAME="ticket-lock-A" psql "$DB_URL" -X -v ON_ERROR_STOP=1 -v event_id="$EVENT_ID" <<'SQL' >"$A_LOG" 2>&1 &
BEGIN;
SELECT id FROM app.events WHERE id = :event_id::bigint FOR UPDATE;
SELECT pg_sleep(5);
COMMIT;
SQL
A_PID=$!

sleep 0.5

PGAPPNAME="ticket-lock-B" psql "$DB_URL" -X -v ON_ERROR_STOP=1 -v event_id="$EVENT_ID" <<'SQL' >"$B_LOG" 2>&1 &
SELECT 1;
BEGIN;
SELECT id FROM app.events WHERE id = :event_id::bigint FOR UPDATE;
COMMIT;
SQL
B_PID=$!

printf 'Lock diagnostics started for event_id=%s (%s)\n' "$EVENT_ID" "$EVENT_NAME" > "$DIAG_LOG"
printf 'timestamp|pid|application|state|wait_type|wait_event|blocking_pids\n' >> "$DIAG_LOG"

for _ in $(seq 1 15); do
    psql "$DB_URL" -X -At -F '|' -v ON_ERROR_STOP=1 <<'SQL' >> "$DIAG_LOG"
SELECT
    clock_timestamp(),
    a.pid,
    a.application_name,
    a.state,
    COALESCE(a.wait_event_type, ''),
    COALESCE(a.wait_event, ''),
    pg_blocking_pids(a.pid)
FROM pg_stat_activity a
WHERE a.application_name IN ('ticket-lock-A', 'ticket-lock-B')
ORDER BY a.pid;
SQL
    sleep 0.3
done

printf '\npg_locks snapshot:\n' >> "$DIAG_LOG"
psql "$DB_URL" -X -At -F '|' -v ON_ERROR_STOP=1 <<'SQL' >> "$DIAG_LOG"
SELECT
    l.pid,
    l.locktype,
    l.mode,
    l.granted,
    COALESCE(l.relation::regclass::text, ''),
    pg_blocking_pids(l.pid)
FROM pg_locks l
WHERE l.pid IN (
    SELECT pid
    FROM pg_stat_activity
    WHERE application_name IN ('ticket-lock-A', 'ticket-lock-B')
)
ORDER BY l.pid, l.granted, l.locktype, l.mode;
SQL

wait "$A_PID"
wait "$B_PID"

printf '\n--- Session A ---\n' >> "$DIAG_LOG"
cat "$A_LOG" >> "$DIAG_LOG"
printf '\n--- Session B ---\n' >> "$DIAG_LOG"
cat "$B_LOG" >> "$DIAG_LOG"

if grep -q '|Lock|' "$DIAG_LOG"; then
    echo "PASS: waiting session observed with wait_event_type=Lock."
elif grep -Eq '\{[0-9]+\}' "$DIAG_LOG"; then
    echo "PASS: non-empty pg_blocking_pids() observed."
else
    echo "WARNING: diagnostic snapshot did not capture a blocked state; inspect $DIAG_LOG" >&2
fi

echo "Diagnostics: $DIAG_LOG"
