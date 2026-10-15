#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
mkdir -p "$ROOT_DIR/artifacts/ha"
LOG="$ROOT_DIR/artifacts/ha/replication_verification.log"
if ! psql_node primary ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT pg_is_in_recovery()' | grep -qx f; then
  echo >&2 'primary must be writable'; exit 1
fi
if ! psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT pg_is_in_recovery()' | grep -qx t; then
  echo >&2 'replica must be in hot standby'; exit 1
fi
streaming=false
for i in $(seq 1 30); do
  if psql_node primary ticket_root "$POSTGRES_PASSWORD" -Atqc \
    "SELECT count(*) FROM pg_stat_replication WHERE application_name='ticket_replica' AND state='streaming'" | grep -qx 1; then
    streaming=true
    break
  fi
  sleep 1
done
[[ "$streaming" == true ]] || { echo >&2 'No active streaming replication sender'; exit 1; }
marker="ha_replication_$(date -u +%s)_$RANDOM"
psql_node proxy ticket_app "$TICKET_APP_PASSWORD" -Atqc \
  "INSERT INTO app.venues(name,capacity) VALUES ('$marker',100) RETURNING id;" >/dev/null
for i in $(seq 1 30); do
  value="$(psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc \
    "SELECT count(*) FROM app.venues WHERE name='$marker'" 2>/dev/null || true)"
  if [[ "$value" == 1 ]]; then
    printf '%s PASS primary_write_replica_read marker=%s replay_delay_upper_bound_seconds=%s\n' \
      "$(date -u +%FT%TZ)" "$marker" "$i" | tee -a "$LOG"
    break
  fi
  [[ "$i" != 30 ]] || { echo >&2 'Written row did not reach standby'; exit 1; }
  sleep 1
done
# Standby must not accept writes; an expected error confirms direction.
if psql_node replica ticket_app "$TICKET_APP_PASSWORD" -Atqc \
    "INSERT INTO app.venues(name,capacity) VALUES ('should_not_write_standby',1)" \
    >/dev/null 2>&1; then
  echo >&2 'FAIL: replica accepted write'; exit 1
fi
echo 'PASS: replica refuses INSERT (read-only standby)' | tee -a "$LOG"
echo "Replication evidence: $LOG"
