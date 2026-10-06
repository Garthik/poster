BEGIN;

DO $$
DECLARE
    v_events INTEGER;
    v_distinct_statuses INTEGER;
    v_min_year INTEGER;
    v_max_year INTEGER;
    v_order_statuses INTEGER;
    v_ticket_statuses INTEGER;
    v_currency_count INTEGER;
    v_whale_orders BIGINT;
    v_median_orders NUMERIC;
    v_bad_fk BIGINT;
    v_bad_quota BIGINT;
    v_max_ratio NUMERIC;
BEGIN
    SELECT count(*)
      INTO v_events
      FROM app.events
     WHERE name IN (
         'Past Rock Festival 2023',
         'Jazz Night 2024',
         'Super Star Live 2027',
         'Jazz Evening 2027',
         'Indie Concert 2028',
         'Underground Gig Canceled',
         'Secret Draft Event'
     );

    IF v_events < 7 THEN
        RAISE EXCEPTION 'Stress dataset is incomplete: expected 7 named events, got %', v_events;
    END IF;

    SELECT count(DISTINCT status)
      INTO v_distinct_statuses
      FROM app.events
     WHERE name IN (
         'Past Rock Festival 2023',
         'Jazz Night 2024',
         'Super Star Live 2027',
         'Jazz Evening 2027',
         'Indie Concert 2028',
         'Underground Gig Canceled',
         'Secret Draft Event'
     );

    IF v_distinct_statuses < 4 THEN
        RAISE EXCEPTION 'Insufficient event status diversity: %', v_distinct_statuses;
    END IF;

    SELECT extract(year FROM min(starts_at))::integer,
           extract(year FROM max(starts_at))::integer
      INTO v_min_year, v_max_year
      FROM app.events
     WHERE name IN (
         'Past Rock Festival 2023',
         'Jazz Night 2024',
         'Super Star Live 2027',
         'Jazz Evening 2027',
         'Indie Concert 2028',
         'Underground Gig Canceled',
         'Secret Draft Event'
     );

    IF v_min_year <> 2023 OR v_max_year <> 2028 THEN
        RAISE EXCEPTION 'Unexpected event date range: %..%', v_min_year, v_max_year;
    END IF;

    SELECT count(DISTINCT status)
      INTO v_order_statuses
      FROM app.orders o
      JOIN app.users u ON u.id = o.user_id
     WHERE u.email LIKE 'regular_%@example.com'
        OR u.email LIKE 'longtail_%@example.com'
        OR u.email = 'whale@example.com';

    IF v_order_statuses < 3 THEN
        RAISE EXCEPTION 'Insufficient order status diversity: %', v_order_statuses;
    END IF;

    SELECT count(DISTINCT t.status)
      INTO v_ticket_statuses
      FROM app.tickets t
      JOIN app.order_items oi ON oi.id = t.order_item_id
      JOIN app.orders o ON o.id = oi.order_id
      JOIN app.users u ON u.id = o.user_id
     WHERE u.email LIKE 'regular_%@example.com'
        OR u.email LIKE 'longtail_%@example.com'
        OR u.email = 'whale@example.com';

    IF v_ticket_statuses < 3 THEN
        RAISE EXCEPTION 'Insufficient ticket status diversity: %', v_ticket_statuses;
    END IF;

    SELECT count(DISTINCT p.currency)
      INTO v_currency_count
      FROM app.payments p
      JOIN app.orders o ON o.id = p.order_id
      JOIN app.users u ON u.id = o.user_id
     WHERE u.email LIKE 'longtail_%@example.com'
        OR u.email = 'whale@example.com';

    IF v_currency_count < 2 THEN
        RAISE EXCEPTION 'Rare currency values are missing: %', v_currency_count;
    END IF;

    SELECT count(*)
      INTO v_bad_fk
      FROM app.order_items oi
      JOIN app.orders o ON o.id = oi.order_id
      LEFT JOIN app.ticket_categories tc
        ON tc.id = oi.category_id
       AND tc.event_id = oi.event_id
     WHERE (oi.event_id <> o.event_id OR tc.id IS NULL)
       AND (o.user_id IN (
           SELECT id FROM app.users
            WHERE email LIKE 'regular_%@example.com'
               OR email LIKE 'longtail_%@example.com'
               OR email = 'whale@example.com'
       ));

    IF v_bad_fk <> 0 THEN
        RAISE EXCEPTION 'Found % order_items with inconsistent order/category/event references', v_bad_fk;
    END IF;

    SELECT count(*)
      INTO v_bad_quota
      FROM (
          SELECT tc.id
          FROM app.ticket_categories tc
          LEFT JOIN app.tickets t
            ON t.category_id = tc.id
           AND t.event_id = tc.event_id
           AND t.status IN ('reserved', 'valid', 'scanned')
          GROUP BY tc.id, tc.quota
          HAVING count(t.id) > tc.quota
      ) violations;

    IF v_bad_quota <> 0 THEN
        RAISE EXCEPTION 'Found % ticket categories with active ticket count above quota', v_bad_quota;
    END IF;

    SELECT count(*)
      INTO v_bad_fk
      FROM app.tickets t
      JOIN app.order_items oi ON oi.id = t.order_item_id
      LEFT JOIN app.ticket_categories tc
        ON tc.id = t.category_id
       AND tc.event_id = t.event_id
     WHERE tc.id IS NULL
       AND oi.order_id IN (
           SELECT o.id
           FROM app.orders o
           JOIN app.users u ON u.id = o.user_id
           WHERE u.email LIKE 'regular_%@example.com'
              OR u.email LIKE 'longtail_%@example.com'
              OR u.email = 'whale@example.com'
       );

    IF v_bad_fk <> 0 THEN
        RAISE EXCEPTION 'Found % tickets with inconsistent category/event references', v_bad_fk;
    END IF;

    SELECT count(*)
      INTO v_bad_fk
      FROM app.ticket_scans s
      LEFT JOIN app.tickets t ON t.id = s.ticket_id
      LEFT JOIN app.users u ON u.id = s.controller_id
     WHERE t.id IS NULL OR u.role <> 'controller';

    IF v_bad_fk <> 0 THEN
        RAISE EXCEPTION 'Found % ticket_scans with invalid ticket/controller references', v_bad_fk;
    END IF;

    SELECT count(*)
      INTO v_whale_orders
      FROM app.orders o
      JOIN app.users u ON u.id = o.user_id
     WHERE u.email = 'whale@example.com';

    SELECT percentile_cont(0.5)
           WITHIN GROUP (ORDER BY buyer_orders)
      INTO v_median_orders
      FROM (
          SELECT u.id, count(o.id)::numeric AS buyer_orders
          FROM app.users u
          JOIN app.orders o ON o.user_id = u.id
          WHERE u.role = 'buyer'
          GROUP BY u.id
      ) q;

    v_max_ratio := v_whale_orders / NULLIF(v_median_orders, 0);
    IF v_max_ratio < 5 THEN
        RAISE EXCEPTION 'Distribution is too uniform: whale/median ratio = %', v_max_ratio;
    END IF;

    RAISE NOTICE 'PASS: stress distribution has diverse dates/statuses, valid references, quota safety and skewed popularity.';
END $$;

ROLLBACK;