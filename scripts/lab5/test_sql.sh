#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$ROOT_DIR/artifacts/lab5"
# No fixture generated implicitly: avoid overwriting an existing 3M-row dataset.
pg -At -c "SELECT CASE WHEN
(SELECT count(*) FROM app.ticket_scans)>0 AND
(SELECT count(*) FROM app.orders WHERE status='paid')>0
THEN 'ready' ELSE 'missing' END;" | grep -qx ready || {
  echo 'ERROR: generate development dataset first (scripts/generate_data.sh development)' >&2
  exit 1
}
MODE="${MODE:-development}" "$ROOT_DIR/scripts/run_business_queries.sh" > "$ROOT_DIR/artifacts/lab5/sql_catalog_results.txt"
pg -f "$ROOT_DIR/tests/lab5/sql_assertions.sql" 2>&1 | tee "$ROOT_DIR/artifacts/lab5/sql_assertions.txt"
python3 - "$ROOT_DIR/queries/business_queries.sql" <<'PY'
import re,sys
sql=open(sys.argv[1],encoding='utf8').read()
parts=re.split(r"(?m)^\\echo 'Q[1-8]\.",sql)[1:]
assert len(parts)==8,f'Expected 8 numbered SQL queries, found {len(parts)}'
aggregates=sum(bool(re.search(r'COUNT\s*\(|SUM\s*\(|AVG\s*\(',x,re.I)) for x in parts)
windows=sum(bool(re.search(r'\bOVER\s*\(',x,re.I)) for x in parts)
cte=sum(bool(re.search(r'\bWITH\b',x,re.I)) for x in parts)
joins=sum(bool(re.search(r'\bJOIN\b',x,re.I)) for x in parts)
assert aggregates>=3 and windows>=3 and cte>=2 and joins>=5
assert 'DENSE_RANK' in sql and 'LAG(' in sql and 'ROWS BETWEEN UNBOUNDED PRECEDING' in sql
print(f'PASS: {len(parts)} queries; {aggregates} aggregates; {windows} window; {cte} CTE; {joins} JOIN')
PY
