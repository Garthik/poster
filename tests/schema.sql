\set ON_ERROR_STOP on
SELECT set_config('app.expected_migration', :'expected_migration', false);

DO $$
DECLARE
    required_table TEXT;
BEGIN
    FOREACH required_table IN ARRAY ARRAY[
        'users',
        'venues',
        'events',
        'venue_seats',
        'ticket_categories',
        'event_seats',
        'orders',
        'order_items',
        'tickets',
        'payments',
        'refunds',
        'ticket_scans',
        'schema_migrations'
    ] LOOP
        IF to_regclass('app.' || required_table) IS NULL THEN
            RAISE EXCEPTION 'Missing required table app.%', required_table;
        END IF;
    END LOOP;
END
$$;

DO $$
DECLARE
    expected_migration TEXT := current_setting('app.expected_migration', true);
    migration_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM app.schema_migrations
        WHERE version = expected_migration
    ) INTO migration_exists;

    IF NOT migration_exists THEN
        RAISE EXCEPTION 'Expected migration % is not registered', expected_migration;
    END IF;
END
$$;

DO $$
DECLARE
    required_column RECORD;
BEGIN
    FOR required_column IN
        SELECT * FROM (VALUES
            ('users', 'id', 'bigint', 'NO'),
            ('users', 'email', 'text', 'NO'),
            ('users', 'role', 'text', 'NO'),
            ('events', 'organizer_id', 'bigint', 'NO'),
            ('events', 'venue_id', 'bigint', 'NO'),
            ('events', 'starts_at', 'timestamp with time zone', 'NO'),
            ('events', 'ends_at', 'timestamp with time zone', 'NO'),
            ('events', 'status', 'text', 'NO'),
            ('events', 'description', 'text', 'YES'),
            ('ticket_categories', 'price', 'numeric', 'NO'),
            ('ticket_categories', 'quota', 'integer', 'NO'),
            ('orders', 'total_amount', 'numeric', 'NO'),
            ('tickets', 'qr_hash', 'bytea', 'NO'),
            ('tickets', 'status', 'text', 'NO')
        ) AS t(table_name, column_name, data_type, is_nullable)
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns c
            WHERE c.table_schema = 'app'
              AND c.table_name = required_column.table_name
              AND c.column_name = required_column.column_name
              AND c.data_type = required_column.data_type
              AND c.is_nullable = required_column.is_nullable
        ) THEN
            RAISE EXCEPTION 'Missing or incorrect column app.%.%', required_column.table_name, required_column.column_name;
        END IF;
    END LOOP;
END
$$;

DO $$
DECLARE
    constraint_name TEXT;
BEGIN
    FOREACH constraint_name IN ARRAY ARRAY[
        'users_role_chk',
        'venues_capacity_chk',
        'events_dates_chk',
        'events_status_chk',
        'ticket_categories_price_chk',
        'ticket_categories_quota_chk',
        'orders_amounts_chk',
        'tickets_qr_hash_len_chk',
        'payments_currency_chk'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE connamespace = 'app'::regnamespace
              AND conname = constraint_name
        ) THEN
            RAISE EXCEPTION 'Missing required CHECK constraint %', constraint_name;
        END IF;
    END LOOP;
END
$$;

DO $$
DECLARE
    constraint_name TEXT;
BEGIN
    FOREACH constraint_name IN ARRAY ARRAY[
        'events_organizer_fk',
        'events_venue_fk',
        'ticket_categories_event_fk',
        'orders_user_fk',
        'orders_event_fk',
        'order_items_order_event_fk',
        'tickets_order_item_fk',
        'payments_order_fk',
        'refunds_ticket_fk',
        'ticket_scans_controller_fk'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE connamespace = 'app'::regnamespace
              AND conname = constraint_name
              AND contype = 'f'
        ) THEN
            RAISE EXCEPTION 'Missing required foreign key %', constraint_name;
        END IF;
    END LOOP;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'app'
          AND indexname = 'users_email_lower_uq'
    ) THEN
        RAISE EXCEPTION 'Missing unique email index';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_indexes
        WHERE schemaname = 'app'
          AND indexname = 'tickets_active_seat_uq'
    ) THEN
        RAISE EXCEPTION 'Missing active seat uniqueness index';
    END IF;
END
$$;

DO $$
BEGIN
    IF to_regprocedure('app.publish_event(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Missing app.publish_event(bigint)';
    END IF;
    IF to_regprocedure('app.reserve_zone_ticket(bigint,bytea,timestamp with time zone)') IS NULL THEN
        RAISE EXCEPTION 'Missing app.reserve_zone_ticket(...)';
    END IF;
    IF to_regprocedure('app.pay_order(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Missing app.pay_order(bigint)';
    END IF;
    IF to_regprocedure('app.scan_ticket(bigint,bigint,timestamp with time zone)') IS NULL THEN
        RAISE EXCEPTION 'Missing app.scan_ticket(...)';
    END IF;
    IF to_regprocedure('app.refund_ticket(bigint,numeric,timestamp with time zone,text)') IS NULL THEN
        RAISE EXCEPTION 'Missing app.refund_ticket(...)';
    END IF;
END
$$;

SELECT 'PASS: schema structure is valid' AS result;
