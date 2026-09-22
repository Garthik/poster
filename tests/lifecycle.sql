BEGIN;

DO $$
DECLARE
    v_organizer_id BIGINT;
    v_buyer_id BIGINT;
    v_controller_id BIGINT;
    v_venue_id BIGINT;
    v_event_id BIGINT;
    v_category_id BIGINT;
    v_seat_id BIGINT;
    v_order_id BIGINT;
    v_item_id BIGINT;
    v_ticket_id BIGINT;
    v_refund_event_id BIGINT;
    v_refund_category_id BIGINT;
    v_refund_order_id BIGINT;
    v_refund_item_1 BIGINT;
    v_refund_item_2 BIGINT;
    v_refund_ticket_1 BIGINT;
    v_refund_ticket_2 BIGINT;
BEGIN
    SELECT u.id INTO v_organizer_id FROM app.users u WHERE u.email = 'organizer@example.com';
    SELECT u.id INTO v_buyer_id FROM app.users u WHERE u.email = 'buyer@example.com';
    SELECT u.id INTO v_controller_id FROM app.users u WHERE u.email = 'controller@example.com';
    SELECT v.id INTO v_venue_id FROM app.venues v WHERE v.name = 'Central Concert Hall';

    ----------------------------------------------------------------------
    -- Event: draft -> published
    ----------------------------------------------------------------------
    INSERT INTO app.events (
        organizer_id, venue_id, name, starts_at, ends_at, status, description
    )
    VALUES (
        v_organizer_id, v_venue_id, 'Lifecycle Test Event',
        '2027-08-20 19:00:00+03', '2027-08-20 22:00:00+03', 'draft',
        'Lifecycle test'
    )
    RETURNING id INTO v_event_id;

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_event_id, 'Standard', 'seat', 1000, 1)
    RETURNING id INTO v_category_id;

    SELECT vs.id INTO v_seat_id
      FROM app.venue_seats vs
     WHERE vs.venue_id = v_venue_id
     ORDER BY vs.id
     LIMIT 1;

    INSERT INTO app.event_seats (event_id, venue_id, seat_id, category_id)
    VALUES (v_event_id, v_venue_id, v_seat_id, v_category_id);

    PERFORM app.publish_event(v_event_id);

    IF NOT EXISTS (
        SELECT 1 FROM app.events e
        WHERE e.id = v_event_id
          AND e.status = 'published'
          AND e.published_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Event lifecycle: publication failed';
    END IF;

    ----------------------------------------------------------------------
    -- Order: pending_payment -> paid
    ----------------------------------------------------------------------
    INSERT INTO app.orders (
        user_id, event_id, status,
        subtotal_amount, platform_fee_amount, total_amount
    )
    VALUES (v_buyer_id, v_event_id, 'pending_payment', 1000, 100, 1100)
    RETURNING id INTO v_order_id;

    INSERT INTO app.order_items (
        order_id, event_id, category_id, seat_id, unit_price
    )
    VALUES (v_order_id, v_event_id, v_category_id, v_seat_id, 1000)
    RETURNING id INTO v_item_id;

    ----------------------------------------------------------------------
    -- Ticket: reserved -> valid -> scanned
    ----------------------------------------------------------------------
    SELECT app.reserve_zone_ticket(
        v_item_id,
        digest('lifecycle-ticket', 'sha256'),
        '2027-08-20 19:15:00+03'
    ) INTO v_ticket_id;

    IF NOT EXISTS (
        SELECT 1 FROM app.tickets t
        WHERE t.id = v_ticket_id
          AND t.status = 'reserved'
          AND t.reserved_until = '2027-08-20 19:15:00+03'
    ) THEN
        RAISE EXCEPTION 'Ticket lifecycle: reservation failed';
    END IF;

    PERFORM app.pay_order(v_order_id);

    IF NOT EXISTS (
        SELECT 1 FROM app.orders o
        WHERE o.id = v_order_id
          AND o.status = 'paid'
    ) THEN
        RAISE EXCEPTION 'Order lifecycle: payment transition failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app.tickets t
        WHERE t.id = v_ticket_id
          AND t.status = 'valid'
          AND t.issued_at IS NOT NULL
          AND t.reserved_until IS NULL
    ) THEN
        RAISE EXCEPTION 'Ticket lifecycle: issue transition failed';
    END IF;

    PERFORM app.scan_ticket(
        v_ticket_id,
        v_controller_id,
        '2027-08-20 18:30:00+03'
    );

    IF NOT EXISTS (
        SELECT 1 FROM app.tickets t
        WHERE t.id = v_ticket_id
          AND t.status = 'scanned'
          AND t.scanned_at = '2027-08-20 18:30:00+03'
    ) THEN
        RAISE EXCEPTION 'Ticket lifecycle: scan transition failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app.ticket_scans s
        WHERE s.ticket_id = v_ticket_id
          AND s.controller_id = v_controller_id
          AND s.result = 'accepted'
    ) THEN
        RAISE EXCEPTION 'Ticket lifecycle: accepted scan was not recorded';
    END IF;

    ----------------------------------------------------------------------
    -- Refund scenario with two tickets in one order: only one ticket is annulled.
    ----------------------------------------------------------------------
    INSERT INTO app.events (
        organizer_id, venue_id, name, starts_at, ends_at, status, description
    )
    VALUES (
        v_organizer_id, v_venue_id, 'Refund Lifecycle Event',
        '2027-09-20 19:00:00+03', '2027-09-20 22:00:00+03', 'draft',
        'Refund lifecycle test'
    )
    RETURNING id INTO v_refund_event_id;

    INSERT INTO app.ticket_categories (
        event_id, name, type, price, quota
    )
    VALUES (
        v_refund_event_id, 'Zone', 'zone', 1000, 2
    )
    RETURNING id INTO v_refund_category_id;

    PERFORM app.publish_event(v_refund_event_id);

    INSERT INTO app.orders (
        user_id, event_id, status,
        subtotal_amount, platform_fee_amount, total_amount
    )
    VALUES (
        v_buyer_id, v_refund_event_id, 'pending_payment',
        2000, 200, 2200
    )
    RETURNING id INTO v_refund_order_id;

    INSERT INTO app.order_items (
        order_id, event_id, category_id, unit_price
    )
    VALUES (
        v_refund_order_id, v_refund_event_id, v_refund_category_id, 1000
    )
    RETURNING id INTO v_refund_item_1;

    INSERT INTO app.order_items (
        order_id, event_id, category_id, unit_price
    )
    VALUES (
        v_refund_order_id, v_refund_event_id, v_refund_category_id, 1000
    )
    RETURNING id INTO v_refund_item_2;

    SELECT app.reserve_zone_ticket(
        v_refund_item_1,
        digest('refund-ticket-1', 'sha256'),
        '2027-09-20 19:15:00+03'
    ) INTO v_refund_ticket_1;

    SELECT app.reserve_zone_ticket(
        v_refund_item_2,
        digest('refund-ticket-2', 'sha256'),
        '2027-09-20 19:15:00+03'
    ) INTO v_refund_ticket_2;

    PERFORM app.pay_order(v_refund_order_id);

    PERFORM app.refund_ticket(
        v_refund_ticket_1,
        1000.00,
        '2027-09-15 19:00:00+03',
        'refund-001'
    );

    IF NOT EXISTS (
        SELECT 1 FROM app.tickets t
        WHERE t.id = v_refund_ticket_1
          AND t.status = 'annulled'
          AND t.annulled_at = '2027-09-15 19:00:00+03'
    ) THEN
        RAISE EXCEPTION 'Refund lifecycle: refunded ticket was not annulled';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app.tickets t
        WHERE t.id = v_refund_ticket_2
          AND t.status = 'valid'
    ) THEN
        RAISE EXCEPTION 'BR-8: refund changed another ticket in the same order';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app.refunds r
        WHERE r.ticket_id = v_refund_ticket_1
          AND r.status = 'approved'
          AND r.amount = 1000.00
    ) THEN
        RAISE EXCEPTION 'Refund lifecycle: refund record was not created';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app.orders o
        WHERE o.id = v_refund_order_id
          AND o.status = 'paid'
    ) THEN
        RAISE EXCEPTION 'BR-8: refund of one ticket must not refund the whole order';
    END IF;

    RAISE NOTICE 'All lifecycle checks passed';
END $$;

ROLLBACK;
