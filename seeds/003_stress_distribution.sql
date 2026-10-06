BEGIN;

DO $$
DECLARE
    v_whale_buyer_id BIGINT;
    v_regular_buyer_ids BIGINT[];
    v_controller_ids BIGINT[];
    v_mega_venue_id BIGINT;
    v_tiny_venue_id BIGINT;
    v_medium_venue_id BIGINT;
    v_past_event_id BIGINT;
    v_mega_event_1_id BIGINT;
    v_mega_event_2_id BIGINT;
    v_canceled_event_id BIGINT;
    v_draft_event_id BIGINT;
    v_future_event_1_id BIGINT;
    v_future_event_2_id BIGINT;
    v_past_cat_id BIGINT;
    v_vip_cat_id BIGINT;
    v_standard_cat_id BIGINT;
    v_premium_cat_id BIGINT;
    v_order_id BIGINT;
    v_item_id BIGINT;
    v_ticket_id BIGINT;
    v_longtail_user_ids BIGINT[];
    i INTEGER;
    v_base_time TIMESTAMPTZ := '2027-10-01 18:00:00+03';
BEGIN
    -- 0. идемпотентность
    IF EXISTS (SELECT 1 FROM app.users WHERE email = 'longtail_1@example.com') THEN
        RAISE NOTICE 'Стресс-данные уже существуют. Повторная генерация пропущена.';
        RETURN;
    END IF;

    -- 1. пользователи
    INSERT INTO app.users (email, password_hash, role)
    VALUES 
        ('whale@example.com', '$2b$12$whale-hash', 'buyer'),
        ('controller1@example.com', '$2b$12$controller-hash', 'controller'),
        ('controller2@example.com', '$2b$12$controller-hash', 'controller'),
        ('admin@example.com', '$2b$12$admin-hash', 'admin')
    ON CONFLICT (lower(email)) DO NOTHING;

    SELECT id INTO v_whale_buyer_id FROM app.users WHERE email = 'whale@example.com';
    SELECT array_agg(id) INTO v_controller_ids FROM app.users WHERE role = 'controller';

    -- 10 "регулярных" пользователей
    INSERT INTO app.users (email, password_hash, role)
    SELECT 'regular_' || i || '@example.com', '$2b$12$regular-hash', 'buyer'
    FROM generate_series(1, 10) AS i
    ON CONFLICT (lower(email)) DO NOTHING;

    SELECT array_agg(id) INTO v_regular_buyer_ids 
    FROM app.users WHERE email LIKE 'regular_%@example.com';

    -- 500 пользователей "длинного хвоста"
    INSERT INTO app.users (email, password_hash, role)
    SELECT 'longtail_' || i || '@example.com', '$2b$12$longtail-hash', 'buyer'
    FROM generate_series(1, 500) AS i
    ON CONFLICT (lower(email)) DO NOTHING;

    SELECT array_agg(id) INTO v_longtail_user_ids 
    FROM app.users WHERE email LIKE 'longtail_%@example.com';

    RAISE NOTICE 'Создано пользователей: 1 кит, 10 регулярных, 500 хвостовых, 2 контролера, 1 админ';

    -- 2. Площадки: Разнообразие размеров
    INSERT INTO app.venues (name, capacity)
    VALUES 
        ('Mega Arena', 50000),
        ('Tiny Club', 50),
        ('Medium Theater', 500),
        ('Open Field', 100000),
        ('Small Bar', 30)
    ON CONFLICT DO NOTHING;

    SELECT id INTO v_mega_venue_id FROM app.venues WHERE name = 'Mega Arena';
    SELECT id INTO v_tiny_venue_id FROM app.venues WHERE name = 'Tiny Club';
    SELECT id INTO v_medium_venue_id FROM app.venues WHERE name = 'Medium Theater';

    -- 3. Мероприятия: 7 событий с разными датами и статусами
    -- completed (прошлое, 2023)
    INSERT INTO app.events (organizer_id, venue_id, name, starts_at, ends_at, status, published_at, description)
    SELECT id, v_mega_venue_id, 'Past Rock Festival 2023', '2023-01-01 20:00:00+03', '2023-01-02 02:00:00+03', 'completed', '2022-12-01 10:00:00+03', 'Уже прошло'
    FROM app.users WHERE email = 'organizer@example.com' RETURNING id INTO v_past_event_id;

    -- completed (прошлое, 2024)
    INSERT INTO app.events (organizer_id, venue_id, name, starts_at, ends_at, status, published_at, description)
    SELECT id, v_medium_venue_id, 'Jazz Night 2024', '2024-06-15 19:00:00+03', '2024-06-15 23:00:00+03', 'completed', '2024-05-01 10:00:00+03', 'Прошлогодний джаз'
    FROM app.users WHERE email = 'organizer@example.com' RETURNING id INTO v_future_event_1_id;

    -- sold_out (будущее, популярное)
    INSERT INTO app.events (organizer_id, venue_id, name, starts_at, ends_at, status, published_at, description)
    SELECT id, v_mega_venue_id, 'Super Star Live 2027', '2027-12-31 23:00:00+03', '2028-01-01 02:00:00+03', 'sold_out', '2026-01-01 10:00:00+03', 'Все билеты распроданы'
    FROM app.users WHERE email = 'organizer@example.com' RETURNING id INTO v_mega_event_1_id;

    -- published (будущее, обычное)
    INSERT INTO app.events (organizer_id, venue_id, name, starts_at, ends_at, status, published_at, description)
    SELECT id, v_medium_venue_id, 'Jazz Evening 2027', '2027-06-15 19:00:00+03', '2027-06-15 22:00:00+03', 'published', '2026-01-01 10:00:00+03', 'Спокойный вечер'
    FROM app.users WHERE email = 'organizer@example.com' RETURNING id INTO v_mega_event_2_id;

    -- published (будущее, 2028)
    INSERT INTO app.events (organizer_id, venue_id, name, starts_at, ends_at, status, published_at, description)
    SELECT id, v_tiny_venue_id, 'Indie Concert 2028', '2028-03-20 20:00:00+03', '2028-03-20 23:00:00+03', 'published', '2027-01-01 10:00:00+03', 'Инди-концерт'
    FROM app.users WHERE email = 'organizer@example.com' RETURNING id INTO v_future_event_2_id;

    -- canceled (будущее, отмененное)
    INSERT INTO app.events (organizer_id, venue_id, name, starts_at, ends_at, status, published_at, description)
    SELECT id, v_tiny_venue_id, 'Underground Gig Canceled', '2027-05-01 20:00:00+03', '2027-05-01 23:00:00+03', 'canceled', '2026-01-01 10:00:00+03', 'Отменено'
    FROM app.users WHERE email = 'organizer@example.com' RETURNING id INTO v_canceled_event_id;

    -- draft (черновик, нет published_at)
    INSERT INTO app.events (organizer_id, venue_id, name, starts_at, ends_at, status, published_at, description)
    SELECT id, v_medium_venue_id, 'Secret Draft Event', '2028-01-01 20:00:00+03', '2028-01-01 23:00:00+03', 'draft', NULL, 'Только для внутреннего пользования'
    FROM app.users WHERE email = 'organizer@example.com' RETURNING id INTO v_draft_event_id;

    RAISE NOTICE 'Создано 7 мероприятий с разными статусами и датами (2023-2028)';

    -- 4. Категории: Популярные и редкие
    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_past_event_id, 'General Past', 'zone', 1500.00, 1000) RETURNING id INTO v_past_cat_id;

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_mega_event_1_id, 'Super VIP', 'seat', 15000.00, 100) RETURNING id INTO v_vip_cat_id;

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_mega_event_2_id, 'Jazz Standard', 'zone', 3000.00, 500) RETURNING id INTO v_standard_cat_id;

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_future_event_2_id, 'Premium Front Row', 'seat', 8000.00, 20) RETURNING id INTO v_premium_cat_id;

    -- 5. Генерация заказов
    
    -- 5.1. "Кит" делает 500 заказов (через цикл с функциями, ~10-20 секунд)
    RAISE NOTICE 'Генерация 500 заказов для кита...';
    FOR i IN 1..500 LOOP
        INSERT INTO app.orders (user_id, event_id, status, subtotal_amount, platform_fee_amount, total_amount)
        VALUES (v_whale_buyer_id, v_mega_event_2_id, 'pending_payment', 3000.00, 300.00, 3300.00)
        RETURNING id INTO v_order_id;

        INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
        VALUES (v_order_id, v_mega_event_2_id, v_standard_cat_id, 3000.00)
        RETURNING id INTO v_item_id;

        IF i <= 350 THEN
            -- 350 билетов: успешно оплачены (RUB)
            PERFORM app.reserve_zone_ticket(v_item_id, digest(v_item_id::text, 'sha256'), now() + interval '1 hour');
            PERFORM app.pay_order(v_order_id);
            INSERT INTO app.payments (order_id, provider_payment_id, amount, currency, status, paid_at)
            VALUES (v_order_id, 'pay-whale-' || i, 3300.00, 'RUB', 'approved', now());
        ELSIF i <= 425 THEN
            -- 75 билетов: оплачены, затем возвращены (USD - редкая валюта)
            v_ticket_id := (SELECT app.reserve_zone_ticket(v_item_id, digest((v_item_id + 1000000)::text, 'sha256'), now() + interval '1 hour'));
            PERFORM app.pay_order(v_order_id);
            INSERT INTO app.payments (order_id, provider_payment_id, amount, currency, status, paid_at)
            VALUES (v_order_id, 'pay-whale-ref-' || i, 3300.00, 'USD', 'approved', now());
            PERFORM app.refund_ticket(v_ticket_id, 3000.00, now() - interval '10 days', 'provider-ref-' || i);
        ELSIF i <= 475 THEN
            -- 50 заказов: отказ платежа (failed)
            UPDATE app.orders SET status = 'failed' WHERE id = v_order_id;
            INSERT INTO app.payments (order_id, provider_payment_id, amount, currency, status)
            VALUES (v_order_id, 'pay-whale-fail-' || i, 3300.00, 'RUB', 'declined');
        ELSE
            -- 25 заказов: остаются в pending_payment (не оплачены)
            NULL;
        END IF;
    END LOOP;

    -- 5.2. 10 "регулярных" пользователей делают по 50 заказов каждый = 500 заказов
    -- Используем массовую вставку через generate_series для скорости
    RAISE NOTICE 'Генерация 500 заказов для 10 регулярных пользователей...';
    INSERT INTO app.orders (user_id, event_id, status, subtotal_amount, platform_fee_amount, total_amount)
    SELECT 
        v_regular_buyer_ids[(g % 10) + 1],
        CASE WHEN g % 3 = 0 THEN v_mega_event_2_id 
             WHEN g % 3 = 1 THEN v_future_event_1_id 
             ELSE v_past_event_id END,
        'pending_payment',
        3000.00, 300.00, 3300.00
    FROM generate_series(1, 500) AS g;

    -- Создаем order_items для этих заказов
    INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
    SELECT o.id, o.event_id, v_standard_cat_id, 3000.00
    FROM app.orders o
    WHERE o.user_id = ANY(v_regular_buyer_ids) AND o.status = 'pending_payment';

    -- Создаем tickets со статусом 'reserved' (CHECK: reserved_until IS NOT NULL)
    INSERT INTO app.tickets (order_item_id, event_id, category_id, qr_hash, status, reserved_until)
    SELECT oi.id, oi.event_id, oi.category_id, digest(oi.id::text, 'sha256'), 'reserved', now() + interval '30 minutes'
    FROM app.order_items oi
    WHERE oi.order_id IN (SELECT id FROM app.orders WHERE user_id = ANY(v_regular_buyer_ids));

    -- 5.3. 500 пользователей делают по 1-3 заказа = ~1000 заказов
    RAISE NOTICE 'Генерация ~1000 заказов для 500 пользователей длинного хвоста...';
    INSERT INTO app.orders (user_id, event_id, status, subtotal_amount, platform_fee_amount, total_amount)
    SELECT 
        v_longtail_user_ids[(g % 500) + 1],
        CASE WHEN g % 4 = 0 THEN v_mega_event_2_id 
             WHEN g % 4 = 1 THEN v_future_event_2_id 
             WHEN g % 4 = 2 THEN v_past_event_id 
             ELSE v_future_event_1_id END,
        CASE WHEN g % 10 < 7 THEN 'pending_payment'
             WHEN g % 10 < 9 THEN 'paid'
             ELSE 'failed' END,
        3000.00, 300.00, 3300.00
    FROM generate_series(1, 1000) AS g;

    -- Создаем order_items для longtail заказов
    INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
    SELECT o.id, o.event_id, 
           CASE WHEN o.event_id = v_past_event_id THEN v_past_cat_id
                WHEN o.event_id = v_future_event_2_id THEN v_premium_cat_id
                ELSE v_standard_cat_id END,
           3000.00
    FROM app.orders o
    WHERE o.user_id = ANY(v_longtail_user_ids);

    -- Создаем tickets для longtail (разные статусы)
    INSERT INTO app.tickets (order_item_id, event_id, category_id, qr_hash, status, reserved_until, issued_at)
    SELECT oi.id, oi.event_id, oi.category_id, digest(oi.id::text, 'sha256'),
           CASE WHEN o.status = 'paid' THEN 'valid'
                WHEN o.status = 'pending_payment' THEN 'reserved'
                ELSE 'annulled' END,
           CASE WHEN o.status = 'pending_payment' THEN now() + interval '30 minutes' ELSE NULL END,
           CASE WHEN o.status = 'paid' THEN now() ELSE NULL END
    FROM app.order_items oi
    JOIN app.orders o ON oi.order_id = o.id
    WHERE o.user_id = ANY(v_longtail_user_ids);

    -- Создаем payments для оплаченных longtail заказов
    INSERT INTO app.payments (order_id, provider_payment_id, amount, currency, status, paid_at)
    SELECT o.id, 'pay-longtail-' || o.id, o.total_amount,
           CASE WHEN o.id % 20 = 0 THEN 'EUR' ELSE 'RUB' END,
           'approved', now()
    FROM app.orders o
    WHERE o.user_id = ANY(v_longtail_user_ids) AND o.status = 'paid';

    -- 6. Проверка сканирования (accepted и rejected)
    RAISE NOTICE 'Тестирование сканирования билетов...';
    INSERT INTO app.orders (user_id, event_id, status, subtotal_amount, platform_fee_amount, total_amount)
    VALUES (v_regular_buyer_ids[1], v_past_event_id, 'pending_payment', 1500.00, 150.00, 1650.00)
    RETURNING id INTO v_order_id;

    INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)
    VALUES (v_order_id, v_past_event_id, v_past_cat_id, 1500.00)
    RETURNING id INTO v_item_id;

    v_ticket_id := (SELECT app.reserve_zone_ticket(v_item_id, digest('past-scanned-ticket', 'sha256'), '2023-01-01 19:00:00+03'));
    PERFORM app.pay_order(v_order_id);
    UPDATE app.tickets SET issued_at = '2023-01-01 10:00:00+03' WHERE id = v_ticket_id;
    UPDATE app.orders SET created_at = '2023-01-01 09:00:00+03' WHERE id = v_order_id;
    
    -- Успешное сканирование (controller1)
    PERFORM app.scan_ticket(v_ticket_id, v_controller_ids[1], '2023-01-01 20:30:00+03');

    -- Намеренно отвергнутое сканирование (controller2, вне временного окна)
    BEGIN
        PERFORM app.scan_ticket(v_ticket_id, v_controller_ids[2], '2023-01-05 20:30:00+03');
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RAISE NOTICE 'Масштабированное неравномерное распределение данных успешно сгенерировано!';
    RAISE NOTICE '   - 1 пользователь (whale) имеет 500 заказов.';
    RAISE NOTICE '   - 10 пользователей (regular) имеют по 50 заказов (500 всего).';
    RAISE NOTICE '   - 500 пользователей (longtail) имеют ~1000 заказов.';
    RAISE NOTICE '   - Всего: ~2000 заказов, ~2000 билетов, ~1000 платежей.';
    RAISE NOTICE '   - 7 мероприятий с разными статусами (2023-2028).';
    RAISE NOTICE '   - Статусы: completed, sold_out, published, canceled, draft.';
    RAISE NOTICE '   - Валюты: RUB (популярная), USD, EUR (редкие).';
    RAISE NOTICE '   - Сканирования: accepted и rejected.';
END $$;

COMMIT;