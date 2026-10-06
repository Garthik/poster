#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}"
SOURCE="$(cd "$(dirname "$0")/.." && pwd)/seeds/003_stress_distribution.sql"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}
command -v python3 >/dev/null 2>&1 || {
    echo "ERROR: python3 is required" >&2
    exit 127
}

TMP_SQL="$(mktemp)"
trap 'rm -f "$TMP_SQL"' EXIT

python3 - "$SOURCE" "$TMP_SQL" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")

needle = """    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)\n    VALUES (v_future_event_2_id, 'Premium Front Row', 'seat', 8000.00, 20) RETURNING id INTO v_premium_cat_id;\n"""
insert = needle + """
    -- Compatibility categories for the current composite category/event FK.
    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_future_event_1_id, 'Jazz Night Standard', 'zone', 3000.00, 500);

    INSERT INTO app.ticket_categories (event_id, name, type, price, quota)
    VALUES (v_future_event_2_id, 'Longtail Admission', 'zone', 3000.00, 1000);

    -- The original stress file inserts many tickets directly rather than through
    -- reserve_zone_ticket(); keep the generated final state within category quotas.
    UPDATE app.ticket_categories
       SET quota = 2000
     WHERE id = v_standard_cat_id;
"""
if needle not in source:
    raise SystemExit("Expected category block was not found")
source = source.replace(needle, insert, 1)

old_regular = """    INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)\n    SELECT o.id, o.event_id, v_standard_cat_id, 3000.00\n"""
new_regular = """    INSERT INTO app.order_items (order_id, event_id, category_id, unit_price)\n    SELECT o.id, o.event_id,\n           CASE\n               WHEN o.event_id = v_past_event_id THEN v_past_cat_id\n               WHEN o.event_id = v_future_event_1_id THEN (\n                   SELECT tc.id\n                     FROM app.ticket_categories tc\n                    WHERE tc.event_id = v_future_event_1_id\n                      AND tc.name = 'Jazz Night Standard'\n               )\n               ELSE v_standard_cat_id\n           END,\n           3000.00\n"""
if old_regular not in source:
    raise SystemExit("Expected regular order_items block was not found")
source = source.replace(old_regular, new_regular, 1)

old_longtail = """           CASE WHEN o.event_id = v_past_event_id THEN v_past_cat_id\n                WHEN o.event_id = v_future_event_2_id THEN v_premium_cat_id\n                ELSE v_standard_cat_id END,\n"""
new_longtail = """           CASE\n               WHEN o.event_id = v_past_event_id THEN v_past_cat_id\n               WHEN o.event_id = v_future_event_2_id THEN (\n                   SELECT tc.id\n                     FROM app.ticket_categories tc\n                    WHERE tc.event_id = v_future_event_2_id\n                      AND tc.name = 'Longtail Admission'\n               )\n               WHEN o.event_id = v_future_event_1_id THEN (\n                   SELECT tc.id\n                     FROM app.ticket_categories tc\n                    WHERE tc.event_id = v_future_event_1_id\n                      AND tc.name = 'Jazz Night Standard'\n               )\n               ELSE v_standard_cat_id\n           END,\n"""
if old_longtail not in source:
    raise SystemExit("Expected longtail category block was not found")
source = source.replace(old_longtail, new_longtail, 1)

# PostgreSQL ambiguity fix: the immutable source declares PL/pgSQL variable `i`,
# while two generate_series queries also alias their output column as `i`.
# Qualify the generated-series column without modifying the source file itself.
source = source.replace(
    "SELECT 'regular_' || i || '@example.com', '$2b$12$regular-hash', 'buyer'\n    FROM generate_series(1, 10) AS i",
    "SELECT 'regular_' || gs.n || '@example.com', '$2b$12$regular-hash', 'buyer'\n    FROM generate_series(1, 10) AS gs(n)",
    1,
)
source = source.replace(
    "SELECT 'longtail_' || i || '@example.com', '$2b$12$longtail-hash', 'buyer'\n    FROM generate_series(1, 500) AS i",
    "SELECT 'longtail_' || gs.n || '@example.com', '$2b$12$longtail-hash', 'buyer'\n    FROM generate_series(1, 500) AS gs(n)",
    1,
)

Path(sys.argv[2]).write_text(source, encoding="utf-8")
PY

psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$TMP_SQL"

echo "Stress distribution seed completed through immutable source file: $SOURCE"
echo "Compatibility changes were applied only to a temporary execution copy."