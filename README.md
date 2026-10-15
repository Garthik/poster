# Лабораторная №4: безопасный PostgreSQL и High Availability

**Новая реализация:** `docker-compose.ha.yml`, `scripts/ha.sh`, `infra/ha/` и `docs/lab4-ha.md`.
Старый `docker-compose.yml` и команды для ЛР2/3 оставлены для совместимости,
но они демонстрационные и **не удовлетворяют** требованиям ЛР4 по ролям/TLS.
Для сдачи ЛР4 использовать только команды HA.

```bash
# Если прежний compose занимает порт 5434, остановить его без удаления томов:
docker compose -f docker-compose.yml down

./scripts/ha.sh init
./scripts/ha.sh up
./scripts/ha.sh roles
./scripts/ha.sh migrate
./scripts/ha.sh seed
./scripts/ha.sh replica
./scripts/ha.sh status
./scripts/ha.sh replcheck
./scripts/ha.sh check
./scripts/ha.sh backup
./scripts/ha.sh restore
./scripts/ha.sh lag development
# Аварийный тест запускать ПОСЛЕДНИМ — он переводит replica в новый primary:
./scripts/ha.sh demo
```

**Полные инструкции:** [ЛР4 — setup и проверки](docs/lab4-ha.md), [runbook](docs/ha-runbook.md),
[критерии приёмки](docs/ha-acceptance.md). Пароли/приватные сертификаты и backup создаются вне репозитория.

---

# Платформа продажи билетов — PostgreSQL / Лабораторная работа

Реализация первого этапа проекта по курсу «Системы управления базами данных» на основе аналитического документа платформы продажи билетов.

## Что реализовано

- логическая реляционная модель;
- PostgreSQL-схема с PK/FK/UNIQUE/CHECK/identity;
- 3НФ с отдельным решением об осознанной денормализации финансового снимка заказа;
- версионируемые миграции `001_init.sql` и `002_event_description.sql`;
- согласованный тестовый набор данных;
- сценарии жизненного цикла мероприятия, заказа и билета;
- негативные тесты ограничений целостности и бизнес-правил (16 сценариев);
- автоматическая проверка схемы;
- проверка чистой установки и обновления `v1 -> v2`;
- матрица владельцев данных и бизнес-сценариев.

## Структура

```text
migrations/                 Версионируемые миграции
seeds/                      Тестовые данные
scripts/                    Запуск миграций и тестов
tests/                      Проверки схемы и бизнес-ограничений
docs/                       Логическая модель, 3НФ, жизненный цикл, матрица
docker-compose.yml          Локальный PostgreSQL 16
Makefile                    Команды проекта
```

## Запуск

Требования: Docker Compose и `psql`. Скрипты `migrate.sh`, `check_schema.sh`, `run_tests.sh` и `test_migrations.sh` используют `DB_URL` и возвращают ненулевой код при первой ошибке.

```bash
make up
make migrate
make seed
./scripts/run_tests.sh
```

По умолчанию PostgreSQL публикуется на `localhost:5434` (`${POSTGRES_HOST_PORT:-5434}:5432`). Все скрипты автоматически определяют фактически опубликованный Docker-порт через `scripts/resolve_db_url.sh`. При необходимости можно явно задать `DB_URL`.

Полная автоматическая проверка чистой установки и обновления:

```bash
./scripts/test_migrations.sh
```

Или:

```bash
make all-checks
```

## Скрипты автоматизации

- `scripts/migrate.sh` — применяет только неприменённые миграции по порядку; поддерживает `--target VERSION` для проверки предыдущего состояния.
- `scripts/check_schema.sh` — запускает структурную проверку схемы из `tests/schema.sql`.
- `scripts/run_tests.sh` — последовательно запускает проверку схемы, негативные тесты и сценарии жизненного цикла.
- `scripts/test_migrations.sh` — создаёт временные базы, проверяет clean install, `001 -> 002`, повторный запуск миграций и тесты после upgrade.

## Миграции

`001_init` создаёт всю схему с нуля и регистрируется в `app.schema_migrations`.

`002_event_description` - безопасное backward-compatible изменение: добавляет nullable `events.description`, не ломая старую версию приложения.

Пример обновления:

```bash
DB_URL=postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform \
  ./scripts/migrate.sh
```

## Жизненный цикл

### Event

`draft -> published -> sold_out -> completed / canceled`

Публикация выполняется через `app.publish_event()` и запрещена без категории с положительной квотой.

### Order

`created -> pending_payment -> paid -> refunded / failed`

### Ticket

`reserved -> valid -> scanned -> expired / annulled`

Резервирование зоны/категории выполняется через `app.reserve_zone_ticket()`, оплата переводит билет в `valid`, проверка входа - в `scanned`.

## Важная оговорка по Redis

Аналитический документ выбирает Redis Lock с TTL 15 минут для бронирования. В этой лабораторной работа направлена на PostgreSQL-схему, поэтому SQL-ограничения выступают источником реляционной целостности. На следующем этапе application service должен выполнять Redis-блокировку до вызова транзакционной операции PostgreSQL.

## Матрица требований

Подробное соответствие каждого пункта задания конкретным файлам находится в `docs/requirements-matrix.md`.

## Расширенные SQL-сценарии

Для большого набора данных и требований по SQL/конкурентности используется `docs/advanced-sql-benchmark.md`.

Основные команды:

```bash
make generate-dev
make generate-load
make business-queries
make transaction-demo
make concurrency-test
make lock-diagnostics
make benchmark
make compare-load
make advanced-checks
```

Артефакты benchmark и диагностики сохраняются в каталоге `artifacts/`.

## Stress-набор и базовые бизнес-запросы

Для неравномерного распределения данных добавлен исходный файл `seeds/003_stress_distribution.sql`. Он сохранён без изменений. Для запуска с текущей схемой используется адаптер:

```bash
./scripts/seed_stress_safe.sh
./scripts/check_stress_distribution.sh
```

Пять базовых бизнес-запросов находятся в `queries/business_queries.sql`.

```bash
make queries
```

Описание бизнес-вопросов, параметров и примеров результата: `docs/business-queries.md`.

Проверка требований к stress-набору: `tests/stress_distribution.sql`.

### Без изменения присланных файлов

Контрольные копии пользователя сохранены без изменения: `Makefile` и `seeds/003_stress_distribution.sql` совпадают с исходными файлами. В обычном `Makefile` цель `seed-stress` запускает именно присланный SQL-файл напрямую. Для текущей схемы, где используется составной FK `(category_id, event_id)`, рекомендуется `Makefile.safe`:

```bash
make -f Makefile.safe seed-stress
make -f Makefile.safe stress-check
make -f Makefile.safe queries
```
