#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
mkdir -p "$ROOT_DIR/artifacts/ha"
LOG="$ROOT_DIR/artifacts/ha/failure_experiments.log"
if [[ -f "$TICKET_SECRETS_DIR/state/failover.lock" ]]; then
  echo >&2 'Failover was already performed; use a new lab cluster or follow runbook to rebuild old primary.'
  exit 1
fi
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG"; }
log 'BEGIN acceptance demo'
"$ROOT_DIR/scripts/ha/check.sh"
"$ROOT_DIR/scripts/ha/backup.sh"
"$ROOT_DIR/scripts/ha/restore.sh"
log 'Backup restored in independent clean instance'
if ! psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT pg_is_in_recovery()' | grep -qx t; then
  echo >&2 'Start a healthy replica before demo.'; exit 1
fi
marker="HA_demo_before_stop_$(date -u +%s)"
psql_node proxy ticket_app "$TICKET_APP_PASSWORD" -Atqc \
  "INSERT INTO app.venues(name, capacity) VALUES ('$marker', 100) RETURNING id;" >/dev/null
for i in $(seq 1 30); do
  if psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc \
    "SELECT count(*) FROM app.venues WHERE name='$marker'" | grep -qx 1; then
    log 'PASS: fresh insert visible on replica'; break
  fi
  [[ "$i" != 30 ]] || { echo >&2 'Replica did not receive insert'; exit 1; }
  sleep 1
done
log 'EXPERIMENT 1: stop replica; primary remains writable'
"${COMPOSE[@]}" --profile replica stop replica
marker2="HA_demo_while_replica_down_$(date -u +%s)"
psql_node proxy ticket_app "$TICKET_APP_PASSWORD" -Atqc \
  "INSERT INTO app.venues(name, capacity) VALUES ('$marker2', 100) RETURNING id;" >/dev/null
log 'PASS: app wrote while replica was down'
"${COMPOSE[@]}" --profile replica up -d replica
for i in $(seq 1 60); do
  value="$(psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc \
    "SELECT count(*) FROM app.venues WHERE name='$marker2'" 2>/dev/null || true)"
  if [[ "$value" == 1 ]]; then log 'PASS: recovered standby caught up'; break; fi
  [[ "$i" != 60 ]] || { echo >&2 'Replica did not catch up after restart; slot/WAL may require rebase'; exit 1; }
  sleep 2
done
log 'EXPERIMENT 2: stop primary; application temporarily loses DB connection'
"$ROOT_DIR/scripts/ha/watch.sh" --daemon
"$ROOT_DIR/scripts/ha/probe.sh" 22 > "$ROOT_DIR/artifacts/ha/app_probe_demo.log" 2>&1 &
probe_pid=$!
sleep 2
"${COMPOSE[@]}" stop primary
for i in $(seq 1 50); do
  if [[ -f "$TICKET_SECRETS_DIR/state/failover.lock" ]]; then break; fi
  sleep 1
done
[[ -f "$TICKET_SECRETS_DIR/state/failover.lock" ]] || { echo >&2 'Watcher failed to promote and switch'; exit 1; }
wait "$probe_pid"
marker3="HA_demo_after_failover_$(date -u +%s)"
psql_node proxy ticket_app "$TICKET_APP_PASSWORD" -Atqc \
  "INSERT INTO app.venues(name, capacity) VALUES ('$marker3', 100) RETURNING id;" >/dev/null
n="$(psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc \
  "SELECT count(*) FROM app.venues WHERE name='$marker3'")"
[[ "$n" == 1 ]] || { echo >&2 'Promoted new primary missing app write'; exit 1; }
log 'PASS: application reconnects via HAProxy and new primary accepts writes'
log 'END acceptance demo. Old primary is fenced; DO NOT restart it without reinitializing as standby.'
echo "Full failure log: $LOG"
