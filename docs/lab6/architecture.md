# Архитектура и аудит исходной модели

## Что установлено при аудите

Lab5 использует `mongo:7.0`, БД `ticket_platform_docs`, root auth через приватный файл `lab5-mongo.env`, standalone volume `lab5_mongo_data`. Его Compose и скрипты не редактировались. Схема в `mongo/schema.js` допускает версии документов 1 и 2 (для страницы v2 нужен `readingMinutes`), ограничивает `pageSlugs` подборки 20 уникальными значениями и требует summary/sections для published-страницы.

|Коллекция|Поля, используемые в Sprint 6|Индексы Lab5, которые сохраняются|
|---|---|---|
|`event_pages`|`_id`, `pgEventId`, `status`, `editor.alias`, `headline`, `summary`, `sections`, `keywords`|`_id_`, `pgEventId_1`, `status_1_keywords_1`|
|`editorial_collections`|`_id`, `kind`, `title`, `pageSlugs`|`_id_`, `pageSlugs_1`|
|`visitor_feedback`|`_id`, `pageSlug`, `moderation`, `createdAt`, `rating`, `authorAlias`, `body`|`_id_`, `pageSlug_1_moderation_1`|

Новых бизнес-полей в этих трёх коллекциях нет. Служебная `lab6_publication_operations` хранит receipt операции (`_id`, `pageSlug`, `collectionId`), а `lab6_write_baseline`/`lab6_write_indexed` используются только для эксперимента с записью, с валидатором `visitor_feedback`. Все временные документы убираются. Временные ID зарезервированы префиксом `lab6-`.

## Топология

```text
PostgreSQL 16 ── Lab5 export pg_events.json ──> детерминированные редакционные fixtures Lab6
  источник истины                              отдельная БД/Compose, схема Lab5

                        Docker network ticket-platform-lab6_default
                    ┌─────────────────────────────────────────────────┐
WSL localhost:27101 ─┤ mongo1:27101 ─ отдельный lab6_mongo1 volume       │
WSL localhost:27102 ─┤ mongo2:27102 ─ отдельный lab6_mongo2 volume       │
WSL localhost:27103 ─┤ mongo3:27103 ─ отдельный lab6_mongo3 volume       │
                    │     rs0: PRIMARY + SECONDARY + SECONDARY        │
                    │ runner: Node.js 22 + mongodb 6.21.0, seed list  │
                    └─────────────────────────────────────────────────┘
                       keyfile и auth; 3 data-bearing voters
```

Роли выбираются динамически. Все участники имеют `votes:1`, `priority:1`; arbiter отсутствует. Время election timeout — 5000 ms; это учебный параметр, не SLA восстановления. `up` ждёт все три состояния через `replSetGetStatus` и проверяет реальные имена/голоса/health. Первый bootstrap выполняется из mongo1, но повторный запуск находит актуальный PRIMARY и не делает `rs.reconfig`.

Чистый официальный entrypoint сначала создаёт root user в локальной временной standalone-инстанции; затем запускает финальный mongod с keyfile и `--replSet rs0`. Healthcheck отличает финальный replica-set процесс от временного. Bootstrap аутентифицируется root, инициирует rs0 только при `NotYetInitialized`, ждёт выборов и создаёт app user с majority write concern. Вторичные узлы выполняют initial sync. Пароли существующего кластера не ротируются автоматически.

Имена из `rs.conf()` должны быть доступны драйверу **после discovery**, а не только в исходном seed list. Поэтому внутри и снаружи контейнеров применяются одинаковые имена и порты; для прямого WSL-клиента достаточно `127.0.0.1 mongo1 mongo2 mongo3` в `/etc/hosts`. Основной runner в Docker этого не требует.

## Сохранность предыдущих спринтов

Lab6 не подключается к `docker-compose.lab5.yml` и не монтирует его volume. Не выполняются `dropDatabase`, `dropCollection`, `down -v`, удаления чужих индексов или изменение PostgreSQL. Схема Lab5 повторно применяется только внутри **нового** rs0. Seed читает существующий PG snapshot, фиксирует IDs и SHA256, проверяет числа документов; это безопасное повторное заполнение отдельного Replica Set вместо рискованной конвертации standalone.

Сохранение исторического PG snapshot не гарантирует, что эти события всё ещё существуют в живом PostgreSQL: при необходимости актуализировать их выполните Lab5 sync. Между СУБД нет распределённой транзакции и MongoDB schema validation не создаёт FK.
