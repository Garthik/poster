BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE app.users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'buyer',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_email_not_blank_chk CHECK (btrim(email) <> ''),
    CONSTRAINT users_role_chk CHECK (role IN ('organizer', 'buyer', 'controller', 'admin'))
);

CREATE UNIQUE INDEX users_email_lower_uq ON app.users (lower(email));

CREATE TABLE app.venues (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL,
    capacity INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT venues_name_not_blank_chk CHECK (btrim(name) <> ''),
    CONSTRAINT venues_capacity_chk CHECK (capacity > 0)
);

CREATE TABLE app.events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organizer_id BIGINT NOT NULL,
    venue_id BIGINT NOT NULL,
    name TEXT NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT events_name_not_blank_chk CHECK (btrim(name) <> ''),
    CONSTRAINT events_dates_chk CHECK (ends_at > starts_at),
    CONSTRAINT events_status_chk CHECK (status IN ('draft', 'published', 'sold_out', 'completed', 'canceled')),
    CONSTRAINT events_published_at_chk CHECK (status <> 'published' OR published_at IS NOT NULL),
    CONSTRAINT events_id_venue_uq UNIQUE (id, venue_id),
    CONSTRAINT events_organizer_fk FOREIGN KEY (organizer_id) REFERENCES app.users(id),
    CONSTRAINT events_venue_fk FOREIGN KEY (venue_id) REFERENCES app.venues(id)
);

CREATE INDEX events_organizer_idx ON app.events (organizer_id);
CREATE INDEX events_venue_time_idx ON app.events (venue_id, starts_at, ends_at);

CREATE TABLE app.venue_seats (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    venue_id BIGINT NOT NULL,
    section TEXT NOT NULL,
    row_number INTEGER NOT NULL,
    seat_number INTEGER NOT NULL,
    label TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT venue_seats_row_chk CHECK (row_number > 0),
    CONSTRAINT venue_seats_number_chk CHECK (seat_number > 0),
    CONSTRAINT venue_seats_venue_fk FOREIGN KEY (venue_id) REFERENCES app.venues(id),
    CONSTRAINT venue_seats_unique_position_uq UNIQUE (venue_id, section, row_number, seat_number),
    CONSTRAINT venue_seats_id_venue_uq UNIQUE (id, venue_id)
);

CREATE TABLE app.ticket_categories (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id BIGINT NOT NULL,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    price NUMERIC(12, 2) NOT NULL DEFAULT 0,
    quota INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ticket_categories_name_not_blank_chk CHECK (btrim(name) <> ''),
    CONSTRAINT ticket_categories_type_chk CHECK (type IN ('seat', 'zone')),
    CONSTRAINT ticket_categories_price_chk CHECK (price >= 0),
    CONSTRAINT ticket_categories_quota_chk CHECK (quota > 0),
    CONSTRAINT ticket_categories_event_name_uq UNIQUE (event_id, name),
    CONSTRAINT ticket_categories_id_event_uq UNIQUE (id, event_id),
    CONSTRAINT ticket_categories_event_fk FOREIGN KEY (event_id) REFERENCES app.events(id) ON DELETE CASCADE
);

CREATE INDEX ticket_categories_event_idx ON app.ticket_categories (event_id);

CREATE TABLE app.event_seats (
    event_id BIGINT NOT NULL,
    venue_id BIGINT NOT NULL,
    seat_id BIGINT NOT NULL,
    category_id BIGINT,
    PRIMARY KEY (event_id, seat_id),
    CONSTRAINT event_seats_event_venue_fk
        FOREIGN KEY (event_id, venue_id) REFERENCES app.events(id, venue_id),
    CONSTRAINT event_seats_seat_venue_fk
        FOREIGN KEY (seat_id, venue_id) REFERENCES app.venue_seats(id, venue_id),
    CONSTRAINT event_seats_category_fk
        FOREIGN KEY (category_id, event_id) REFERENCES app.ticket_categories(id, event_id)
);

CREATE INDEX event_seats_category_idx ON app.event_seats (event_id, category_id);

CREATE TABLE app.orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    event_id BIGINT NOT NULL,
    status TEXT NOT NULL DEFAULT 'created',
    subtotal_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
    platform_fee_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT orders_status_chk CHECK (status IN ('created', 'pending_payment', 'paid', 'refunded', 'failed')),
    CONSTRAINT orders_amounts_chk CHECK (
        subtotal_amount >= 0
        AND platform_fee_amount >= 0
        AND total_amount = subtotal_amount + platform_fee_amount
    ),
    CONSTRAINT orders_id_event_uq UNIQUE (id, event_id),
    CONSTRAINT orders_user_fk FOREIGN KEY (user_id) REFERENCES app.users(id),
    CONSTRAINT orders_event_fk FOREIGN KEY (event_id) REFERENCES app.events(id)
);

CREATE INDEX orders_user_created_idx ON app.orders (user_id, created_at DESC);
CREATE INDEX orders_event_status_idx ON app.orders (event_id, status);

CREATE TABLE app.order_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    event_id BIGINT NOT NULL,
    category_id BIGINT NOT NULL,
    seat_id BIGINT,
    unit_price NUMERIC(12, 2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT order_items_price_chk CHECK (unit_price >= 0),
    CONSTRAINT order_items_order_event_fk
        FOREIGN KEY (order_id, event_id) REFERENCES app.orders(id, event_id) ON DELETE CASCADE,
    CONSTRAINT order_items_category_fk
        FOREIGN KEY (category_id, event_id) REFERENCES app.ticket_categories(id, event_id),
    CONSTRAINT order_items_seat_fk
        FOREIGN KEY (event_id, seat_id) REFERENCES app.event_seats(event_id, seat_id),
    CONSTRAINT order_items_seat_unique_uq UNIQUE (order_id, seat_id)
);

CREATE INDEX order_items_order_idx ON app.order_items (order_id);

CREATE TABLE app.tickets (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_item_id BIGINT NOT NULL UNIQUE,
    event_id BIGINT NOT NULL,
    category_id BIGINT NOT NULL,
    seat_id BIGINT,
    qr_hash BYTEA NOT NULL,
    status TEXT NOT NULL DEFAULT 'reserved',
    reserved_until TIMESTAMPTZ,
    issued_at TIMESTAMPTZ,
    scanned_at TIMESTAMPTZ,
    annulled_at TIMESTAMPTZ,
    CONSTRAINT tickets_status_chk CHECK (status IN ('reserved', 'valid', 'scanned', 'expired', 'annulled')),
    CONSTRAINT tickets_qr_hash_len_chk CHECK (octet_length(qr_hash) = 32),
    CONSTRAINT tickets_reserved_until_chk CHECK (status <> 'reserved' OR reserved_until IS NOT NULL),
    CONSTRAINT tickets_issued_at_chk CHECK (status IN ('reserved', 'expired', 'annulled') OR issued_at IS NOT NULL),
    CONSTRAINT tickets_order_item_fk FOREIGN KEY (order_item_id) REFERENCES app.order_items(id) ON DELETE CASCADE,
    CONSTRAINT tickets_category_fk
        FOREIGN KEY (category_id, event_id) REFERENCES app.ticket_categories(id, event_id),
    CONSTRAINT tickets_seat_fk
        FOREIGN KEY (event_id, seat_id) REFERENCES app.event_seats(event_id, seat_id)
);

CREATE UNIQUE INDEX tickets_qr_hash_uq ON app.tickets (qr_hash);
CREATE UNIQUE INDEX tickets_active_seat_uq
    ON app.tickets (event_id, seat_id)
    WHERE seat_id IS NOT NULL AND status IN ('reserved', 'valid', 'scanned');
CREATE INDEX tickets_event_status_idx ON app.tickets (event_id, status);

CREATE TABLE app.payments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    provider_payment_id TEXT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'RUB',
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at TIMESTAMPTZ,
    CONSTRAINT payments_amount_chk CHECK (amount >= 0),
    CONSTRAINT payments_currency_chk CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT payments_status_chk CHECK (status IN ('pending', 'approved', 'declined', 'refunded')),
    CONSTRAINT payments_order_fk FOREIGN KEY (order_id) REFERENCES app.orders(id),
    CONSTRAINT payments_provider_id_uq UNIQUE (provider_payment_id)
);

CREATE INDEX payments_order_idx ON app.payments (order_id, created_at DESC);

CREATE TABLE app.refunds (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id BIGINT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    status TEXT NOT NULL,
    provider_ref TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT refunds_amount_chk CHECK (amount > 0),
    CONSTRAINT refunds_status_chk CHECK (status IN ('pending', 'approved', 'rejected')),
    CONSTRAINT refunds_ticket_fk FOREIGN KEY (ticket_id) REFERENCES app.tickets(id),
    CONSTRAINT refunds_ticket_uq UNIQUE (ticket_id)
);

CREATE TABLE app.ticket_scans (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id BIGINT NOT NULL,
    controller_id BIGINT NOT NULL,
    scanned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    result TEXT NOT NULL,
    CONSTRAINT ticket_scans_result_chk CHECK (result IN ('accepted', 'rejected')),
    CONSTRAINT ticket_scans_ticket_fk FOREIGN KEY (ticket_id) REFERENCES app.tickets(id),
    CONSTRAINT ticket_scans_controller_fk FOREIGN KEY (controller_id) REFERENCES app.users(id)
);

CREATE INDEX ticket_scans_ticket_idx ON app.ticket_scans (ticket_id, scanned_at DESC);

CREATE OR REPLACE FUNCTION app.check_order_item_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    item_count INTEGER;
BEGIN
    PERFORM 1 FROM app.orders WHERE id = NEW.order_id FOR UPDATE;

    SELECT count(*)
      INTO item_count
      FROM app.order_items
     WHERE order_id = NEW.order_id;

    IF item_count >= 10 THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'An order may contain at most 10 tickets for one event';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_order_item_limit
BEFORE INSERT ON app.order_items
FOR EACH ROW
EXECUTE FUNCTION app.check_order_item_limit();

CREATE OR REPLACE FUNCTION app.publish_event(p_event_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    category_count INTEGER;
BEGIN
    PERFORM 1
      FROM app.events
     WHERE id = p_event_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Event not found';
    END IF;

    SELECT count(*)
      INTO category_count
      FROM app.ticket_categories
     WHERE event_id = p_event_id
       AND quota > 0;

    IF category_count = 0 THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Published event must have at least one ticket category with positive quota';
    END IF;

    UPDATE app.events
       SET status = 'published',
           published_at = COALESCE(published_at, now())
     WHERE id = p_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION app.reserve_zone_ticket(
    p_order_item_id BIGINT,
    p_qr_hash BYTEA,
    p_reserved_until TIMESTAMPTZ
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_id BIGINT;
    v_category_id BIGINT;
    v_quota INTEGER;
    v_active_count INTEGER;
    v_ticket_id BIGINT;
BEGIN
    SELECT event_id, category_id
      INTO v_event_id, v_category_id
      FROM app.order_items
     WHERE id = p_order_item_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Order item not found';
    END IF;

    PERFORM 1 FROM app.ticket_categories WHERE id = v_category_id AND event_id = v_event_id FOR UPDATE;

    SELECT quota
      INTO v_quota
      FROM app.ticket_categories
     WHERE id = v_category_id
       AND event_id = v_event_id;

    SELECT count(*)
      INTO v_active_count
      FROM app.tickets
     WHERE category_id = v_category_id
       AND event_id = v_event_id
       AND status IN ('reserved', 'valid', 'scanned');

    IF v_active_count >= v_quota THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ticket category quota is exhausted';
    END IF;

    INSERT INTO app.tickets (
        order_item_id, event_id, category_id, qr_hash, status, reserved_until
    )
    VALUES (
        p_order_item_id, v_event_id, v_category_id, p_qr_hash, 'reserved', p_reserved_until
    )
    RETURNING id INTO v_ticket_id;

    RETURN v_ticket_id;
END;
$$;

CREATE OR REPLACE FUNCTION app.pay_order(p_order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE app.orders
       SET status = 'paid'
     WHERE id = p_order_id
       AND status = 'pending_payment';

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Order is not awaiting payment';
    END IF;

    UPDATE app.tickets
       SET status = 'valid',
           issued_at = COALESCE(issued_at, now()),
           reserved_until = NULL
     WHERE order_item_id IN (
         SELECT id FROM app.order_items WHERE order_id = p_order_id
     )
       AND status = 'reserved';
END;
$$;

CREATE OR REPLACE FUNCTION app.scan_ticket(
    p_ticket_id BIGINT,
    p_controller_id BIGINT,
    p_scanned_at TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
    v_starts_at TIMESTAMPTZ;
BEGIN
    SELECT t.status, e.starts_at
      INTO v_status, v_starts_at
      FROM app.tickets t
      JOIN app.events e ON e.id = t.event_id
     WHERE t.id = p_ticket_id
     FOR UPDATE OF t;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Ticket not found';
    END IF;

    IF p_scanned_at < v_starts_at - INTERVAL '12 hours'
       OR p_scanned_at > v_starts_at + INTERVAL '12 hours' THEN
        INSERT INTO app.ticket_scans(ticket_id, controller_id, scanned_at, result)
        VALUES (p_ticket_id, p_controller_id, p_scanned_at, 'rejected');
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Controller validation is available only within +/- 12 hours of event start';
    END IF;

    IF v_status <> 'valid' THEN
        INSERT INTO app.ticket_scans(ticket_id, controller_id, scanned_at, result)
        VALUES (p_ticket_id, p_controller_id, p_scanned_at, 'rejected');
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ticket is not valid for entry';
    END IF;

    UPDATE app.tickets
       SET status = 'scanned',
           scanned_at = p_scanned_at
     WHERE id = p_ticket_id;

    INSERT INTO app.ticket_scans(ticket_id, controller_id, scanned_at, result)
    VALUES (p_ticket_id, p_controller_id, p_scanned_at, 'accepted');
END;
$$;

CREATE OR REPLACE FUNCTION app.refund_ticket(
    p_ticket_id BIGINT,
    p_amount NUMERIC(12,2),
    p_refund_at TIMESTAMPTZ,
    p_provider_ref TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
    v_starts_at TIMESTAMPTZ;
BEGIN
    SELECT t.status, e.starts_at
      INTO v_status, v_starts_at
      FROM app.tickets t
      JOIN app.events e ON e.id = t.event_id
     WHERE t.id = p_ticket_id
     FOR UPDATE OF t;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Ticket not found';
    END IF;

    IF v_status <> 'valid' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Only a valid ticket can be refunded';
    END IF;

    IF p_refund_at >= v_starts_at - INTERVAL '72 hours' THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Ticket refund is unavailable within 72 hours of event start';
    END IF;

    INSERT INTO app.refunds(ticket_id, amount, status, provider_ref)
    VALUES (p_ticket_id, p_amount, 'approved', p_provider_ref);

    UPDATE app.tickets
       SET status = 'annulled',
           annulled_at = p_refund_at
     WHERE id = p_ticket_id;
END;
$$;

CREATE TABLE app.schema_migrations (
    version VARCHAR(100) PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO app.schema_migrations(version) VALUES ('001_init');

COMMIT;
