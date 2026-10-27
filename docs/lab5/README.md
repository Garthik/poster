# ЛР №5: SQL-аналитика PostgreSQL + документная модель MongoDB

Проект расширяет **существующий ticket-platform-sql**. Ничего из `app.orders`, `app.tickets`, резервного копирования и HA не переносится в MongoDB. В архиве сохраняется предыдущая ЛР №4, а новые файлы лежат в `mongo/`, `scripts/lab5/`, `tests/lab5/` и `docs/lab5/`.

## Требования к окружению

- PostgreSQL 16 из ЛР №4 (primary/HAProxy) **или** отдельный PostgreSQL из `docker-compose.yml`.
- `psql`, Python 3, Docker Compose, `openssl`; исходные миграции и seed уже применены.
- MongoDB 7 в отдельном Compose-проекте; порт `127.0.0.1:27018`, *с аутентификацией*.
- Разработческий seed для полноценной проверки аналитики: **75 000** строк `app.ticket_scans`. Нагрузочные 3 млн строк не обязательны для ЛР №5.

## Запуск из WSL

```bash
cd /mnt/c/TomeD/VSCode/Proga/Afisha/poster
# После распаковки нового архива или копирования новых файлов в проект:
./scripts/lab5.sh init
./scripts/lab5.sh up

# Для HA-стенда: миграция на действующем primary (порт HAProxy 5436).
# Для исходной топологии также подходит ./scripts/ha.sh migrate.
export TICKET_SECRETS_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"
source "$TICKET_SECRETS_DIR/roles.env"
export PGPASSWORD="$TICKET_ADMIN_PASSWORD"
export DB_URL="host=localhost port=5436 dbname=ticket_platform user=ticket_admin sslmode=verify-full sslrootcert=$TICKET_SECRETS_DIR/tls/ca.crt"
./scripts/migrate.sh

# Начальные справочники и события, если база чистая:
./scripts/ha.sh seed
# Важно: генерировать от имени ticket_app (требуемый GRANT).
# При имеющемся development-наборе пропусти генерацию.
source "$TICKET_SECRETS_DIR/roles.env"
PGPASSWORD="$TICKET_APP_PASSWORD" \
DB_URL="host=localhost port=5436 dbname=ticket_platform user=ticket_app sslmode=verify-full sslrootcert=$TICKET_SECRETS_DIR/tls/ca.crt" \
SEED=20261004 ./scripts/generate_data.sh development

# Все проверки. SQL запустится от ticket_admin по DB_URL выше:
./scripts/lab5.sh all

# Опционально: пример перехода версий документов v1 -> v2:
./scripts/lab5.sh evolve
./scripts/lab5.sh validation
```

Если PostgreSQL не в HA, передай собственный `DB_URL` с реальными credentials (например, `export DB_URL=...`), затем выполни миграцию и `./scripts/lab5.sh all`. Команда `all` **сама не генерирует миллионы строк** и не удаляет предыдущие данные.

Важное замечание: `./scripts/ha.sh migrate` из ЛР №4 подключается к **фиксированному первому узлу `5434`**. После failover используй `./scripts/migrate.sh` с `DB_URL` к текущему primary через HAProxy. Не применяй миграции к standby.

## Основные команды

| Команда | Что проверяет |
|---|---|
| `./scripts/lab5.sh sql` | Каталог Q1–Q8, SQL ASSERT-проверки семантики |
| `./scripts/lab5.sh schema` | 3 коллекции, `$jsonSchema`, индексы |
| `./scripts/lab5.sh sync` | 2–3 существующих PostgreSQL events → редакционные документы в Mongo |
| `./scripts/lab5.sh crud` | CRUD во всех коллекциях, автоматическая уборка тестовых документов |
| `./scripts/lab5.sh validation` | 3 ошибочные вставки запрещены, M:N и 1:N ссылки валидны |
| `./scripts/lab5.sh compare` | На **одинаковых документах** результат Mongo запросов равен JSONB SELECT |
| `./scripts/lab5.sh evolve` | Миграция event_pages v1 → v2 с `readingMinutes` |
| `./scripts/lab5.sh down` | Остановка только MongoDB; PG/HA и данные Mongo не удаляются |

Логи: `artifacts/lab5/sql_catalog_results.txt`, `sql_assertions.txt`, `pg_events.json`, `mongo_pages.jsonl`, `mongo_cards.json`, `postgres_cards.json`, `comparison.txt`.

## Краткая структура

- `queries/business_queries.sql` — полный каталог **8** запросов.
- `migrations/003_lab5_comparison.sql` — только тестовая **JSONB-проекция** редакционных документов.
- `mongo/schema.js` — MongoDB `$jsonSchema`, ограничения, индексы.
- `mongo/sync_from_pg.js`, `crud.js`, `validation_test.js`, `export_comparison.js`, `migrate_v2.js`.
- `docs/lab5/ownership-and-model.md` — границы владения, 1:N, M:N, embed/ref.
- `docs/lab5/decisions.md` — ADR с плюсами/минусами, JSONB vs Mongo, обновления.
- `docs/lab5/query-catalog.md` — 8 бизнес-вопросов, параметры, конструкции.

## Проверка результата в Mongo Shell

```bash
# Mongo credentials хранятся здесь (НЕ коммитить):
# ~/.local/share/ticket-platform-ha/lab5-mongo.env
./scripts/lab5.sh schema
./scripts/lab5.sh sync
./scripts/lab5.sh validation
```

Для просмотра документов через `mongosh` используй `docker compose -f docker-compose.lab5.yml exec mongo mongosh` с корректными `-u/-p`, либо MongoDB Compass через локальный порт `27018`. Пароль из приватного файла не показывай преподавателю.

## Ограничения

- **Нет распределённой ACID-транзакции** между PostgreSQL и MongoDB. Страница может ссылаться на удалённое PG-событие до обработки события удаления. Референциальная целостность проверяется прикладным кодом / синхронизацией; `schema validation` MongoDB не создаёт FK.
- `mongodb` запущена на loopback с root-логином — **учебная конфигурация**. Для production нужны отдельные least-privilege Mongo users, TLS и резервирование Mongo.
- PostgreSQL JSONB — только *сравнительный снимок*, а **не** дублирующий источник истины.
- На 25 октября 2026 г. выполнена статическая проверка кода; Docker/PostgreSQL/mongosh в текущей среде недоступны, результаты полного запуска получаются в WSL пользователя.
