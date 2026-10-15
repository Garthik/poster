#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_URL="${DB_URL:-$("$ROOT_DIR/scripts/resolve_db_url.sh")}"
SEED="${SEED:-20261004}"
MODE="${MODE:-load}"
EVENT_NAME="${EVENT_NAME:-Generated ${MODE} dataset seed=${SEED} popular event}"
RUNS="${RUNS:-5}"
OUT_DIR="$ROOT_DIR/artifacts/query_benchmark"
BEFORE_DIR="$OUT_DIR/before"
AFTER_DIR="$OUT_DIR/after"
SUMMARY="$OUT_DIR/summary.txt"
CSV="$OUT_DIR/measurements.csv"

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 3 && $((RUNS % 2)) -eq 1 ]] || {
    echo "ERROR: RUNS must be an odd integer >= 3" >&2
    exit 2
}

mkdir -p "$BEFORE_DIR" "$AFTER_DIR"
rm -f "$BEFORE_DIR"/* "$AFTER_DIR"/* "$CSV" "$SUMMARY"

echo "Preparing benchmark parameters..."

IFS='|' read -r CONTROLLER_ID FROM_TS TO_TS < <(
    psql "$DB_URL" -X -At -F '|' -v ON_ERROR_STOP=1 -v event_name="$EVENT_NAME" <<'SQL'
SELECT
    u.id,
    min(s.scanned_at),
    min(s.scanned_at) + interval '1 hour'
FROM app.users u
JOIN app.ticket_scans s ON s.controller_id=u.id
JOIN app.tickets t ON t.id=s.ticket_id
JOIN app.events e ON e.id=t.event_id
WHERE u.role='controller'
  AND e.name=:'event_name'
GROUP BY u.id
ORDER BY u.id
LIMIT 1;
SQL
)

if [[ -z "${CONTROLLER_ID:-}" || -z "${FROM_TS:-}" || -z "${TO_TS:-}" ]]; then
    echo "ERROR: benchmark dataset is missing. Generate development/load data first." >&2
    exit 1
fi

cat > "$ROOT_DIR/artifacts/query_benchmark/parameters.txt" <<EOF
Event: $EVENT_NAME
Controller ID: $CONTROLLER_ID
Interval: $FROM_TS .. $TO_TS
Runs per phase: $RUNS
EOF

run_query() {
    local query_name="$1"
    local phase="$2"
    local run="$3"
    local output_file="$4"
    local plan

    case "$query_name" in
        Q1)
            plan="EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) AS scan_count FROM app.ticket_scans WHERE controller_id = ${CONTROLLER_ID} AND scanned_at >= '${FROM_TS}'::timestamptz AND scanned_at < '${TO_TS}'::timestamptz;"
            ;;
        Q2)
            plan="EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) AS rejected_count FROM app.ticket_scans WHERE result = 'rejected' AND scanned_at >= '${FROM_TS}'::timestamptz AND scanned_at < '${TO_TS}'::timestamptz;"
            ;;
        *)
            echo "ERROR: unknown query $query_name" >&2
            exit 2
            ;;
    esac

    psql "$DB_URL" -X -v ON_ERROR_STOP=1 -c "$plan" > "$output_file"
    local ms
    ms="$(awk '/Execution Time:/ {gsub(/ms/, "", $3); print $3; exit}' "$output_file")"
    [[ -n "$ms" ]] || {
        echo "ERROR: failed to parse execution time from $output_file" >&2
        exit 1
    }
    printf '%s,%s,%s,%s\n' "$query_name" "$phase" "$run" "$ms" >> "$CSV"
}

printf 'query,phase,run,time_ms\n' > "$CSV"

printf '==> BEFORE: remove benchmark-only indexes and ANALYZE\n'
psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
DROP INDEX IF EXISTS app.ticket_scans_controller_time_idx;
DROP INDEX IF EXISTS app.ticket_scans_result_time_idx;
ANALYZE app.ticket_scans;
SQL

for run in $(seq 1 "$RUNS"); do
    run_query Q1 before "$run" "$BEFORE_DIR/q1_run${run}.txt"
    run_query Q2 before "$run" "$BEFORE_DIR/q2_run${run}.txt"
done

printf '==> AFTER: create benchmark indexes and ANALYZE\n'
psql "$DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
CREATE INDEX IF NOT EXISTS ticket_scans_controller_time_idx
    ON app.ticket_scans (controller_id, scanned_at DESC);

CREATE INDEX IF NOT EXISTS ticket_scans_result_time_idx
    ON app.ticket_scans (result, scanned_at DESC);

ANALYZE app.ticket_scans;
SQL

for run in $(seq 1 "$RUNS"); do
    run_query Q1 after "$run" "$AFTER_DIR/q1_run${run}.txt"
    run_query Q2 after "$run" "$AFTER_DIR/q2_run${run}.txt"
done

median() {
    local q="$1"
    local phase="$2"
    awk -F, -v q="$q" -v phase="$phase" \
        '$1 == q && $2 == phase {print $4}' "$CSV" \
        | sort -n \
        | awk -v n="$RUNS" 'NR == int((n + 1) / 2) {print; exit}'
}

q1_before="$(median Q1 before)"
q1_after="$(median Q1 after)"
q2_before="$(median Q2 before)"
q2_after="$(median Q2 after)"

speedup() {
    awk -v before="$1" -v after="$2" 'BEGIN { if (after == 0) print "n/a"; else printf "%.2fx", before/after }'
}

cat > "$SUMMARY" <<EOF
Query benchmark
===============
Dataset: $EVENT_NAME
Controller ID: $CONTROLLER_ID
Interval: $FROM_TS .. $TO_TS
Runs per phase: $RUNS

Median execution time (ms)
--------------------------
Q1 controller + time   before: $q1_before   after: $q1_after   speedup: $(speedup "$q1_before" "$q1_after")
Q2 rejected + time     before: $q2_before   after: $q2_after   speedup: $(speedup "$q2_before" "$q2_after")

Indexes created in AFTER phase
------------------------------
app.ticket_scans_controller_time_idx (controller_id, scanned_at DESC)
app.ticket_scans_result_time_idx     (result, scanned_at DESC)

Plans:
  $BEFORE_DIR/q1_run1.txt
  $BEFORE_DIR/q2_run1.txt
  $AFTER_DIR/q1_run1.txt
  $AFTER_DIR/q2_run1.txt
EOF

cat "$SUMMARY"
