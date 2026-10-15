# Матрица выполнения задания

| Требование | Реализация |
|---|---|
| Логическая модель PostgreSQL | `docs/logical-model.md`, `docs/er-diagram.md`, `migrations/001_init.sql` |
| Таблицы, атрибуты, PK/FK, кардинальности | `migrations/001_init.sql`, `docs/logical-model.md` |
| 3НФ | `docs/normalization.md` |
| Намеренная денормализация | Снимок сумм в `orders`, обоснование в `docs/normalization.md` |
| Версионируемые миграции | `migrations/001_init.sql`, `migrations/002_event_description.sql` |
| NOT NULL / UNIQUE / CHECK / FK / identity | `migrations/001_init.sql` |
| Тестовые данные | `seeds/002_seed_data.sql` |
| Жизненный цикл 3+ сущностей | `tests/lifecycle.sql`, `docs/lifecycle-scenarios.sql` |
| Негативные примеры 5+ ограничений | 8 проверок в `tests/constraints.sql` |
| Автоматическая проверка схемы | `scripts/check_schema.sh`, `tests/schema.sql` |
| Безопасное обновление схемы | `002_event_description.sql`: additive nullable change |
| Матрица таблица -> владелец -> сценарий | `docs/data-ownership-matrix.md` |
| Сравнение нормализованной/денормализованной модели | `docs/normalization.md` |
| Чистая установка и upgrade предыдущей версии | `scripts/test_migrations.sh` |
