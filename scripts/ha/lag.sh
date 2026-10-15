#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
MODE="${1:-load}"
SEED="${SEED:-20261004}"
[[ "$MODE" == load || "$MODE" == development ]] || { echo >&2 'mode is development or load'; exit 2; }
if ! psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT pg_is_in_recovery()' | grep -qx t; then
  echo >&2 'Replica must be a streaming standby'; exit 1
fi
mkdir -p "$ROOT_DIR/artifacts/ha"
CSV="$ROOT_DIR/artifacts/ha/replication_lag_${MODE}.csv"
echo 'timestamp_utc,lag_bytes,write_lag_ms,flush_lag_ms,replay_lag_ms,state' > "$CSV"
export PGPASSWORD="$TICKET_APP_PASSWORD"
export DB_URL="host=localhost port=${TICKET_PROXY_PORT:-5436} dbname=ticket_platform user=ticket_app sslmode=verify-full sslrootcert=$PGSSLROOTCERT"
SEED="$SEED" "$ROOT_DIR/scripts/generate_data.sh" "$MODE" > "$ROOT_DIR/artifacts/ha/generate_${MODE}.log" 2>&1 &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  result="$(psql_node primary ticket_root "$POSTGRES_PASSWORD" -At -F , -c "SELECT
    COALESCE(pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn),0)::bigint,
    COALESCE(round(extract(epoch from write_lag)*1000)::text,''),
    COALESCE(round(extract(epoch from flush_lag)*1000)::text,''),
    COALESCE(round(extract(epoch from replay_lag)*1000)::text,''),
    state
    FROM pg_stat_replication WHERE application_name='ticket_replica' LIMIT 1;" 2>/dev/null | tail -n1)"
  if [[ -n "$result" ]]; then
    printf '%s,%s\n' "$(date -u +%FT%TZ)" "$result" >> "$CSV"
  else
    printf '%s,, , , ,missing\n' "$(date -u +%FT%TZ)" >> "$CSV"
  fi
  sleep 0.5
done
wait "$pid" || { tail -n 35 "$ROOT_DIR/artifacts/ha/generate_${MODE}.log" >&2; exit 1; }
# Observe replay after commit, as the transaction may have been bulk committed.
for _ in $(seq 1 12); do
  result="$(psql_node primary ticket_root "$POSTGRES_PASSWORD" -At -F , -c "SELECT
    COALESCE(pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn),0)::bigint,
    COALESCE(round(extract(epoch from write_lag)*1000)::text,''),
    COALESCE(round(extract(epoch from flush_lag)*1000)::text,''),
    COALESCE(round(extract(epoch from replay_lag)*1000)::text,''),state
    FROM pg_stat_replication WHERE application_name='ticket_replica' LIMIT 1;" 2>/dev/null | tail -n1)"
  [[ -z "$result" ]] || printf '%s,%s\n' "$(date -u +%FT%TZ)" "$result" >> "$CSV"
  sleep 0.5
done
echo "Replication lag samples: $CSV"
