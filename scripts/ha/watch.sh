#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
if [[ "${1:-}" == '--daemon' ]]; then
  mkdir -p "$ROOT_DIR/artifacts/ha"
  nohup "$ROOT_DIR/scripts/ha/watch.sh" > "$ROOT_DIR/artifacts/ha/watch.log" 2>&1 < /dev/null &
  echo "$!" > "$ROOT_DIR/artifacts/ha/watch.pid"
  echo "Background failover watcher PID=$! log=artifacts/ha/watch.log"
  exit 0
fi
if [[ "${1:-}" == '--once' ]]; then
  exec "$ROOT_DIR/scripts/ha/failover.sh"
fi
echo 'Monitoring PostgreSQL primary every 2s; failover requires 3 failed probes.'
miss=0
while true; do
  if [[ -f "$TICKET_SECRETS_DIR/state/failover.lock" ]]; then
    echo 'Failover already completed; watcher exits.'; exit 0
  fi
  if psql_node primary ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT 1' >/dev/null 2>&1; then
    miss=0
  else
    miss=$((miss + 1))
    echo "$(date -u +%FT%TZ) primary probe failure $miss/3"
    if ((miss >= 3)); then
      "$ROOT_DIR/scripts/ha/failover.sh"
      exit $?
    fi
  fi
  sleep 2
done
