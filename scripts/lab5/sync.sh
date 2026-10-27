#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
mkdir -p "$ROOT_DIR/artifacts/lab5"
# 3 real PostgreSQL event IDs form the only shared business identity.
# Event price, inventory and transactions never go into editorial Mongo documents.
pg -At -c "SELECT COALESCE(json_agg(row_to_json(e)),'[]'::json) FROM (
  SELECT id::text AS \"pgEventId\", name
  FROM app.events WHERE status IN ('published','sold_out','completed')
  ORDER BY id LIMIT 3
) e;" > "$ROOT_DIR/artifacts/lab5/pg_events.json"
python3 - "$ROOT_DIR/artifacts/lab5/pg_events.json" <<'PY'
import json,sys
rows=json.load(open(sys.argv[1],encoding='utf8'))
if len(rows)<2: raise SystemExit('ERROR: at least 2 published/completed PG events required. Run ./scripts/ha.sh seed first.')
assert all(int(x['pgEventId'])>0 and x['name'] for x in rows)
print('PostgreSQL event identities exported:', len(rows))
PY
run_mongo sync_from_pg.js
