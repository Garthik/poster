#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-$("$ROOT_DIR/scripts/resolve_db_url.sh")}"
export DB_URL
SEED="${SEED:-20261004}"
MODE="${MODE:-load}"
RUNS="${RUNS:-5}"
ROWS="${ROWS:-300000}"
GENERATE="${GENERATE:-0}"

echo "==> Database: $DB_URL"

if [[ "$GENERATE" == "1" ]]; then
    echo "==> Generate data: mode=$MODE seed=$SEED"
    SEED="$SEED" "$ROOT_DIR/scripts/generate_data.sh" "$MODE"
fi

echo "==> Business queries"
SEED="$SEED" MODE="$MODE" "$ROOT_DIR/scripts/run_business_queries.sh"

echo "==> Transaction COMMIT / ROLLBACK"
"$ROOT_DIR/scripts/run_transaction_demo.sh"

echo "==> Concurrent quota protection"
"$ROOT_DIR/scripts/concurrency_test.sh"

echo "==> Lock diagnostics"
"$ROOT_DIR/scripts/lock_diagnostics.sh"

echo "==> Query benchmark: before / after"
SEED="$SEED" MODE="$MODE" RUNS="$RUNS" "$ROOT_DIR/scripts/benchmark_queries.sh"

echo "==> Bulk-load strategy comparison"
ROWS="$ROWS" RUNS="$RUNS" "$ROOT_DIR/scripts/compare_load.sh"

echo
echo "PASS: automated advanced SQL stand completed. Results are in $ROOT_DIR/artifacts/."
