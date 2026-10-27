#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lab5/lib.sh"
usage() {
  cat <<'USAGE'
./scripts/lab5.sh init        # generate local Mongo password, outside git
./scripts/lab5.sh up          # start MongoDB on 127.0.0.1:27018
./scripts/lab5.sh schema      # create 3 collections, validation and indexes
./scripts/lab5.sh sql         # run Q1...Q8 + SQL assertions
./scripts/lab5.sh sync        # export real PG events; seed editorial Mongo documents
./scripts/lab5.sh crud        # CRUD demo for all collections
./scripts/lab5.sh validation  # 3 rejected writes and reference checks
./scripts/lab5.sh compare     # same documents: MongoDB query vs PG JSONB query
./scripts/lab5.sh evolve      # migrate Mongo event_pages schema v1 -> v2
./scripts/lab5.sh all         # SQL tests, schema, sync, CRUD, validation, comparison
./scripts/lab5.sh down        # stop Mongo without deleting its data
USAGE
}
cmd="${1:-help}"
case "$cmd" in
  init)
    if [[ -e "$MONGO_SECRET_FILE" ]]; then echo "Existing Mongo secrets kept: $MONGO_SECRET_FILE"; exit 0; fi
    command -v openssl >/dev/null || { echo 'openssl missing' >&2; exit 127; }
    umask 077; mkdir -p "$(dirname "$MONGO_SECRET_FILE")"
    printf 'MONGO_ROOT_USER=lab5_root\nMONGO_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 24)" > "$MONGO_SECRET_FILE"
    chmod 600 "$MONGO_SECRET_FILE"
    echo "Created Mongo credentials outside repository: $MONGO_SECRET_FILE" ;;
  up) mongo_compose up -d --wait mongo ;;
  down) mongo_compose down ;;
  schema) run_mongo schema.js ;;
  sql) "$ROOT_DIR/scripts/lab5/test_sql.sh" ;;
  sync) "$ROOT_DIR/scripts/lab5/sync.sh" ;;
  crud) run_mongo crud.js ;;
  validation) run_mongo validation_test.js ;;
  compare) "$ROOT_DIR/scripts/lab5/compare.sh" ;;
  evolve) run_mongo migrate_v2.js ;;
  all)
    "$ROOT_DIR/scripts/lab5/test_sql.sh"
    run_mongo schema.js
    "$ROOT_DIR/scripts/lab5/sync.sh"
    run_mongo crud.js
    run_mongo validation_test.js
    "$ROOT_DIR/scripts/lab5/compare.sh"
    echo 'PASS: all Lab5 stages completed' ;;
  help|-h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
