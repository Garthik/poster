#!/usr/bin/env bash
set -euo pipefail
DB_URL="${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}"
mkdir -p artifacts/stress
psql "$DB_URL" -v ON_ERROR_STOP=1 -f tests/stress_distribution.sql | tee artifacts/stress/stress_distribution.txt
