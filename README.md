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
docker compose up -d postgres
./scripts/migrate.sh
psql "postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform" -f seeds/002_seed_data.sql
./scripts/run_tests.sh
```

Полная автоматическая проверка чистой установки и обновления:

```bash
./scripts/test_migrations.sh
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
