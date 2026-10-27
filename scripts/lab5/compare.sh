#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
OUT="$ROOT_DIR/artifacts/lab5"
mkdir -p "$OUT"
run_mongo export_comparison.js
# CSV-quote JSON text so psql COPY does not interpret JSON backslashes as COPY escapes.
python3 - "$OUT" <<'PYCSV'
import sys,pathlib,csv
p=pathlib.Path(sys.argv[1]); rows=(p/'mongo_pages.jsonl').read_text(encoding='utf8').splitlines()
with (p/'mongo_pages.csv').open('w',newline='',encoding='utf8') as f:
  writer=csv.writer(f)
  for row in rows: writer.writerow([row])
PYCSV
# The PG JSONB table is a read-model comparison, not the editorial source of truth.
# \copy is psql client-side, so it can load runtime files from WSL.
pg <<SQL
CREATE TEMP TABLE lab5_stage(line TEXT);
\copy lab5_stage(line) FROM '$OUT/mongo_pages.csv' WITH (FORMAT csv)
INSERT INTO app.lab5_content_compare(slug,payload)
SELECT (line::jsonb)->>'slug', line::jsonb FROM lab5_stage
ON CONFLICT (slug) DO UPDATE SET payload=EXCLUDED.payload, imported_at=now();
SQL
pg -At -c "SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.slug),'[]'::json) FROM (
 SELECT slug,payload->>'headline' AS headline,payload->>'status' AS status
 FROM app.lab5_content_compare
 WHERE payload->>'status'='published' AND payload->'keywords' ? 'visit'
 AND slug LIKE 'pg-event-%' ORDER BY slug
) t;" > "$OUT/postgres_cards.json"
python3 - "$OUT" <<'PY'
import json,sys,pathlib
p=pathlib.Path(sys.argv[1]); mongo=json.loads((p/'mongo_cards.json').read_text()); postgres=json.loads((p/'postgres_cards.json').read_text())
if not mongo or not postgres: raise SystemExit('FAIL: no matching catalog cards for JSONB/Mongo comparison')
if mongo!=postgres:
 print('MONGO:',mongo); print('PG:',postgres)
 raise SystemExit('FAIL: PostgreSQL JSONB and MongoDB returned different cards')
print('PASS: same source documents, same business filter, same result:',len(mongo),'cards')
(p/'comparison.txt').write_text('PASS: identical editorial cards in MongoDB and PG JSONB. Count='+str(len(mongo))+'\n')
PY
