# Подключение расширенной части задания

Набор рассчитан на текущий `ticket-platform-sql` с каталогами `scripts/`, `queries/`, `docs/` и существующим `Makefile`.

## 1. Скопировать файлы

Добавить новые SQL-запросы в `queries/`, shell-скрипты в `scripts/`, документацию в `docs/`, а `Makefile` заменить версией из набора. Текущий генератор `scripts/generate_data.sh` также приложен: используется версия с пятью событиями, разными статусами/датами и skew-распределением.

## 2. Подготовить БД

```bash
make up
make migrate
make seed
```

## 3. Сгенерировать нагрузку

```bash
SEED=20261004 ./scripts/generate_data.sh load
```

Проверка:

```sql
SELECT count(*)
FROM app.ticket_scans s
JOIN app.tickets t ON t.id = s.ticket_id
JOIN app.order_items oi ON oi.id = t.order_item_id
JOIN app.orders o ON o.id = oi.order_id
JOIN app.events e ON e.id = o.event_id
WHERE e.name = 'Generated load dataset seed=20261004 popular event';
```

Ожидается `3000000`.

## 4. Выполнить отдельные требования

```bash
./scripts/run_business_queries.sh
./scripts/run_transaction_demo.sh
./scripts/concurrency_test.sh
./scripts/lock_diagnostics.sh
RUNS=5 ./scripts/benchmark_queries.sh
ROWS=300000 RUNS=3 ./scripts/compare_load.sh
```

## 5. Один автоматизированный прогон

```bash
SEED=20261004 MODE=load GENERATE=1 RUNS=5 ROWS=300000 \
  ./scripts/advanced_checks.sh
```

## 6. Что сдавать

Основные исходные артефакты: `scripts/generate_data.sh`, `docs/data-generator.md`, `queries/business_queries.sql`, `queries/transaction_demo.sql`, `scripts/concurrency_test.sh`, `scripts/benchmark_queries.sh`, `scripts/compare_load.sh`, `scripts/lock_diagnostics.sh`, `scripts/advanced_checks.sh` и `docs/advanced-sql-benchmark.md`.

После запуска добавляются фактические доказательства: `artifacts/business/*`, `artifacts/query_benchmark/*`, `artifacts/load_compare/*` и `artifacts/locks/*`.

Фактические времена и планы не фиксированы в исходниках, поскольку они зависят от конкретного экземпляра PostgreSQL; стенд воспроизводимо генерирует их на машине сдачи.
