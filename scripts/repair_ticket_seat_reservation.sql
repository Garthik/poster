BEGIN;

-- Restore seat_id for tickets created before reserve_zone_ticket() copied it
-- from order_items. Only NULL ticket.seat_id values are backfilled.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM app.tickets t
        JOIN app.order_items oi ON oi.id = t.order_item_id
        WHERE t.seat_id IS NULL
          AND oi.seat_id IS NOT NULL
    ) THEN
        UPDATE app.tickets t
           SET seat_id = oi.seat_id
          FROM app.order_items oi
         WHERE oi.id = t.order_item_id
           AND t.seat_id IS NULL
           AND oi.seat_id IS NOT NULL;
    END IF;
END
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
    v_seat_id BIGINT;
    v_quota INTEGER;
    v_active_count INTEGER;
    v_ticket_id BIGINT;
BEGIN
    SELECT event_id, category_id, seat_id
      INTO v_event_id, v_category_id, v_seat_id
      FROM app.order_items
     WHERE id = p_order_item_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Order item not found';
    END IF;

    PERFORM 1
      FROM app.ticket_categories
     WHERE id = v_category_id
       AND event_id = v_event_id
     FOR UPDATE;

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
        order_item_id, event_id, category_id, seat_id, qr_hash, status, reserved_until
    )
    VALUES (
        p_order_item_id, v_event_id, v_category_id, v_seat_id,
        p_qr_hash, 'reserved', p_reserved_until
    )
    RETURNING id INTO v_ticket_id;

    RETURN v_ticket_id;
END;
$$;

COMMIT;
