# Расширенный SQL, транзакции, конкуренция и benchmark

Этот набор является продолжением генератора тестовых данных. Исходные миграции `001_init.sql` и `002_event_description.sql` не изменяются; индексы для оптимизации создаются отдельным benchmark-скриптом.

## 1. Генерация данных

Файл: `scripts/generate_data.sh`.

```bash
SEED=20261004 ./scripts/generate_data.sh development
SEED=20261004 ./scripts/generate_data.sh load
```

`development` создаёт 75 000 строк в `app.ticket_scans`, `load` — 3 000 000.

Генератор создаёт пять событий с различными статусами и датами, несколько состояний заказов и билетов, а также неравномерное распределение сканов. Основной skew задаётся как 60% / 20% / 8% / 4% / 2% / 6% между 12 валидными билетами. Доля `rejected` — 3%, `accepted` — 97%.

Все внешние ключи генерируются из реально существующих ID. Для опубликованных событий создаётся положительная квота. Для возвращённого билета используется `app.refund_ticket()`, поэтому серверное бизнес-правило возврата также проверяется.

## 2. Пять базовых бизнес-запросов

Файл: `queries/business_queries.sql`.

| № | Бизнес-вопрос | Параметры | Таблицы | Агрегаты |
|---|---|---|---|---|
| Q1 | Какие мероприятия дают не менее заданной выручки за период? | `from_ts`, `to_ts`, `min_revenue` | `events`, `orders`, `order_items` | `COUNT`, `SUM`, `GROUP BY`, `HAVING` |
| Q2 | Как распределены проходы по часам и результатам? | `event_id`, `scan_from`, `scan_to` | `ticket_scans`, `tickets`, `events` | `COUNT`, `GROUP BY` |
| Q3 | Какие покупатели сделали не менее N оплаченных заказов? | `min_orders` | `users`, `orders`, `events` | `COUNT`, `SUM`, `GROUP BY`, `HAVING` |
| Q4 | Насколько заполнены квоты категорий? | без обязательных параметров | `events`, `ticket_categories`, `tickets` | `COUNT`, `GROUP BY` |
| Q5 | Какие оплаты были неуспешными или возвращены? | без обязательных параметров | `orders`, `events`, `payments` | нет |

Пример результата Q1:

```text
 event_id | name                                      | status    | paid_orders | items | gross_sales
----------+-------------------------------------------+-----------+-------------+-------+------------
      ... | Generated load dataset seed=20261004 ... | published |          12 |    12 |     1200.00
```

Для полной 3-миллионной выборки Q2 в пределах всего окна генерации ожидаются `2910000 accepted` и `90000 rejected`.

Пример результата Q3:

```text
 user_id | email             | paid_orders | paid_amount | different_events
---------+-------------------+-------------+-------------+-----------------
       2 | buyer@example.com |          12 |     1320.00 |               1
```

Пример результата Q4:

```text
 event_name                                  | category_name | quota | active_tickets | utilization_percent
----------------------------------------------+---------------+-------+----------------+--------------------
 Generated load dataset seed=20261004 popular | Popular zone  |    20 |             17 |              85.00
```

Q1 и Q3 содержат `HAVING`. Q1–Q4 используют группировку и агрегаты. Все пять запросов используют соединение нескольких таблиц.

Запуск:

```bash
./scripts/run_business_queries.sh
```

Результат сохраняется в `artifacts/business/`.

## 3. Многошаговая транзакция

Файл: `queries/transaction_demo.sql`.

Успешная транзакция изменяет `events`, `ticket_categories`, `orders`, `order_items`, `tickets` и `payments`, причём резервирование выполняется через `app.reserve_zone_ticket()`, а оплата — через `app.pay_order()`. Затем та же связанная цепочка для второго события откатывается командой `ROLLBACK`.

Запуск:

```bash
./scripts/run_transaction_demo.sh
```

Ожидаемый факт rollback: `rolled_back_events = 0`.

## 4. Конкурентное выполнение

Файл: `scripts/concurrency_test.sh`.

Проверяемое правило: при `quota = 1` две конкурентные операции не должны успешно зарезервировать два билета.

`app.reserve_zone_ticket()` блокирует строку категории через `FOR UPDATE`. Первая сессия после резерва удерживает транзакцию 2 секунды. Вторая сессия успевает войти в ожидание, после коммита первой видит занятую квоту и завершается с контролируемой ошибкой.

Ожидается:

```text
session_A_exit=0
session_B_exit=1
PASS: quota=1 protected against concurrent double reservation.
```

## 5. EXPLAIN до и после оптимизации

Файл: `scripts/benchmark_queries.sh`.

Профилируются два запроса:

- Q1 — число сканов выбранного контроллера за короткий интервал;
- Q2 — число сканов по часам за тот же интервал.

До оптимизации удаляются только два индексa benchmark-сценария. После первой серии выполняется:

```sql
CREATE INDEX ticket_scans_controller_time_idx
    ON app.ticket_scans (controller_id, scanned_at DESC);

CREATE INDEX ticket_scans_time_result_idx
    ON app.ticket_scans (scanned_at, result);
```

После `ANALYZE` запросы выполняются повторно.

План и времена сохраняются в:

```text
artifacts/query_benchmark/before/
artifacts/query_benchmark/after/
artifacts/query_benchmark/summary.txt
```

По умолчанию выполняется 5 запусков. В `summary.txt` фиксируется медиана.

Типичный эффект: до индекса PostgreSQL рассматривает чтение большой части `ticket_scans`, после индекса появляется возможность использовать `Index Scan`/`Bitmap Index Scan` по селективному диапазону. Фактический узел плана и количество buffers берутся из сохранённых `EXPLAIN (ANALYZE, BUFFERS)` и не подменяются заранее придуманными цифрами.

Запуск:

```bash
RUNS=5 ./scripts/benchmark_queries.sh
```

## 6. Сравнение массовой загрузки

Файл: `scripts/compare_load.sh`.

Сравниваются две стратегии:

1. `INSERT ... SELECT generate_series(...)` внутри PostgreSQL.
2. Подготовка CSV на клиенте и `COPY` в PostgreSQL.

По умолчанию — 300 000 строк:

```bash
ROWS=500000 ./scripts/compare_load.sh
```

Реальное время обеих стратегий выводит `psql \timing`. CSV и лог сохраняются в `artifacts/load_compare/`.

## 7. Ожидание блокировки и диагностика

Файл: `scripts/lock_diagnostics.sh`.

Одна сессия захватывает строку `events` через `SELECT ... FOR UPDATE` и удерживает её 5 секунд. Вторая пытается получить тот же lock. Пока она ждёт, отдельная сессия читает `pg_stat_activity`, `pg_blocking_pids()` и `pg_locks`.

Диагностический результат сохраняется в `artifacts/locks/diagnostics.txt`.

## 8. Автоматизированный воспроизводимый стенд

Общий раннер:

```bash
./scripts/advanced_checks.sh
```

Он запускает бизнес-запросы, COMMIT/ROLLBACK, concurrency-тест, lock diagnostics, EXPLAIN benchmark и сравнение массовой загрузки.

Для полного сценария:

```bash
SEED=20261004 ./scripts/generate_data.sh load
RUNS=5 ROWS=300000 ./scripts/advanced_checks.sh
```

Основные результаты сохраняются в `artifacts/`, а параметры стенда задаются переменными `SEED`, `RUNS` и `ROWS`.
