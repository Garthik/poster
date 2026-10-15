#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-$("$ROOT_DIR/scripts/resolve_db_url.sh")}" 

psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/tests/stress_distribution.sql"
