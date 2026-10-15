#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-$("$ROOT_DIR/scripts/resolve_db_url.sh")}"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

mkdir -p "$ROOT_DIR/artifacts/business"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/queries/transaction_demo.sql" \
    | tee "$ROOT_DIR/artifacts/business/transaction_demo.txt"
