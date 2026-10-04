.PHONY: up down clean migrate seed check-schema test test-constraints test-lifecycle all-checks generate-dev generate-load

up:
	docker compose up -d postgres

down:
	docker compose down

clean:
	docker compose down -v

migrate:
	./scripts/migrate.sh

seed:
	psql "$${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}" -v ON_ERROR_STOP=1 -f seeds/002_seed_data.sql

check-schema:
	./scripts/check_schema.sh

test-constraints:
	psql "$${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}" -v ON_ERROR_STOP=1 -f tests/constraints.sql

test-lifecycle:
	psql "$${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}" -v ON_ERROR_STOP=1 -f tests/lifecycle.sql

test:
	./scripts/run_tests.sh

all-checks:
	./scripts/test_migrations.sh

generate-dev:
	./scripts/generate_data.sh development

generate-load:
	./scripts/generate_data.sh load