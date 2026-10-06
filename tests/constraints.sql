BEGIN;

DO $$
DECLARE
    v_organizer_id BIGINT;
    v_buyer_id BIGINT;
    v_controller_id BIGINT;
    v_venue_id BIGINT;
    v_event_id BIGINT;
    v_category_id BIGINT;
    v_zone_event_id BIGINT;
    v_zone_category_id BIGINT;
    v_zone_order_id BIGINT;
    v_order_id BIGINT;
    v_item_id BIGINT;
    v_ticket_id BIGINT;
    v_seed_ticket_id BIGINT;
    v_seed_order_id BIGINT;
    v_seed_item_id BIGINT;
    v_payment_order_id BIGINT;
    v_payment_item_id BIGINT;
    v_payment_ticket_id BIGINT;
    v_seat_id BIGINT;
    i INTEGER;
BEGIN
    SELECT u.id INTO v_organizer_id FROM app.users u WHERE u.email = 'organizer@example.com';
    SELECT u.id INTO v_buyer_id FROM app.users u WHERE u.email = 'buyer@example.com';
    SELECT u.id INTO v_controller_id FROM app.users u WHERE u.email = 'controller@example.com';
    SELECT v.id INTO v_venue_id FROM app.venues v WHERE v.name = 'Central Concert Hall';
    SELECT e.id INTO v_event_id FROM app.events e WHERE e.name = 'Symphony Night';
    SELECT c.id INTO v_category_id
      FROM app.ticket_categories c
     WHERE c.event_id = v_event_id AND c.name = 'Standard';
    SELECT o.id INTO v_seed_order_id
      FROM app.orders o
     WHERE o.user_id = v_buyer_id AND o.event_id = v_event_id
     ORDER BY o.id DESC LIMIT 1;
    SELECT oi.id, oi.seat_id INTO v_seed_item_id, v_seat_id
      FROM app.order_items oi
     WHERE oi.order_id = v_seed_order_id
     ORDER BY oi.id
     LIMIT 1;
    SELECT t.id INTO v_seed_ticket_id
      FROM app.tickets t
     WHERE t.order_item_id = v_seed_item_id;

    ----------------------------------------------------------------------
    -- 1. UNIQUE: lower(email)
    -- Не зависит от seed: сначала создаём базовую запись внутри
    -- текущей транзакции, затем проверяем case-insensitive UNIQUE.
    ----------------------------------------------------------------------
    BEGIN
        INSERT INTO app.users (email, password_hash, role)
        VALUES ('constraint-unique@example.com', 'hash', 'buyer');

        BEGIN
            INSERT INTO app.users (email, password_hash, role)
            VALUES ('CONSTRAINT-UNIQUE@example.com', 'hash', 'buyer');
            RAISE EXCEPTION 'Expected UNIQUE failure for lower(email)';
        EXCEPTION WHEN unique_violation THEN
            NULL;
        END;
    END;

    ----------------------------------------------------------------------
    -- 2. CHECK: venue capacity > 0
    ----------------------------------------------------------------------
    BEGIN
        INSERT INTO app.venues (name, capacity)
        VALUES ('Invalid Capacity', 0);
        RAISE EXCEPTION 'Expected CHECK failure for venue capacity';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 3. CHECK: event end > event start
    ----------------------------------------------------------------------
    BEGIN
        INSERT INTO app.events (
            organizer_id, venue_id, name, starts_at, ends_at
        )
        VALUES (
            v_organizer_id, v_venue_id, 'Invalid Dates',
            '2027-01-02 10:00+03', '2027-01-02 09:00+03'
        );
        RAISE EXCEPTION 'Expected CHECK failure for event dates';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 4. CHECK: category quota > 0
    ----------------------------------------------------------------------
    BEGIN
        INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
        VALUES (v_event_id, 'Bad quota', 'seat', 1000, 0);
        RAISE EXCEPTION 'Expected CHECK failure for quota';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 5. FOREIGN KEY: event organizer
    ----------------------------------------------------------------------
    BEGIN
        INSERT INTO app.events (
            organizer_id, venue_id, name, starts_at, ends_at
        )
        VALUES (
            999999999, v_venue_id, 'Bad FK',
            '2027-01-02 10:00+03', '2027-01-02 11:00+03'
        );
        RAISE EXCEPTION 'Expected FK failure for organizer';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 6. CHECK: order item price >= 0
    ----------------------------------------------------------------------
    BEGIN
        INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
        VALUES (v_seed_order_id, v_event_id, v_category_id, -1);
        RAISE EXCEPTION 'Expected CHECK failure for negative unit price';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 7. CHECK: payment currency is ISO-like 3 uppercase letters
    ----------------------------------------------------------------------
    BEGIN
        INSERT INTO app.payments (
            order_id, provider_payment_id, amount, currency, status
        )
        VALUES (
            v_seed_order_id, 'bad-currency', 1, 'RU', 'pending'
        );
        RAISE EXCEPTION 'Expected CHECK failure for currency';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 8. FOREIGN KEY: ticket order item
    ----------------------------------------------------------------------
    BEGIN
        INSERT INTO app.tickets (
            order_item_id, event_id, category_id, qr_hash, status, reserved_until
        )
        VALUES (
            999999999, v_event_id, v_category_id,
            decode(repeat('00', 32), 'hex'), 'reserved', now()
        );
        RAISE EXCEPTION 'Expected FK failure for order item';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 9. CHECK: order total = subtotal + platform fee
    ----------------------------------------------------------------------
    BEGIN
        INSERT INTO app.orders (
            user_id, event_id, status,
            subtotal_amount, platform_fee_amount, total_amount
        )
        VALUES (
            v_buyer_id, v_event_id, 'created',
            100, 10, 999
        );
        RAISE EXCEPTION 'Expected CHECK failure for order amounts';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 10. CHECK: QR hash must be exactly 32 bytes
    ----------------------------------------------------------------------
    INSERT INTO app.orders (
        user_id, event_id, status,
        subtotal_amount, platform_fee_amount, total_amount
    )
    VALUES (
        v_buyer_id, v_event_id, 'pending_payment',
        2500, 250, 2750
    )
    RETURNING id INTO v_order_id;

    INSERT INTO app.order_items (
        order_id, event_id, category_id, seat_id, unit_price
    )
    VALUES (
        v_order_id, v_event_id, v_category_id, NULL, 2500
    )
    RETURNING id INTO v_item_id;

    BEGIN
        INSERT INTO app.tickets (
            order_item_id, event_id, category_id, qr_hash, status, reserved_until
        )
        VALUES (
            v_item_id, v_event_id, v_category_id,
            decode(repeat('aa', 31), 'hex'), 'reserved', now()
        );
        RAISE EXCEPTION 'Expected CHECK failure for QR length';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 11. CHECK: publishing requires a positive ticket quota
    ----------------------------------------------------------------------
    INSERT INTO app.events (
        organizer_id, venue_id, name, starts_at, ends_at, status
    )
    VALUES (
        v_organizer_id, v_venue_id, 'No Quota Event',
        '2027-09-20 10:00+03', '2027-09-20 12:00+03', 'draft'
    )
    RETURNING id INTO v_zone_event_id;

    BEGIN
        PERFORM app.publish_event(v_zone_event_id);
        RAISE EXCEPTION 'Expected publication to fail without quota';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 12. BR-1: an order cannot contain more than 10 tickets
    ----------------------------------------------------------------------
    INSERT INTO app.ticket_categories (
        event_id, name, type, price, quota
    )
    VALUES (
        v_zone_event_id, 'Zone', 'zone', 100, 100
    )
    RETURNING id INTO v_zone_category_id;

    PERFORM app.publish_event(v_zone_event_id);

    INSERT INTO app.orders (
        user_id, event_id, status,
        subtotal_amount, platform_fee_amount, total_amount
    )
    VALUES (
        v_buyer_id, v_zone_event_id, 'pending_payment',
        1000, 100, 1100
    )
    RETURNING id INTO v_zone_order_id;

    FOR i IN 1..10 LOOP
        INSERT INTO app.order_items (
            order_id, event_id, category_id, unit_price
        )
        VALUES (
            v_zone_order_id, v_zone_event_id, v_zone_category_id, 100
        );
    END LOOP;

    BEGIN
        INSERT INTO app.order_items (
            order_id, event_id, category_id, unit_price
        )
        VALUES (
            v_zone_order_id, v_zone_event_id, v_zone_category_id, 100
        );
        RAISE EXCEPTION 'Expected BR-1 order item limit failure';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 13. Active seat uniqueness: same seat cannot have two active tickets
    ----------------------------------------------------------------------
    INSERT INTO app.orders (
        user_id, event_id, status,
        subtotal_amount, platform_fee_amount, total_amount
    )
    VALUES (
        v_buyer_id, v_event_id, 'pending_payment',
        2500, 250, 2750
    )
    RETURNING id INTO v_order_id;

    INSERT INTO app.order_items (
        order_id, event_id, category_id, seat_id, unit_price
    )
    VALUES (
        v_order_id, v_event_id, v_category_id, v_seat_id, 2500
    )
    RETURNING id INTO v_item_id;

    BEGIN
        PERFORM app.reserve_zone_ticket(
            v_item_id,
            digest('duplicate-active-seat', 'sha256'),
            '2027-05-20 19:15:00+03'
        );
        RAISE EXCEPTION 'Expected active-seat uniqueness failure';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- Prepare an isolated pending order for payment/scan tests.
    -- These checks must not depend on the current state of seed data.
    ----------------------------------------------------------------------
    INSERT INTO app.orders (
        user_id, event_id, status,
        subtotal_amount, platform_fee_amount, total_amount
    )
    VALUES (
        v_buyer_id, v_zone_event_id, 'pending_payment',
        100, 10, 110
    )
    RETURNING id INTO v_payment_order_id;

    INSERT INTO app.order_items (
        order_id, event_id, category_id, seat_id, unit_price
    )
    VALUES (
        v_payment_order_id, v_zone_event_id, v_zone_category_id, NULL, 100
    )
    RETURNING id INTO v_payment_item_id;

    SELECT app.reserve_zone_ticket(
        v_payment_item_id,
        digest('constraint-payment-ticket', 'sha256'),
        '2027-09-20 19:15:00+03'
    ) INTO v_payment_ticket_id;

    ----------------------------------------------------------------------
    -- 14. BR-7: controller scan outside +/- 12 hours must fail
    ----------------------------------------------------------------------
    PERFORM app.pay_order(v_payment_order_id);

    BEGIN
        PERFORM app.scan_ticket(
            v_payment_ticket_id,
            v_controller_id,
            '2027-09-19 21:00:00+03'
        );
        RAISE EXCEPTION 'Expected controller time-window failure';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 15. BR-3: refund at/inside the 72-hour cutoff must fail
    ----------------------------------------------------------------------
    BEGIN
        PERFORM app.refund_ticket(
            v_payment_ticket_id,
            100.00,
            '2027-09-17 11:00:00+03',
            'refund-negative-001'
        );
        RAISE EXCEPTION 'Expected refund cutoff failure';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    ----------------------------------------------------------------------
    -- 16. Re-paying a non-pending order must fail
    ----------------------------------------------------------------------
    BEGIN
        PERFORM app.pay_order(v_payment_order_id);
        RAISE EXCEPTION 'Expected second payment transition failure';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    RAISE NOTICE 'All negative integrity and business-rule checks passed';
END $$;

ROLLBACK;