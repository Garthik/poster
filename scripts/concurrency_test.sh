#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-$("$ROOT_DIR/scripts/resolve_db_url.sh")}"
EVENT_NAME="Concurrency Demo Event"
OUT_DIR="$ROOT_DIR/artifacts/business"
A_LOG="$OUT_DIR/concurrency_session_A.txt"
B_LOG="$OUT_DIR/concurrency_session_B.txt"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

mkdir -p "$OUT_DIR"

psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
DO $cleanup$
DECLARE
    v_event_id BIGINT;
BEGIN
    FOR v_event_id IN SELECT id FROM app.events WHERE name = 'Concurrency Demo Event'
    LOOP
        DELETE FROM app.ticket_scans
        WHERE ticket_id IN (
            SELECT t.id FROM app.tickets t
            JOIN app.order_items oi ON oi.id=t.order_item_id
            JOIN app.orders o ON o.id=oi.order_id
            WHERE o.event_id=v_event_id
        );
        DELETE FROM app.refunds
        WHERE ticket_id IN (
            SELECT t.id FROM app.tickets t
            JOIN app.order_items oi ON oi.id=t.order_item_id
            JOIN app.orders o ON o.id=oi.order_id
            WHERE o.event_id=v_event_id
        );
        DELETE FROM app.payments WHERE order_id IN (SELECT id FROM app.orders WHERE event_id=v_event_id);
        DELETE FROM app.tickets
        WHERE order_item_id IN (
            SELECT id FROM app.order_items WHERE order_id IN (SELECT id FROM app.orders WHERE event_id=v_event_id)
        );
        DELETE FROM app.order_items WHERE order_id IN (SELECT id FROM app.orders WHERE event_id=v_event_id);
        DELETE FROM app.orders WHERE event_id=v_event_id;
        DELETE FROM app.event_seats WHERE event_id=v_event_id;
        DELETE FROM app.ticket_categories WHERE event_id=v_event_id;
        DELETE FROM app.events WHERE id=v_event_id;
    END LOOP;
END
$cleanup$;

DO $setup$
DECLARE
    v_organizer_id BIGINT;
    v_buyer_id BIGINT;
    v_venue_id BIGINT;
    v_event_id BIGINT;
    v_category_id BIGINT;
    v_order_id BIGINT;
BEGIN
    SELECT id INTO v_organizer_id FROM app.users WHERE email='organizer@example.com';
    SELECT id INTO v_buyer_id FROM app.users WHERE email='buyer@example.com';
    SELECT id INTO v_venue_id FROM app.venues ORDER BY id LIMIT 1;

    INSERT INTO app.events (
        organizer_id, venue_id, name, starts_at, ends_at, status
    )
    VALUES (
        v_organizer_id, v_venue_id, 'Concurrency Demo Event',
        '2027-11-24 18:00:00+03', '2027-11-24 22:00:00+03', 'draft'
    )
    RETURNING id INTO v_event_id;

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_event_id, 'Quota One', 'zone', 100, 1)
    RETURNING id INTO v_category_id;

    PERFORM app.publish_event(v_event_id);

    INSERT INTO app.orders (user_id, event_id, status, subtotal_amount, platform_fee_amount, total_amount)
    VALUES (v_buyer_id, v_event_id, 'pending_payment', 100, 10, 110)
    RETURNING id INTO v_order_id;

    INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
    VALUES (v_order_id, v_event_id, v_category_id, 100);

    INSERT INTO app.orders (user_id, event_id, status, subtotal_amount, platform_fee_amount, total_amount)
    VALUES (v_buyer_id, v_event_id, 'pending_payment', 100, 10, 110)
    RETURNING id INTO v_order_id;

    INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
    VALUES (v_order_id, v_event_id, v_category_id, 100);
END
$setup$;
SQL

read -r CATEGORY_ID ITEM1_ID ITEM2_ID < <(
    psql "$DB_URL" -X -At -F ' ' -v ON_ERROR_STOP=1 -v event_name="$EVENT_NAME" <<'SQL'
SELECT
    c.id,
    MIN(oi.id) FILTER (WHERE o.id = ids.min_order_id),
    MAX(oi.id) FILTER (WHERE o.id = ids.max_order_id)
FROM app.events e
JOIN app.ticket_categories c ON c.event_id=e.id
JOIN app.orders o ON o.event_id=e.id
JOIN app.order_items oi ON oi.order_id=o.id
CROSS JOIN LATERAL (
    SELECT MIN(id) AS min_order_id, MAX(id) AS max_order_id
    FROM app.orders
    WHERE event_id=e.id
) ids
WHERE e.name=:'event_name'
GROUP BY c.id;
SQL
)

if [[ -z "${CATEGORY_ID:-}" || -z "${ITEM1_ID:-}" || -z "${ITEM2_ID:-}" ]]; then
    echo "ERROR: concurrency fixtures were not created" >&2
    exit 1
fi

PGAPPNAME="ticket-concurrency-A" psql "$DB_URL" -X -v ON_ERROR_STOP=1 \
    -v item_id="$ITEM1_ID" <<'SQL' >"$A_LOG" 2>&1 &
BEGIN;
SELECT app.reserve_zone_ticket(:item_id::bigint, digest('concurrency-A', 'sha256'), now() + interval '1 hour');
SELECT pg_sleep(3);
COMMIT;
SQL
A_PID=$!

sleep 0.4

PGAPPNAME="ticket-concurrency-B" psql "$DB_URL" -X -v ON_ERROR_STOP=1 \
    -v item_id="$ITEM2_ID" <<'SQL' >"$B_LOG" 2>&1
BEGIN;
SELECT set_config('app.concurrency_item_id', :'item_id', true);
DO $test$
DECLARE
    v_item_id BIGINT := current_setting('app.concurrency_item_id')::BIGINT;
BEGIN
    BEGIN
        PERFORM app.reserve_zone_ticket(v_item_id, digest('concurrency-B', 'sha256'), now() + interval '1 hour');
        RAISE EXCEPTION 'UNEXPECTED_SECOND_RESERVATION';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'Expected quota conflict: second reservation rejected';
    END;
END
$test$;
COMMIT;
SQL
B_STATUS=$?

wait "$A_PID"

ACTIVE_TICKETS="$(
    psql "$DB_URL" -X -At -v ON_ERROR_STOP=1 -v category_id="$CATEGORY_ID" <<'SQL'
SELECT count(*)
FROM app.tickets
WHERE category_id = :'category_id'::bigint
  AND status IN ('reserved','valid','scanned');
SQL
)"

printf 'category_id=%s\nitem1_id=%s\nitem2_id=%s\n' "$CATEGORY_ID" "$ITEM1_ID" "$ITEM2_ID"
printf 'session_B_exit=%s\nactive_tickets=%s\n' "$B_STATUS" "$ACTIVE_TICKETS"

if [[ "$B_STATUS" -ne 0 ]]; then
    echo "ERROR: session B failed unexpectedly" >&2
    cat "$B_LOG" >&2
    exit 1
fi

if [[ "$ACTIVE_TICKETS" -ne 1 ]]; then
    echo "ERROR: concurrent quota protection failed; expected exactly one active ticket" >&2
    exit 1
fi

if grep -q 'Expected quota conflict' "$B_LOG"; then
    echo "PASS: quota=1 protected against concurrent double reservation."
else
    echo "ERROR: expected quota conflict message was not observed" >&2
    cat "$B_LOG" >&2
    exit 1
fi

printf 'Session A log: %s\nSession B log: %s\n' "$A_LOG" "$B_LOG"
