BEGIN;

INSERT INTO app.users (email, password_hash, role)
VALUES
    ('organizer@example.com', '$2b$12$example-organizer-hash', 'organizer'),
    ('buyer@example.com', '$2b$12$example-buyer-hash', 'buyer'),
    ('controller@example.com', '$2b$12$example-controller-hash', 'controller')
ON CONFLICT DO NOTHING;

INSERT INTO app.venues (name, capacity)
SELECT 'Central Concert Hall', 100
WHERE NOT EXISTS (SELECT 1 FROM app.venues WHERE name = 'Central Concert Hall');

INSERT INTO app.venues (name, capacity)
SELECT 'Open Air Park', 500
WHERE NOT EXISTS (SELECT 1 FROM app.venues WHERE name = 'Open Air Park');

DO $$
DECLARE
    v_organizer_id BIGINT;
    v_buyer_id BIGINT;
    v_concert_venue_id BIGINT;
    v_park_venue_id BIGINT;
    v_concert_event_id BIGINT;
    v_festival_event_id BIGINT;
    v_standard_category_id BIGINT;
    v_vip_category_id BIGINT;
    v_seat_id BIGINT;
    v_order_id BIGINT;
    v_item_id BIGINT;
BEGIN
    SELECT u.id INTO v_organizer_id
      FROM app.users AS u
     WHERE u.email = 'organizer@example.com';

    SELECT u.id INTO v_buyer_id
      FROM app.users AS u
     WHERE u.email = 'buyer@example.com';

    SELECT v.id INTO v_concert_venue_id
      FROM app.venues AS v
     WHERE v.name = 'Central Concert Hall';

    SELECT v.id INTO v_park_venue_id
      FROM app.venues AS v
     WHERE v.name = 'Open Air Park';

    INSERT INTO app.venue_seats (venue_id, section, row_number, seat_number, label)
    SELECT v_concert_venue_id, s.section, s.row_number, s.seat_number, s.label
    FROM (VALUES
        ('A', 1, 1, 'A-1-1'),
        ('A', 1, 2, 'A-1-2'),
        ('A', 1, 3, 'A-1-3'),
        ('B', 1, 1, 'B-1-1')
    ) AS s(section, row_number, seat_number, label)
    WHERE NOT EXISTS (
        SELECT 1
          FROM app.venue_seats vs
         WHERE vs.venue_id = v_concert_venue_id
           AND vs.section = s.section
           AND vs.row_number = s.row_number
           AND vs.seat_number = s.seat_number
    );

    SELECT e.id INTO v_concert_event_id
      FROM app.events AS e
     WHERE e.name = 'Symphony Night'
       AND e.venue_id = v_concert_venue_id
       AND e.starts_at = '2027-05-20 19:00:00+03';

    IF v_concert_event_id IS NULL THEN
        INSERT INTO app.events (
            organizer_id, venue_id, name, starts_at, ends_at, status, description
        )
        VALUES (
            v_organizer_id,
            v_concert_venue_id,
            'Symphony Night',
            '2027-05-20 19:00:00+03',
            '2027-05-20 22:00:00+03',
            'draft',
            'Симфонический концерт для демонстрации seat-based inventory.'
        )
        RETURNING id INTO v_concert_event_id;
    END IF;

    SELECT e.id INTO v_festival_event_id
      FROM app.events AS e
     WHERE e.name = 'Open Air Festival'
       AND e.venue_id = v_park_venue_id
       AND e.starts_at = '2027-06-12 16:00:00+03';

    IF v_festival_event_id IS NULL THEN
        INSERT INTO app.events (
            organizer_id, venue_id, name, starts_at, ends_at, status, description
        )
        VALUES (
            v_organizer_id,
            v_park_venue_id,
            'Open Air Festival',
            '2027-06-12 16:00:00+03',
            '2027-06-12 23:00:00+03',
            'draft',
            'Фестиваль с зоной свободной рассадки.'
        )
        RETURNING id INTO v_festival_event_id;
    END IF;

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    SELECT v_concert_event_id, 'Standard', 'seat', 2500.00, 3
    WHERE NOT EXISTS (
        SELECT 1 FROM app.ticket_categories c
         WHERE c.event_id = v_concert_event_id AND c.name = 'Standard'
    );

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    SELECT v_concert_event_id, 'VIP', 'seat', 5000.00, 1
    WHERE NOT EXISTS (
        SELECT 1 FROM app.ticket_categories c
         WHERE c.event_id = v_concert_event_id AND c.name = 'VIP'
    );

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    SELECT v_festival_event_id, 'Dance Floor', 'zone', 1800.00, 500
    WHERE NOT EXISTS (
        SELECT 1 FROM app.ticket_categories c
         WHERE c.event_id = v_festival_event_id AND c.name = 'Dance Floor'
    );

    SELECT c.id INTO v_standard_category_id
      FROM app.ticket_categories AS c
     WHERE c.event_id = v_concert_event_id AND c.name = 'Standard';

    SELECT c.id INTO v_vip_category_id
      FROM app.ticket_categories AS c
     WHERE c.event_id = v_concert_event_id AND c.name = 'VIP';

    INSERT INTO app.event_seats (event_id, venue_id, seat_id, category_id)
    SELECT v_concert_event_id, v_concert_venue_id, vs.id, v_standard_category_id
      FROM app.venue_seats AS vs
     WHERE vs.venue_id = v_concert_venue_id
       AND vs.section = 'A'
       AND vs.row_number = 1
       AND NOT EXISTS (
           SELECT 1 FROM app.event_seats es
            WHERE es.event_id = v_concert_event_id AND es.seat_id = vs.id
       );

    INSERT INTO app.event_seats (event_id, venue_id, seat_id, category_id)
    SELECT v_concert_event_id, v_concert_venue_id, vs.id, v_vip_category_id
      FROM app.venue_seats AS vs
     WHERE vs.venue_id = v_concert_venue_id
       AND vs.section = 'B'
       AND vs.row_number = 1
       AND NOT EXISTS (
           SELECT 1 FROM app.event_seats es
            WHERE es.event_id = v_concert_event_id AND es.seat_id = vs.id
       );

    IF EXISTS (SELECT 1 FROM app.events WHERE id = v_concert_event_id AND status = 'draft') THEN
        PERFORM app.publish_event(v_concert_event_id);
    END IF;

    IF EXISTS (SELECT 1 FROM app.events WHERE id = v_festival_event_id AND status = 'draft') THEN
        PERFORM app.publish_event(v_festival_event_id);
    END IF;

    SELECT o.id INTO v_order_id
      FROM app.orders AS o
     WHERE o.user_id = v_buyer_id
       AND o.event_id = v_concert_event_id
     ORDER BY o.id DESC
     LIMIT 1;

    IF v_order_id IS NULL THEN
        INSERT INTO app.orders (
            user_id, event_id, status,
            subtotal_amount, platform_fee_amount, total_amount
        )
        VALUES (v_buyer_id, v_concert_event_id, 'pending_payment', 2500.00, 250.00, 2750.00)
        RETURNING id INTO v_order_id;
    END IF;

    SELECT es.seat_id INTO v_seat_id
      FROM app.event_seats AS es
     WHERE es.event_id = v_concert_event_id
       AND es.category_id = v_standard_category_id
     ORDER BY es.seat_id
     LIMIT 1;

    SELECT oi.id INTO v_item_id
      FROM app.order_items AS oi
     WHERE oi.order_id = v_order_id
     ORDER BY oi.id
     LIMIT 1;

    IF v_item_id IS NULL THEN
        INSERT INTO app.order_items (
            order_id, event_id, category_id, seat_id, unit_price
        )
        VALUES (
            v_order_id,
            v_concert_event_id,
            v_standard_category_id,
            v_seat_id,
            2500.00
        )
        RETURNING id INTO v_item_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM app.tickets WHERE order_item_id = v_item_id) THEN
        PERFORM app.reserve_zone_ticket(
            v_item_id,
            digest('seed-ticket-1', 'sha256'),
            '2027-05-20 19:15:00+03'
        );
    END IF;

    INSERT INTO app.payments (order_id, provider_payment_id, amount, currency, status)
    SELECT v_order_id, 'demo-payment-001', 2750.00, 'RUB', 'pending'
    WHERE NOT EXISTS (
        SELECT 1 FROM app.payments p WHERE p.provider_payment_id = 'demo-payment-001'
    );
END $$;

COMMIT;
