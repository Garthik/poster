#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LC_ALL=C
DB_URL="${DB_URL:-$("$ROOT_DIR/scripts/resolve_db_url.sh")}"
ROWS="${ROWS:-300000}"
RUNS="${RUNS:-3}"
OUT_DIR="$ROOT_DIR/artifacts/load_compare"
CSV_FILE="$OUT_DIR/load_data.csv"
MEASUREMENTS="$OUT_DIR/measurements.csv"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}
command -v awk >/dev/null 2>&1 || {
    echo "ERROR: awk is required" >&2
    exit 127
}

[[ "$ROWS" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: ROWS must be a positive integer" >&2; exit 2; }
[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 3 && $((RUNS % 2)) -eq 1 ]] || { echo "ERROR: RUNS must be an odd integer >= 3" >&2; exit 2; }

mkdir -p "$OUT_DIR"
rm -f "$CSV_FILE" "$MEASUREMENTS" "$OUT_DIR"/insert_run*.txt "$OUT_DIR"/copy_run*.txt

printf '==> Preparing deterministic CSV with %s rows\n' "$ROWS"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<SQL > /dev/null
\copy (SELECT g AS id, mod(g,100)::integer AS bucket, md5(format('load:%s',g)) AS payload FROM generate_series(1, ${ROWS}::bigint) AS gs(g)) TO '$CSV_FILE' WITH (FORMAT csv)
SQL

printf 'strategy,run,time_ms\n' > "$MEASUREMENTS"

run_insert() {
    local run="$1"
    local log="$OUT_DIR/insert_run${run}.txt"
    psql "$DB_URL" -X -v ON_ERROR_STOP=1 -v rows="$ROWS" <<'SQL' > "$log" 2>&1
CREATE TEMP TABLE load_compare (
    id BIGINT NOT NULL,
    bucket INTEGER NOT NULL,
    payload TEXT NOT NULL
);
\timing on
INSERT INTO load_compare (id, bucket, payload)
SELECT
    g,
    mod(g, 100)::integer,
    md5(format('load:%s', g))
FROM generate_series(1, :'rows'::bigint) AS gs(g);
\timing off
SELECT count(*) AS rows_loaded FROM load_compare;
SQL
    local ms
    ms="$(awk '/^Time:/ && /ms/ {value=$2} END {print value}' "$log")"
    [[ -n "$ms" ]] || { echo "ERROR: could not parse INSERT time" >&2; exit 1; }
    printf 'insert,%s,%s\n' "$run" "$ms" >> "$MEASUREMENTS"
}

run_copy() {
    local run="$1"
    local log="$OUT_DIR/copy_run${run}.txt"
    psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<SQL > "$log" 2>&1
CREATE TEMP TABLE load_compare (
    id BIGINT NOT NULL,
    bucket INTEGER NOT NULL,
    payload TEXT NOT NULL
);
\\timing on
\copy load_compare FROM '$CSV_FILE' WITH (FORMAT csv)
\\timing off
SELECT count(*) AS rows_loaded FROM load_compare;
SQL
    local ms
    ms="$(awk '/^Time:/ && /ms/ {value=$2} END {print value}' "$log")"
    [[ -n "$ms" ]] || { echo "ERROR: could not parse COPY time" >&2; exit 1; }
    printf 'copy,%s,%s\n' "$run" "$ms" >> "$MEASUREMENTS"
}

for run in $(seq 1 "$RUNS"); do
    run_insert "$run"
    run_copy "$run"
done

median_for() {
    local strategy="$1"
    awk -F, -v strategy="$strategy" '$1==strategy {print $3}' "$MEASUREMENTS" \
        | sort -n \
        | awk -v n="$RUNS" 'NR == int((n + 1) / 2) {print; exit}'
}

insert_median="$(median_for insert)"
copy_median="$(median_for copy)"

awk -v i="$insert_median" -v c="$copy_median" 'BEGIN {printf "INSERT median: %.3f ms\nCOPY median:   %.3f ms\n", i, c; if (c > 0) printf "COPY speedup vs INSERT: %.2fx\n", i/c}' \
    | tee "$OUT_DIR/summary.txt"

printf 'Rows: %s\nRuns: %s\nCSV: %s\nMeasurements: %s\n' "$ROWS" "$RUNS" "$CSV_FILE" "$MEASUREMENTS"
