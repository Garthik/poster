\set ON_ERROR_STOP on

\echo '==> Cleanup previous transaction demo rows'
DO $cleanup$
DECLARE
    v_event_id BIGINT;
BEGIN
    FOR v_event_id IN
        SELECT id
        FROM app.events
        WHERE name IN ('TX Demo Commit', 'TX Demo Rollback')
    LOOP
        DELETE FROM app.ticket_scans
        WHERE ticket_id IN (
            SELECT t.id
            FROM app.tickets t
            JOIN app.order_items oi ON oi.id = t.order_item_id
            JOIN app.orders o ON o.id = oi.order_id
            WHERE o.event_id = v_event_id
        );

        DELETE FROM app.refunds
        WHERE ticket_id IN (
            SELECT t.id
            FROM app.tickets t
            JOIN app.order_items oi ON oi.id = t.order_item_id
            JOIN app.orders o ON o.id = oi.order_id
            WHERE o.event_id = v_event_id
        );

        DELETE FROM app.payments
        WHERE order_id IN (SELECT id FROM app.orders WHERE event_id = v_event_id);

        DELETE FROM app.tickets
        WHERE order_item_id IN (
            SELECT id FROM app.order_items
            WHERE order_id IN (SELECT id FROM app.orders WHERE event_id = v_event_id)
        );

        DELETE FROM app.order_items
        WHERE order_id IN (SELECT id FROM app.orders WHERE event_id = v_event_id);

        DELETE FROM app.orders WHERE event_id = v_event_id;
        DELETE FROM app.event_seats WHERE event_id = v_event_id;
        DELETE FROM app.ticket_categories WHERE event_id = v_event_id;
        DELETE FROM app.events WHERE id = v_event_id;
    END LOOP;
END
$cleanup$;

\echo '==> Transaction 1: COMMIT'
BEGIN;
DO $commit_demo$
DECLARE
    v_organizer_id BIGINT;
    v_buyer_id BIGINT;
    v_venue_id BIGINT;
    v_event_id BIGINT;
    v_category_id BIGINT;
    v_order_id BIGINT;
    v_item_id BIGINT;
    v_ticket_id BIGINT;
BEGIN
    SELECT id INTO v_organizer_id FROM app.users WHERE email = 'organizer@example.com';
    SELECT id INTO v_buyer_id FROM app.users WHERE email = 'buyer@example.com';
    SELECT id INTO v_venue_id FROM app.venues ORDER BY id LIMIT 1;

    INSERT INTO app.events (
        organizer_id, venue_id, name, starts_at, ends_at, status, description
    )
    VALUES (
        v_organizer_id, v_venue_id, 'TX Demo Commit',
        '2027-11-10 18:00:00+03', '2027-11-10 22:00:00+03',
        'draft', 'Committed multi-table transaction demo'
    )
    RETURNING id INTO v_event_id;

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_event_id, 'TX Zone', 'zone', 100, 1)
    RETURNING id INTO v_category_id;

    PERFORM app.publish_event(v_event_id);

    INSERT INTO app.orders (
        user_id, event_id, status,
        subtotal_amount, platform_fee_amount, total_amount,
        created_at
    )
    VALUES (
        v_buyer_id, v_event_id, 'pending_payment',
        100, 10, 110,
        '2027-10-20 12:00:00+03'
    )
    RETURNING id INTO v_order_id;

    INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
    VALUES (v_order_id, v_event_id, v_category_id, 100)
    RETURNING id INTO v_item_id;

    SELECT app.reserve_zone_ticket(
        v_item_id,
        digest('tx-demo-commit-ticket', 'sha256'),
        '2027-11-10 19:00:00+03'
    ) INTO v_ticket_id;

    INSERT INTO app.payments (
        order_id, provider_payment_id, amount, currency, status
    )
    VALUES (
        v_order_id, 'tx-demo-commit-payment', 110, 'RUB', 'pending'
    );

    PERFORM app.pay_order(v_order_id);

    UPDATE app.payments
       SET status = 'approved',
           paid_at = '2027-10-20 12:10:00+03'
     WHERE order_id = v_order_id;

    RAISE NOTICE 'COMMIT demo created event_id=%, order_id=%, ticket_id=%',
        v_event_id, v_order_id, v_ticket_id;
END
$commit_demo$;
COMMIT;

SELECT
    e.name,
    e.status AS event_status,
    o.status AS order_status,
    t.status AS ticket_status,
    p.status AS payment_status
FROM app.events e
JOIN app.orders o ON o.event_id = e.id
JOIN app.order_items oi ON oi.order_id = o.id
JOIN app.tickets t ON t.order_item_id = oi.id
JOIN app.payments p ON p.order_id = o.id
WHERE e.name = 'TX Demo Commit';

\echo '==> Transaction 2: controlled ROLLBACK'
BEGIN;
DO $rollback_demo$
DECLARE
    v_organizer_id BIGINT;
    v_buyer_id BIGINT;
    v_venue_id BIGINT;
    v_event_id BIGINT;
    v_category_id BIGINT;
    v_order_id BIGINT;
    v_item_id BIGINT;
BEGIN
    SELECT id INTO v_organizer_id FROM app.users WHERE email = 'organizer@example.com';
    SELECT id INTO v_buyer_id FROM app.users WHERE email = 'buyer@example.com';
    SELECT id INTO v_venue_id FROM app.venues ORDER BY id LIMIT 1;

    INSERT INTO app.events (
        organizer_id, venue_id, name, starts_at, ends_at, status
    )
    VALUES (
        v_organizer_id, v_venue_id, 'TX Demo Rollback',
        '2027-11-17 18:00:00+03', '2027-11-17 22:00:00+03',
        'draft'
    )
    RETURNING id INTO v_event_id;

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_event_id, 'TX Rollback Zone', 'zone', 200, 1)
    RETURNING id INTO v_category_id;

    PERFORM app.publish_event(v_event_id);

    INSERT INTO app.orders (
        user_id, event_id, status,
        subtotal_amount, platform_fee_amount, total_amount
    )
    VALUES (v_buyer_id, v_event_id, 'pending_payment', 200, 20, 220)
    RETURNING id INTO v_order_id;

    INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
    VALUES (v_order_id, v_event_id, v_category_id, 200)
    RETURNING id INTO v_item_id;

    PERFORM app.reserve_zone_ticket(
        v_item_id,
        digest('tx-demo-rollback-ticket', 'sha256'),
        '2027-11-17 19:00:00+03'
    );

    INSERT INTO app.payments (
        order_id, provider_payment_id, amount, currency, status
    )
    VALUES (
        v_order_id, 'tx-demo-rollback-payment', 220, 'RUB', 'pending'
    );

    PERFORM app.pay_order(v_order_id);
END
$rollback_demo$;
ROLLBACK;

SELECT count(*) AS rolled_back_events
FROM app.events
WHERE name = 'TX Demo Rollback';

DO $verify$
BEGIN
    IF (SELECT count(*) FROM app.events WHERE name = 'TX Demo Commit') <> 1 THEN
        RAISE EXCEPTION 'COMMIT demo result is missing';
    END IF;

    IF (SELECT count(*) FROM app.events WHERE name = 'TX Demo Rollback') <> 0 THEN
        RAISE EXCEPTION 'ROLLBACK demo left persistent data';
    END IF;
END
$verify$;

\echo 'PASS: COMMIT persisted the related rows; ROLLBACK removed the second transaction.'
