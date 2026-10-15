# Матрица выполнения расширенных требований

| Требование | Реализация | Артефакт |
|---|---|---|
| Фиксированный seed | `SEED` + детерминированные значения | `scripts/generate_data.sh` |
| 50–100 тыс. строк | 75 000 `ticket_scans` | `scripts/generate_data.sh` |
| ≥ 3 млн строк | 3 000 000 `ticket_scans` | `scripts/generate_data.sh` |
| FK и бизнес-ограничения | реальные ID, CHECK/FK, `publish_event`, `refund_ticket`, проверка количества | `scripts/generate_data.sh` |
| Разные даты и статусы | 5 событий, 5 статусов, разные даты; несколько статусов заказов/билетов | `docs/data-generator.md` |
| Популярные/редкие значения | `popular` и `rare`; skew 60/20/8/4/2/6 | `docs/data-generator.md` |
| 5 бизнес-запросов | Q1–Q5 | `queries/business_queries.sql` |
| ≥ 3 JOIN-запроса | все Q1–Q5 соединяют несколько таблиц | `queries/business_queries.sql` |
| ≥ 2 GROUP BY + aggregate | Q1–Q4 | `queries/business_queries.sql` |
| ≥ 1 HAVING | Q1 и Q3 | `queries/business_queries.sql` |
| Параметры и примеры результатов | параметры сохраняются отдельно, результаты запуска сохраняются в `artifacts/business/` | `scripts/run_business_queries.sh`, `docs/advanced-sql-benchmark.md` |
| Многошаговая транзакция | изменения events/categories/orders/items/tickets/payments | `queries/transaction_demo.sql` |
| Успешный COMMIT | отдельный сценарий + проверка | `queries/transaction_demo.sql` |
| Контролируемый ROLLBACK | вторая связанная цепочка откатывается и проверяется | `queries/transaction_demo.sql` |
| Конкурентное выполнение | две параллельные резервации квоты 1 | `scripts/concurrency_test.sh` |
| Защита бизнес-правила | `FOR UPDATE` в `app.reserve_zone_ticket()` + проверка одной активной записи | `scripts/concurrency_test.sh` |
| EXPLAIN до/после | две выборки `ticket_scans`, 5 запусков каждой фазы | `scripts/benchmark_queries.sh` |
| Медианное время | рассчитывается из нескольких запусков | `artifacts/query_benchmark/summary.txt` |
| Объяснение изменения плана | описание в отчёте, фактические узлы из сохранённых планов | `docs/advanced-sql-benchmark.md` |
| 2 стратегии массовой загрузки | `INSERT ... SELECT generate_series` и CSV + `COPY` | `scripts/compare_load.sh` |
| Ожидание блокировки | `SELECT ... FOR UPDATE` в двух сессиях | `scripts/lock_diagnostics.sh` |
| Диагностика блокировки | `pg_stat_activity`, `pg_blocking_pids()`, `pg_locks` | `artifacts/locks/diagnostics.txt` |
| Автоматизированный стенд | единый последовательный runner | `scripts/advanced_checks.sh` |
