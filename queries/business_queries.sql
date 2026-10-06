\echo 'Q1. Какие мероприятия дали выручку не ниже заданного порога?'
\if :{?from_ts}
\else
\set from_ts '2023-01-01 00:00:00+00'
\endif
\if :{?to_ts}
\else
\set to_ts '2029-01-01 00:00:00+00'
\endif
\if :{?min_revenue}
\else
\set min_revenue 10000
\endif

SELECT
    e.id AS event_id,
    e.name,
    e.status,
    COUNT(DISTINCT o.id) AS paid_orders,
    COUNT(oi.id) AS items,
    SUM(oi.unit_price) AS gross_sales
FROM app.events e
JOIN app.orders o
  ON o.event_id = e.id
JOIN app.order_items oi
  ON oi.order_id = o.id
 AND oi.event_id = e.id
WHERE o.status = 'paid'
  AND o.created_at >= :'from_ts'::timestamptz
  AND o.created_at <  :'to_ts'::timestamptz
GROUP BY e.id, e.name, e.status
HAVING SUM(oi.unit_price) >= :'min_revenue'::numeric
ORDER BY gross_sales DESC, e.id;

\echo 'Q2. Сколько принятых и отклонённых проходов приходится на каждый час?'
\if :{?scan_from}
\else
\set scan_from '2027-01-01 00:00:00+00'
\endif
\if :{?scan_to}
\else
\set scan_to '2029-01-01 00:00:00+00'
\endif
\if :{?event_like}
\else
\set event_like '%'
\endif

SELECT
    e.id AS event_id,
    e.name,
    date_trunc('hour', s.scanned_at) AS scan_hour,
    COUNT(*) FILTER (WHERE s.result = 'accepted') AS accepted_scans,
    COUNT(*) FILTER (WHERE s.result = 'rejected') AS rejected_scans,
    COUNT(*) AS total_scans
FROM app.ticket_scans s
JOIN app.tickets t
  ON t.id = s.ticket_id
JOIN app.events e
  ON e.id = t.event_id
WHERE s.scanned_at >= :'scan_from'::timestamptz
  AND s.scanned_at <  :'scan_to'::timestamptz
  AND e.name ILIKE :'event_like'
GROUP BY e.id, e.name, date_trunc('hour', s.scanned_at)
ORDER BY scan_hour, e.id;

\echo 'Q3. Какие покупатели имеют не менее заданного количества оплаченных заказов?'
\if :{?min_orders}
\else
\set min_orders 5
\endif

SELECT
    u.id AS user_id,
    u.email,
    COUNT(DISTINCT o.id) AS paid_orders,
    SUM(o.total_amount) AS paid_amount,
    COUNT(DISTINCT e.id) AS different_events
FROM app.users u
JOIN app.orders o
  ON o.user_id = u.id
JOIN app.events e
  ON e.id = o.event_id
WHERE u.role = 'buyer'
  AND o.status = 'paid'
GROUP BY u.id, u.email
HAVING COUNT(DISTINCT o.id) >= :'min_orders'::integer
ORDER BY paid_orders DESC, paid_amount DESC, u.id;

\echo 'Q4. Какова заполненность квоты каждой категории?'
SELECT
    e.id AS event_id,
    e.name AS event_name,
    tc.id AS category_id,
    tc.name AS category_name,
    tc.quota,
    COUNT(t.id) FILTER (WHERE t.status IN ('reserved', 'valid', 'scanned')) AS active_tickets,
    ROUND(
        100.0 * COUNT(t.id) FILTER (WHERE t.status IN ('reserved', 'valid', 'scanned'))
        / NULLIF(tc.quota, 0),
        2
    ) AS utilization_percent
FROM app.events e
JOIN app.ticket_categories tc
  ON tc.event_id = e.id
LEFT JOIN app.tickets t
  ON t.event_id = e.id
 AND t.category_id = tc.id
GROUP BY e.id, e.name, tc.id, tc.name, tc.quota
HAVING COUNT(t.id) FILTER (WHERE t.status IN ('reserved', 'valid', 'scanned')) > 0
ORDER BY utilization_percent DESC, e.id, tc.id;

\echo 'Q5. Какие сочетания валюты и статуса оплаты дают наибольшие суммы, включая возвраты?'
WITH refunds_by_order AS (
    SELECT
        o.id AS order_id,
        COALESCE(SUM(r.amount), 0) AS refunded_amount
    FROM app.orders o
    JOIN app.order_items oi
      ON oi.order_id = o.id
    JOIN app.tickets t
      ON t.order_item_id = oi.id
    LEFT JOIN app.refunds r
      ON r.ticket_id = t.id
     AND r.status = 'approved'
    GROUP BY o.id
)
SELECT
    e.name AS event_name,
    p.currency,
    p.status AS payment_status,
    COUNT(*) AS payments_count,
    SUM(p.amount) AS payment_amount,
    SUM(COALESCE(rbo.refunded_amount, 0)) AS refunded_amount
FROM app.payments p
JOIN app.orders o
  ON o.id = p.order_id
JOIN app.events e
  ON e.id = o.event_id
LEFT JOIN refunds_by_order rbo
  ON rbo.order_id = o.id
GROUP BY e.name, p.currency, p.status
ORDER BY payment_amount DESC, event_name, p.currency, p.status;
