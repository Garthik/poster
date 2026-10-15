#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-$("$ROOT_DIR/scripts/resolve_db_url.sh")}"
SEED="${SEED:-20261004}"
MODE="${MODE:-load}"
EVENT_NAME="${EVENT_NAME:-Generated ${MODE} dataset seed=${SEED} popular event}"
MIN_REVENUE="${MIN_REVENUE:-500}"
MIN_ORDERS="${MIN_ORDERS:-5}"
EVENT_LIKE="${EVENT_LIKE:-$EVENT_NAME}"
OUT_DIR="$ROOT_DIR/artifacts/business"
PARAMS_FILE="$OUT_DIR/parameters.txt"
RESULT_FILE="$OUT_DIR/results.txt"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

mkdir -p "$OUT_DIR"

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
    echo "ERROR: event not found: $EVENT_NAME" >&2
    echo "Run the generator first or set EVENT_NAME explicitly." >&2
    exit 1
fi

IFS='|' read -r ORDER_FROM ORDER_TO < <(
    psql "$DB_URL" -X -At -F '|' -v ON_ERROR_STOP=1 -v event_id="$EVENT_ID" <<'SQL'
SELECT
    min(o.created_at - interval '1 hour'),
    max(o.created_at + interval '1 hour')
FROM app.orders o
WHERE o.event_id = :'event_id'::bigint;
SQL
)

IFS='|' read -r SCAN_FROM SCAN_TO < <(
    psql "$DB_URL" -X -At -F '|' -v ON_ERROR_STOP=1 -v event_id="$EVENT_ID" <<'SQL'
SELECT
    min(s.scanned_at),
    max(s.scanned_at) + interval '1 second'
FROM app.ticket_scans s
JOIN app.tickets t ON t.id = s.ticket_id
WHERE t.event_id = :'event_id'::bigint;
SQL
)

if [[ -z "${SCAN_FROM:-}" || -z "${SCAN_TO:-}" ]]; then
    echo "ERROR: no scan rows found for event $EVENT_ID. Run the generator first." >&2
    exit 1
fi

{
    printf 'event_name=%s\n' "$EVENT_NAME"
    printf 'event_id=%s\n' "$EVENT_ID"
    printf 'from_ts=%s\n' "$ORDER_FROM"
    printf 'to_ts=%s\n' "$ORDER_TO"
    printf 'scan_from=%s\n' "$SCAN_FROM"
    printf 'scan_to=%s\n' "$SCAN_TO"
    printf 'min_revenue=%s\n' "$MIN_REVENUE"
    printf 'min_orders=%s\n' "$MIN_ORDERS"
    printf 'event_like=%s\n' "$EVENT_LIKE"
} > "$PARAMS_FILE"

psql "$DB_URL" -X -v ON_ERROR_STOP=1 \
    -v event_id="$EVENT_ID" \
    -v from_ts="$ORDER_FROM" \
    -v to_ts="$ORDER_TO" \
    -v scan_from="$SCAN_FROM" \
    -v scan_to="$SCAN_TO" \
    -v min_revenue="$MIN_REVENUE" \
    -v min_orders="$MIN_ORDERS" \
    -v event_like="$EVENT_LIKE" \
    -f "$ROOT_DIR/queries/business_queries.sql" | tee "$RESULT_FILE"

echo
printf 'Business queries completed. Parameters: %s\n' "$PARAMS_FILE"
printf 'Results: %s\n' "$RESULT_FILE"
