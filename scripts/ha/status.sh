#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
"${COMPOSE[@]}" --profile replica --profile restore ps
printf '\nProxy target: '
cat "$TICKET_SECRETS_DIR/routing.env"
for node in primary replica; do
  printf '\n%s: ' "$node"
  if ! psql_node "$node" ticket_root "$POSTGRES_PASSWORD" -Atqc \
    "SELECT CASE WHEN pg_is_in_recovery() THEN 'STANDBY' ELSE 'PRIMARY' END" 2>/dev/null; then
    echo 'unavailable'
  fi
done
printf '\nStreaming status on primary (if reachable):\n'
psql_node primary ticket_root "$POSTGRES_PASSWORD" -c \
 "SELECT application_name,state,sync_state,write_lsn,flush_lsn,replay_lsn,write_lag,flush_lag,replay_lag FROM pg_stat_replication;" || true
printf '\nStandby replay (if reachable):\n'
psql_node replica ticket_root "$POSTGRES_PASSWORD" -c \
 'SELECT pg_is_in_recovery(),pg_last_wal_receive_lsn(),pg_last_wal_replay_lsn(),pg_last_xact_replay_timestamp();' || true
