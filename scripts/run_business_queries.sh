#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}"
OUT_DIR="artifacts/business"
mkdir -p "$OUT_DIR"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

psql "$DB_URL" \
  -v ON_ERROR_STOP=1 \
  -v from_ts="${FROM_TS:-2023-01-01 00:00:00+00}" \
  -v to_ts="${TO_TS:-2029-01-01 00:00:00+00}" \
  -v min_revenue="${MIN_REVENUE:-10000}" \
  -v scan_from="${SCAN_FROM:-2027-01-01 00:00:00+00}" \
  -v scan_to="${SCAN_TO:-2029-01-01 00:00:00+00}" \
  -v event_like="${EVENT_LIKE:-%}" \
  -v min_orders="${MIN_ORDERS:-5}" \
  -f queries/business_queries.sql \
  | tee "$OUT_DIR/business_queries.txt"
