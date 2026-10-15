#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
N="${1:-15}"
[[ "$N" =~ ^[0-9]+$ ]] || exit 2
mkdir -p "$ROOT_DIR/artifacts/ha"
LOG="$ROOT_DIR/artifacts/ha/app_probe.log"
for i in $(seq 1 "$N"); do
  if value="$(psql_node proxy ticket_app "$TICKET_APP_PASSWORD" -Atqc 'SELECT count(*) FROM app.events' 2>&1)"; then
    printf '%s OK events=%s\n' "$(date -u +%FT%TZ)" "$value" | tee -a "$LOG"
  else
    printf '%s ERROR connection/query failed (retrying)\n' "$(date -u +%FT%TZ)" | tee -a "$LOG"
  fi
  sleep 1
done
echo "Probe log: $LOG"
