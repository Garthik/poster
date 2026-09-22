BEGIN;

DO $$
DECLARE
    v_organizer_id BIGINT;
    v_venue_id BIGINT;
    v_event_id BIGINT;
    v_category_id BIGINT;
    v_buyer_id BIGINT;
    v_order_id BIGINT;
BEGIN
    SELECT u.id INTO v_organizer_id
      FROM app.users u WHERE u.email = 'organizer@example.com';
    SELECT u.id INTO v_buyer_id
      FROM app.users u WHERE u.email = 'buyer@example.com';
    SELECT v.id INTO v_venue_id
      FROM app.venues v WHERE v.name = 'Central Concert Hall';
    SELECT e.id INTO v_event_id
      FROM app.events e WHERE e.name = 'Symphony Night';
    SELECT c.id INTO v_category_id
      FROM app.ticket_categories c
     WHERE c.event_id = v_event_id AND c.name = 'Standard';
    SELECT o.id INTO v_order_id
      FROM app.orders o
     WHERE o.user_id = v_buyer_id AND o.event_id = v_event_id
     ORDER BY o.id DESC LIMIT 1;

    BEGIN
        INSERT INTO app.users (email, password_hash, role)
        VALUES ('buyer@example.com', 'hash', 'buyer');
        RAISE EXCEPTION 'Expected UNIQUE failure for lower(email)';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO app.venues (name, capacity) VALUES ('Invalid Capacity', 0);
        RAISE EXCEPTION 'Expected CHECK failure for venue capacity';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO app.events (organizer_id, venue_id, name, starts_at, ends_at)
        VALUES (v_organizer_id, v_venue_id, 'Invalid Dates', '2027-01-02 10:00+03', '2027-01-02 09:00+03');
        RAISE EXCEPTION 'Expected CHECK failure for event dates';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
        VALUES (v_event_id, 'Bad quota', 'seat', 1000, 0);
        RAISE EXCEPTION 'Expected CHECK failure for quota';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO app.events (organizer_id, venue_id, name, starts_at, ends_at)
        VALUES (999999999, v_venue_id, 'Bad FK', '2027-01-02 10:00+03', '2027-01-02 11:00+03');
        RAISE EXCEPTION 'Expected FK failure for organizer';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
        VALUES (v_order_id, v_event_id, v_category_id, -1);
        RAISE EXCEPTION 'Expected CHECK failure for negative unit price';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO app.payments (order_id, provider_payment_id, amount, currency, status)
        VALUES (v_order_id, 'bad-currency', 1, 'RU', 'pending');
        RAISE EXCEPTION 'Expected CHECK failure for currency';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO app.tickets (order_item_id, event_id, category_id, qr_hash, status, reserved_until)
        VALUES (999999999, v_event_id, v_category_id, decode(repeat('00', 32), 'hex'), 'reserved', now());
        RAISE EXCEPTION 'Expected FK failure for order item';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;
END $$;

ROLLBACK;
