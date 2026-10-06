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
        echo "  SEED=123 $0 development  # 75,000 rows" >&2
        echo "  SEED=123 $0 load         # 3,000,000 rows" >&2
        exit 2
        ;;
esac

if ! [[ "$SEED" =~ ^[0-9]+$ ]]; then
    echo "ERROR: SEED must be a non-negative integer" >&2
    exit 2
fi

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

export PGCLIENTENCODING=UTF8

printf 'Generating %s dataset: %s rows in app.ticket_scans, seed=%s\n' "$MODE" "$ROWS" "$SEED"

psql "$DB_URL" -v ON_ERROR_STOP=1 -v seed="$SEED" -v rows="$ROWS" -v mode="$MODE" <<'SQL'
BEGIN;
SET LOCAL synchronous_commit = off;

SELECT set_config('app.generator_seed', :'seed', false);
SELECT set_config('app.generator_rows', :'rows', false);
SELECT set_config('app.generator_mode', :'mode', false);

DO $generator$
DECLARE
    v_seed BIGINT := current_setting('app.generator_seed')::BIGINT;
    v_rows BIGINT := current_setting('app.generator_rows')::BIGINT;
    v_mode TEXT := current_setting('app.generator_mode');

    v_controller_id BIGINT;
    v_organizer_id BIGINT;
    v_buyer_id BIGINT;
    v_venue_id BIGINT;
    v_event_id BIGINT;
    v_category_id BIGINT;
    v_order_id BIGINT;
    v_item_id BIGINT;
    v_ticket_id BIGINT;
    v_popular_event_id BIGINT;
    v_popular_category_id BIGINT;
    v_popular_start TIMESTAMPTZ;
    v_ticket_ids BIGINT[];

    v_event_name TEXT;
    v_status TEXT;
    v_order_status TEXT;
    v_ticket_status TEXT;
    v_base_time TIMESTAMPTZ := '2027-10-01 18:00:00+03';
    v_starts_at TIMESTAMPTZ;
    v_created_at TIMESTAMPTZ;
    i INTEGER;

    v_statuses TEXT[] := ARRAY[
        'published',
        'published',
        'completed',
        'canceled',
        'draft'
    ];
    v_day_offsets INTEGER[] := ARRAY[7, 60, -60, 30, 90];
    v_quotas INTEGER[] := ARRAY[20, 5, 20, 5, 10];
    v_kinds TEXT[] := ARRAY[
        'popular',
        'rare',
        'completed',
        'canceled',
        'draft'
    ];
BEGIN
    SELECT id INTO v_controller_id
      FROM app.users
     WHERE role = 'controller'
     ORDER BY id
     LIMIT 1;

    SELECT id INTO v_organizer_id
      FROM app.users
     WHERE role = 'organizer'
     ORDER BY id
     LIMIT 1;

    SELECT id INTO v_buyer_id
      FROM app.users
     WHERE role = 'buyer'
     ORDER BY id
     LIMIT 1;

    SELECT id INTO v_venue_id
      FROM app.venues
     ORDER BY id
     LIMIT 1;

    IF v_controller_id IS NULL OR v_organizer_id IS NULL
       OR v_buyer_id IS NULL OR v_venue_id IS NULL THEN
        RAISE EXCEPTION 'Required seed fixtures are missing. Run seeds/002_seed_data.sql first.';
    END IF;

    -- Удаляем предыдущий набор с теми же MODE + SEED.
    DELETE FROM app.ticket_scans
     WHERE ticket_id IN (
         SELECT t.id
           FROM app.tickets t
           JOIN app.order_items oi ON oi.id = t.order_item_id
           JOIN app.orders o ON o.id = oi.order_id
           JOIN app.events e ON e.id = o.event_id
          WHERE e.name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed)
     );

    DELETE FROM app.refunds
     WHERE ticket_id IN (
         SELECT t.id
           FROM app.tickets t
           JOIN app.order_items oi ON oi.id = t.order_item_id
           JOIN app.orders o ON o.id = oi.order_id
           JOIN app.events e ON e.id = o.event_id
          WHERE e.name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed)
     );

    DELETE FROM app.payments
     WHERE order_id IN (
         SELECT o.id
           FROM app.orders o
           JOIN app.events e ON e.id = o.event_id
          WHERE e.name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed)
     );

    DELETE FROM app.tickets
     WHERE order_item_id IN (
         SELECT oi.id
           FROM app.order_items oi
           JOIN app.orders o ON o.id = oi.order_id
           JOIN app.events e ON e.id = o.event_id
          WHERE e.name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed)
     );

    DELETE FROM app.order_items
     WHERE order_id IN (
         SELECT o.id
           FROM app.orders o
           JOIN app.events e ON e.id = o.event_id
          WHERE e.name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed)
     );

    DELETE FROM app.orders
     WHERE event_id IN (
         SELECT id
           FROM app.events
          WHERE name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed)
     );

    DELETE FROM app.event_seats
     WHERE event_id IN (
         SELECT id
           FROM app.events
          WHERE name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed)
     );

    DELETE FROM app.ticket_categories
     WHERE event_id IN (
         SELECT id
           FROM app.events
          WHERE name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed)
     );

    DELETE FROM app.events
     WHERE name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed);

    -- Создаём пять событий с разными статусами, датами и квотами.
    FOR i IN 1..5 LOOP
        v_event_name := format(
            'Generated %s dataset seed=%s %s event',
            v_mode,
            v_seed,
            v_kinds[i]
        );
        v_starts_at := v_base_time + make_interval(days => v_day_offsets[i]);
        v_status := v_statuses[i];

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
            v_starts_at,
            v_starts_at + interval '4 hours',
            v_status,
            CASE WHEN v_status = 'draft' THEN NULL ELSE v_starts_at - interval '14 days' END,
            format(
                'Generated dataset: mode=%s, seed=%s, kind=%s',
                v_mode,
                v_seed,
                v_kinds[i]
            )
        )
        RETURNING id INTO v_event_id;

        INSERT INTO app.ticket_categories (
            event_id,
            name,
            type,
            price,
            quota
        )
        VALUES (
            v_event_id,
            CASE WHEN i = 1 THEN 'Popular zone' ELSE 'General zone' END,
            'zone',
            CASE WHEN i = 1 THEN 100 ELSE 150 + i * 25 END,
            v_quotas[i]
        )
        RETURNING id INTO v_category_id;

        IF i = 1 THEN
            v_popular_event_id := v_event_id;
            v_popular_category_id := v_category_id;
            v_popular_start := v_starts_at;
        END IF;
    END LOOP;

    -- 20 заказов для popular event дают разные статусы и разные состояния билетов.
    FOR i IN 1..20 LOOP
        CASE
            WHEN i <= 12 THEN
                v_order_status := 'paid';
                v_ticket_status := 'valid';
            WHEN i <= 15 THEN
                v_order_status := 'pending_payment';
                v_ticket_status := 'reserved';
            WHEN i <= 17 THEN
                v_order_status := 'failed';
                v_ticket_status := 'expired';
            WHEN i <= 19 THEN
                v_order_status := 'created';
                v_ticket_status := 'reserved';
            ELSE
                v_order_status := 'refunded';
                v_ticket_status := 'valid';
        END CASE;

        v_created_at := v_popular_start - make_interval(days => 30 + i);

        INSERT INTO app.orders (
            user_id,
            event_id,
            status,
            subtotal_amount,
            platform_fee_amount,
            total_amount,
            created_at
        )
        VALUES (
            v_buyer_id,
            v_popular_event_id,
            v_order_status,
            100,
            10,
            110,
            v_created_at
        )
        RETURNING id INTO v_order_id;

        INSERT INTO app.order_items (
            order_id,
            event_id,
            category_id,
            seat_id,
            unit_price,
            created_at
        )
        VALUES (
            v_order_id,
            v_popular_event_id,
            v_popular_category_id,
            NULL,
            100,
            v_created_at
        )
        RETURNING id INTO v_item_id;

        INSERT INTO app.tickets (
            order_item_id,
            event_id,
            category_id,
            seat_id,
            qr_hash,
            status,
            reserved_until,
            issued_at,
            annulled_at
        )
        VALUES (
            v_item_id,
            v_popular_event_id,
            v_popular_category_id,
            NULL,
            digest(
                format('generated-v3:%s:%s:popular:%s', v_mode, v_seed, i),
                'sha256'
            ),
            v_ticket_status,
            CASE
                WHEN v_ticket_status = 'reserved' THEN v_popular_start + interval '1 day'
                ELSE NULL
            END,
            CASE
                WHEN v_ticket_status IN ('valid', 'annulled') THEN v_created_at + interval '1 hour'
                ELSE NULL
            END,
            NULL
        )
        RETURNING id INTO v_ticket_id;

        IF v_order_status IN ('paid', 'pending_payment', 'failed', 'refunded') THEN
            INSERT INTO app.payments (
                order_id,
                provider_payment_id,
                amount,
                currency,
                status,
                created_at,
                paid_at
            )
            VALUES (
                v_order_id,
                format('generated-%s-%s-payment-%s', v_mode, v_seed, i),
                110,
                'RUB',
                CASE
                    WHEN v_order_status = 'paid' THEN 'approved'
                    WHEN v_order_status = 'pending_payment' THEN 'pending'
                    WHEN v_order_status = 'failed' THEN 'declined'
                    ELSE 'refunded'
                END,
                v_created_at,
                CASE WHEN v_order_status IN ('paid', 'refunded') THEN v_created_at + interval '10 minutes' ELSE NULL END
            );
        END IF;

        IF v_order_status = 'refunded' THEN
            PERFORM app.refund_ticket(
                v_ticket_id,
                100,
                v_popular_start - interval '10 days',
                format('generated-%s-%s-refund-%s', v_mode, v_seed, i)
            );
        END IF;
    END LOOP;

    SELECT array_agg(t.id ORDER BY t.id)
      INTO v_ticket_ids
      FROM app.tickets t
     WHERE t.event_id = v_popular_event_id
       AND t.status = 'valid';

    IF cardinality(v_ticket_ids) <> 12 THEN
        RAISE EXCEPTION 'Expected 12 valid generated tickets, got %', cardinality(v_ticket_ids);
    END IF;

    -- 75k / 3M scan-логов. Распределение намеренно неравномерное:
    -- 60% ticket #1, 20% #2, 8% #3, 4% #4, 2% #5, остальные 6%.
    INSERT INTO app.ticket_scans (
        ticket_id,
        controller_id,
        scanned_at,
        result
    )
    SELECT
        v_ticket_ids[
            CASE
                WHEN mod(g, 100) < 60 THEN 1
                WHEN mod(g, 100) < 80 THEN 2
                WHEN mod(g, 100) < 88 THEN 3
                WHEN mod(g, 100) < 92 THEN 4
                WHEN mod(g, 100) < 94 THEN 5
                ELSE 6 + mod(g, 7)
            END
        ],
        v_controller_id,
        v_popular_start
            + ((mod(g - 1, 86400) - 43200) * interval '1 second'),
        CASE
            WHEN mod(g + v_seed, 100) < 3 THEN 'rejected'
            ELSE 'accepted'
        END
    FROM generate_series(1, v_rows) AS gs(g);

    -- Контрольные проверки генератора.
    IF (SELECT count(*) FROM app.ticket_scans s
        JOIN app.tickets t ON t.id = s.ticket_id
        WHERE t.event_id = v_popular_event_id) <> v_rows THEN
        RAISE EXCEPTION 'Generated ticket_scans count mismatch';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM app.ticket_scans s
        LEFT JOIN app.tickets t ON t.id = s.ticket_id
        WHERE s.controller_id <> v_controller_id
           OR t.id IS NULL
           OR t.event_id <> v_popular_event_id
    ) THEN
        RAISE EXCEPTION 'Generated ticket_scans contain invalid foreign-key references';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM app.events e
        WHERE e.name LIKE format('Generated %s dataset seed=%s %%', v_mode, v_seed)
          AND (e.status NOT IN ('published', 'completed', 'canceled', 'draft')
               OR e.ends_at <= e.starts_at)
    ) THEN
        RAISE EXCEPTION 'Generated events violate status/date business constraints';
    END IF;

    RAISE NOTICE 'Generated rows: %, seed: %, mode: %, popular_event_id: %',
        v_rows, v_seed, v_mode, v_popular_event_id;
END
$generator$;

COMMIT;

SELECT
    count(*) AS generated_scan_rows,
    count(*) FILTER (WHERE s.result = 'accepted') AS accepted_rows,
    count(*) FILTER (WHERE s.result = 'rejected') AS rejected_rows,
    min(s.scanned_at) AS first_scan,
    max(s.scanned_at) AS last_scan
FROM app.ticket_scans s
JOIN app.tickets t ON t.id = s.ticket_id
JOIN app.order_items oi ON oi.id = t.order_item_id
JOIN app.orders o ON o.id = oi.order_id
JOIN app.events e ON e.id = o.event_id
WHERE e.name = format('Generated %s dataset seed=%s popular event', :'mode', :'seed');
SQL
