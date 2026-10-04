#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}"
MODE="${1:-development}"
SEED="${SEED:-20261004}"

case "$MODE" in
    development)
        ROWS=75000
        ;;

    load)
        ROWS=3000000
        ;;

    *)
        echo "Usage: $0 {development|load}" >&2
        echo
        echo "Examples:"
        echo "  SEED=123 $0 development"
        echo "  SEED=123 $0 load"
        exit 2
        ;;
esac

if ! [[ "$SEED" =~ ^[0-9]+$ ]]; then
    echo "ERROR: SEED must be a non-negative integer" >&2
    exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
    echo "ERROR: psql is required" >&2
    exit 127
fi

export PGCLIENTENCODING=UTF8

echo "=============================================="
echo "Ticket Platform data generator"
echo "=============================================="
echo "Mode: $MODE"
echo "Seed: $SEED"
echo "Rows: $ROWS"
echo "Database: $DB_URL"
echo

psql "$DB_URL" \
    -v ON_ERROR_STOP=1 \
    -v seed="$SEED" \
    -v rows="$ROWS" \
    -v mode="$MODE" <<'SQL'

BEGIN;

SET LOCAL synchronous_commit = off;

SELECT set_config('app.generator_seed', :'seed', false);
SELECT set_config('app.generator_rows', :'rows', false);
SELECT set_config('app.generator_mode', :'mode', false);

DO $generator$
DECLARE
    v_seed BIGINT;
    v_rows BIGINT;
    v_mode TEXT;

    v_event_id BIGINT;
    v_category_id BIGINT;
    v_order_id BIGINT;
    v_item_id BIGINT;

    v_controller_id BIGINT;
    v_organizer_id BIGINT;
    v_buyer_id BIGINT;
    v_venue_id BIGINT;

    v_ticket_ids BIGINT[];

    v_event_name TEXT;
    v_base_time TIMESTAMPTZ;

    i INTEGER;
BEGIN
    /*
     * Получаем параметры генерации.
     */
    v_seed := current_setting('app.generator_seed')::BIGINT;
    v_rows := current_setting('app.generator_rows')::BIGINT;
    v_mode := current_setting('app.generator_mode');

    v_event_name :=
        format(
            'Generated %s event (seed=%s)',
            v_mode,
            v_seed
        );

    v_base_time := '2027-10-01 18:00:00+03';

    /*
     * Находим существующих пользователей и площадку.
     */

    SELECT id
      INTO v_controller_id
      FROM app.users
     WHERE role = 'controller'
     ORDER BY id
     LIMIT 1;

    IF v_controller_id IS NULL THEN
        RAISE EXCEPTION
            'Controller user not found. Run seeds/002_seed_data.sql first.';
    END IF;

    SELECT id
      INTO v_organizer_id
      FROM app.users
     WHERE role = 'organizer'
     ORDER BY id
     LIMIT 1;

    IF v_organizer_id IS NULL THEN
        RAISE EXCEPTION
            'Organizer user not found. Run seeds/002_seed_data.sql first.';
    END IF;

    SELECT id
      INTO v_buyer_id
      FROM app.users
     WHERE role = 'buyer'
     ORDER BY id
     LIMIT 1;

    IF v_buyer_id IS NULL THEN
        RAISE EXCEPTION
            'Buyer user not found. Run seeds/002_seed_data.sql first.';
    END IF;

    SELECT id
      INTO v_venue_id
      FROM app.venues
     ORDER BY id
     LIMIT 1;

    IF v_venue_id IS NULL THEN
        RAISE EXCEPTION
            'Venue not found. Run seeds/002_seed_data.sql first.';
    END IF;

    /*
     * Удаляем предыдущий набор с тем же seed и режимом.
     */

    DELETE FROM app.ticket_scans
     WHERE ticket_id IN (
        SELECT t.id
          FROM app.tickets t
          JOIN app.order_items oi
            ON oi.id = t.order_item_id
          JOIN app.orders o
            ON o.id = oi.order_id
          JOIN app.events e
            ON e.id = o.event_id
         WHERE e.name = v_event_name
     );

    DELETE FROM app.refunds
     WHERE ticket_id IN (
        SELECT t.id
          FROM app.tickets t
          JOIN app.order_items oi
            ON oi.id = t.order_item_id
          JOIN app.orders o
            ON o.id = oi.order_id
          JOIN app.events e
            ON e.id = o.event_id
         WHERE e.name = v_event_name
     );

    DELETE FROM app.payments
     WHERE order_id IN (
        SELECT o.id
          FROM app.orders o
          JOIN app.events e
            ON e.id = o.event_id
         WHERE e.name = v_event_name
     );

    DELETE FROM app.tickets
     WHERE order_item_id IN (
        SELECT oi.id
          FROM app.order_items oi
          JOIN app.orders o
            ON o.id = oi.order_id
          JOIN app.events e
            ON e.id = o.event_id
         WHERE e.name = v_event_name
     );

    DELETE FROM app.order_items
     WHERE order_id IN (
        SELECT o.id
          FROM app.orders o
          JOIN app.events e
            ON e.id = o.event_id
         WHERE e.name = v_event_name
     );

    DELETE FROM app.orders
     WHERE event_id IN (
        SELECT id
          FROM app.events
         WHERE name = v_event_name
     );

    DELETE FROM app.event_seats
     WHERE event_id IN (
        SELECT id
          FROM app.events
         WHERE name = v_event_name
     );

    DELETE FROM app.ticket_categories
     WHERE event_id IN (
        SELECT id
          FROM app.events
         WHERE name = v_event_name
     );

    DELETE FROM app.events
     WHERE name = v_event_name;

    /*
     * Создаём тестовое мероприятие.
     */

    INSERT INTO app.events (
        organizer_id,
        venue_id,
        name,
        starts_at,
        ends_at,
        status,
        published_at,
        description
    )
    VALUES (
        v_organizer_id,
        v_venue_id,
        v_event_name,

        v_base_time
            + make_interval(
                days => (v_seed % 30)::INTEGER
            ),

        v_base_time
            + make_interval(
                days => (v_seed % 30)::INTEGER,
                hours => 4
            ),

        'published',

        v_base_time
            + make_interval(
                days => (v_seed % 30)::INTEGER
            ),

        format(
            'Deterministic generated dataset; seed=%s; mode=%s',
            v_seed,
            v_mode
        )
    )
    RETURNING id INTO v_event_id;

    /*
     * Создаём категорию билетов.
     */

    INSERT INTO app.ticket_categories (
        event_id,
        name,
        type,
        price,
        quota
    )
    VALUES (
        v_event_id,
        'Generated Scan Load',
        'zone',
        100.00,
        10
    )
    RETURNING id INTO v_category_id;

    /*
     * Создаём 10 заказов и 10 билетов.
     */

    FOR i IN 1..10 LOOP

        INSERT INTO app.orders (
            user_id,
            event_id,
            status,
            subtotal_amount,
            platform_fee_amount,
            total_amount
        )
        VALUES (
            v_buyer_id,
            v_event_id,
            'paid',
            100.00,
            10.00,
            110.00
        )
        RETURNING id INTO v_order_id;

        INSERT INTO app.order_items (
            order_id,
            event_id,
            category_id,
            seat_id,
            unit_price
        )
        VALUES (
            v_order_id,
            v_event_id,
            v_category_id,
            NULL,
            100.00
        )
        RETURNING id INTO v_item_id;

        INSERT INTO app.tickets (
            order_item_id,
            event_id,
            category_id,
            seat_id,
            qr_hash,
            status,
            issued_at
        )
        VALUES (
            v_item_id,
            v_event_id,
            v_category_id,
            NULL,
            digest(
                format(
                    'generated-v2:%s:%s:%s',
                    v_mode,
                    v_seed,
                    i
                ),
                'sha256'
            ),
            'valid',
            v_base_time
        );

    END LOOP;

    /*
     * Получаем созданные билеты.
     */

    SELECT array_agg(
               t.id
               ORDER BY t.id
           )
      INTO v_ticket_ids
      FROM app.tickets t
     WHERE t.event_id = v_event_id;

    IF cardinality(v_ticket_ids) <> 10 THEN
        RAISE EXCEPTION
            'Expected exactly 10 generated tickets, got %',
            cardinality(v_ticket_ids);
    END IF;

    /*
     * Генерация большого объёма записей ticket_scans.
     *
     * development = 75 000
     * load        = 3 000 000
     */

    INSERT INTO app.ticket_scans (
        ticket_id,
        controller_id,
        scanned_at,
        result
    )
    SELECT
        v_ticket_ids[
            ((g - 1) % 10) + 1
        ],

        v_controller_id,

        v_base_time
            + ((g - 1) * interval '1 second'),

        CASE
            WHEN mod(
                g + v_seed,
                20
            ) = 0
            THEN 'rejected'
            ELSE 'accepted'
        END

    FROM generate_series(
        1,
        v_rows
    ) AS generated(g);

    RAISE NOTICE
        'Generated % rows, seed=%, mode=%',
        v_rows,
        v_seed,
        v_mode;
END
$generator$;

COMMIT;

SELECT
    e.name AS generated_dataset,
    count(*) AS scan_rows,
    min(s.scanned_at) AS first_scan,
    max(s.scanned_at) AS last_scan
FROM app.ticket_scans s
JOIN app.tickets t
  ON t.id = s.ticket_id
JOIN app.order_items oi
  ON oi.id = t.order_item_id
JOIN app.orders o
  ON o.id = oi.order_id
JOIN app.events e
  ON e.id = o.event_id
WHERE e.name = format(
    'Generated %s event (seed=%s)',
    :'mode',
    :'seed'
)
GROUP BY e.name;

SQL