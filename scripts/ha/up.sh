#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
"${COMPOSE[@]}" up -d primary proxy
for i in $(seq 1 50); do
  if psql_node primary ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT 1' >/dev/null 2>&1; then
    echo 'Primary accepting verified TLS connections.'
    exit 0
  fi
  sleep 1
done
echo >&2 'Primary failed to become ready. Check ./scripts/ha.sh status and docker logs.'
exit 1
