#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
if ! psql_node primary ticket_root "$POSTGRES_PASSWORD" -Atqc "SELECT 1 FROM pg_replication_slots WHERE slot_name='ticket_replica_slot'" | grep -qx 1; then
  echo >&2 'Replication slot missing: run ./scripts/ha.sh roles first'; exit 1
fi
"${COMPOSE[@]}" --profile replica up -d replica
for i in $(seq 1 90); do
  if psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT pg_is_in_recovery()' 2>/dev/null | grep -qx t; then
    echo 'Replica is in recovery mode and accepts verified TLS read connections.'
    exit 0
  fi
  sleep 1
done
echo >&2 'Replica not ready: check docker compose logs replica'; exit 1
