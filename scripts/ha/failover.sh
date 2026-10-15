#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
if [[ -e "$TICKET_SECRETS_DIR/state/failover.lock" ]]; then
  echo 'Failover already executed. Old primary is fenced.'; exit 0
fi
if psql_node primary ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT NOT pg_is_in_recovery()' 2>/dev/null | grep -qx t; then
  echo >&2 'REFUSING promotion: old primary is still reachable and writable (split-brain risk).'; exit 1
fi
if ! psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT pg_is_in_recovery()' | grep -qx t; then
  echo >&2 'Standby not healthy or already promoted.'; exit 1
fi
mkdir -p "$TICKET_SECRETS_DIR/state" "$ROOT_DIR/artifacts/ha"
echo 'Promoting replica using pg_promote(wait=true)...'
psql_node replica ticket_root "$POSTGRES_PASSWORD" -c 'SELECT pg_promote(true,30);'
if ! psql_node replica ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT NOT pg_is_in_recovery()' | grep -qx t; then
  echo >&2 'Promotion did not complete'; exit 1
fi
# Fence former primary BEFORE routing client writes to the new primary.
umask 077
printf 'Promoted at %s (former primary MUST be rebuilt as standby)\n' "$(date -u +%FT%TZ)" > "$TICKET_SECRETS_DIR/state/failover.lock"
printf 'TICKET_ACTIVE_DB=replica\n' > "$TICKET_SECRETS_DIR/routing.env"
"${COMPOSE[@]}" up -d --no-deps --force-recreate proxy
printf '%s primary_unavailable replica_promoted proxy_switched\n' "$(date -u +%FT%TZ)" \
  | tee -a "$ROOT_DIR/artifacts/ha/failure_experiments.log"
echo 'Promoted replica is writable. Existing client connections will fail and must reconnect via proxy:5436.'
