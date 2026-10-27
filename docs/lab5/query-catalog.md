# Каталог 8 SQL-запросов PostgreSQL

Файл исполнения — `queries/business_queries.sql`. SQL выполнен для существующей схемы `app`; `\set` и `\echo` — команды **psql**, не синтаксис Query Tool pgAdmin. В pgAdmin следует заменить `:'param'` на literal или пользоваться `run_business_queries.sh`.

| № | Бизнес-вопрос | Таблицы | Параметры | Особенности |
|---|---|---|---|---|
| Q1 | Какие мероприятия принесли выручку выше порога? | events, orders, order_items | from_ts, to_ts, min_revenue | JOIN, SUM, COUNT, GROUP BY, **HAVING** |
| Q2 | Как менялось число принятых/отклонённых сканов по часам? | ticket_scans, tickets, events | scan_from, scan_to, event_like | JOIN, COUNT FILTER, GROUP BY |
| Q3 | Кто из покупателей сделал минимум N оплаченных заказов? | users, orders, events | min_orders | JOIN, GROUP BY, **HAVING** |
| Q4 | Какая часть квоты каждой категории уже занята? | events, ticket_categories, tickets | нет | JOIN, COUNT FILTER, GROUP BY, HAVING |
| Q5 | Каково соотношение платежей и возвратов? | payments, orders, events, order_items, tickets, refunds | нет | **CTE**, SUM, GROUP BY |
| Q6 | Какие категории дают максимальный доход в своём мероприятии? | events, ticket_categories, tickets | нет | **CTE**, **DENSE_RANK OVER**, SUM OVER |
| Q7 | Насколько поток входов отличается от прошлого часа? | ticket_scans, tickets, events | scan_from, scan_to | **CTE**, **LAG OVER**, условный COUNT |
| Q8 | Как растёт выручка события по мере оплаченных заказов? | orders, events | from_ts, to_ts | **ROW_NUMBER OVER**, **SUM OVER ROWS** |

Требования: агрегаты **8/8**, оконные функции **Q6/Q7/Q8**, ранжирование **Q6**, LAG **Q7**, накопительный агрегат **Q8**, CTE **Q5/Q6/Q7**, JOIN **8/8**.

## Пример формы результата

**Q6**: `event_id`, `category_name`, `sold_tickets`, `revenue`, `revenue_rank`, `event_revenue_percent` (1 — наиболее доходная категория события).

**Q7**: `event_id`, `scan_hour`, `attempts`, `rejected`, `previous_hour_attempts`, `change_from_previous_hour`. Для первого часа `previous_hour_attempts` = NULL.

**Q8**: `event_id`, `order_id`, `created_at`, `total_amount`, `order_number`, `cumulative_revenue`. Последнее значение для каждого мероприятия равно сумме его оплаченных заказов за выбранный период.

Фактические результаты создаются в `artifacts/lab5/sql_catalog_results.txt`. `tests/lab5/sql_assertions.sql` автоматически доказывает: `accepted+rejected=total`, отсутствие квоты меньше нуля / overbooking, корректность рангов, `LAG` и итогов накопительной суммы. Успех означает отсутствие EXCEPTION и появление нескольких `PASS`-уведомлений.
