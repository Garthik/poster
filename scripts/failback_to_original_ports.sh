#!/usr/bin/env bash
# Planned failback from promoted replica:5435 to primary:5434.
# Preserves original named volumes; creates TWO new volumes.
set -Eeuo pipefail
umask 077

ROOT="$(pwd -P)"
[[ -f "$ROOT/docker-compose.ha.yml" && -f "$ROOT/scripts/ha.sh" ]] || {
  echo >&2 'ERROR: run from ticket-platform HA project root'; exit 2;
}
cd "$ROOT"
D="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"
export TICKET_SECRETS_DIR="$D"
[[ -f "$D/primary.env" && -f "$D/roles.env" && -f "$D/tls/ca.crt" ]] || {
  echo >&2 'ERROR: HA secret files missing'; exit 2;
}
set -a
# shellcheck disable=SC1091
source "$D/primary.env"
# shellcheck disable=SC1091
source "$D/roles.env"
set +a
export PGSSLMODE=verify-full PGSSLROOTCERT="$D/tls/ca.crt" PGCONNECT_TIMEOUT=5
C=(docker compose -f "$ROOT/docker-compose.ha.yml")
PROJECT='ticket-platform-ha'
SRC_VOL="${PROJECT}_ha_replica"
ORIGINAL_PRIMARY_VOL="${PROJECT}_ha_primary"
DEST_VOL="${PROJECT}_ha_primary_after_failback"
NEW_REPLICA_VOL="${PROJECT}_ha_replica_after_failback"
ROUTING="$D/routing.env"
LOCK="$D/state/failover.lock"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$D/backups/failback_${STAMP}.txt"
mkdir -p "$D/backups"

fail() { echo >&2 "ERROR: $*"; exit 1; }
info() { printf '\n==> %s\n' "$*"; }
postgres() {
  local port="$1"; shift
  PGPASSWORD="$POSTGRES_PASSWORD" psql -X -v ON_ERROR_STOP=1 -h localhost -p "$port" \
      -U ticket_root -d ticket_platform "$@"
}
node_running() {
  [[ -n "$(docker ps -q \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --filter "label=com.docker.compose.service=$1")" ]]
}
COUNT_SQL="SELECT (SELECT count(*) FROM app.venues), (SELECT count(*) FROM app.events), (SELECT count(*) FROM app.orders), (SELECT count(*) FROM app.tickets), (SELECT count(*) FROM app.ticket_scans);"

command -v docker >/dev/null || fail 'docker not found'
command -v pg_dump >/dev/null || fail 'pg_dump not found'
command -v psql >/dev/null || fail 'psql not found'
command -v python3 >/dev/null || fail 'python3 not found'
[[ "$(cat "$ROUTING")" == 'TICKET_ACTIVE_DB=replica' ]] || fail 'routing.env does not target replica'
[[ -f "$LOCK" ]] || fail 'failover.lock is missing (state differs; manual review required)'
node_running replica || fail 'promoted replica container not running'
if node_running primary; then fail 'old primary is running: STOP! split-brain hazard'; fi
if node_running restore; then echo 'Info: isolated restore instance may continue running.'; fi
[[ "$(postgres 5435 -Atqc 'SELECT pg_is_in_recovery()')" == f ]] || fail 'replica:5435 is not PRIMARY'
for vol in "$SRC_VOL" "$ORIGINAL_PRIMARY_VOL"; do
  docker volume inspect "$vol" >/dev/null || fail "missing volume $vol"
done
for vol in "$DEST_VOL" "$NEW_REPLICA_VOL"; do
  if docker volume inspect "$vol" >/dev/null 2>&1; then
    fail "volume $vol already exists; to prevent overwrite, inspect previous failback attempt"
  fi
done
if grep -q -E '^ *- ha_(primary|replica)_after_failback:/var/lib/postgresql/data' docker-compose.ha.yml; then
  fail 'docker-compose.ha.yml already contains failback volume mappings'
fi

info 'Checking Docker-volume disk space for two additional full data copies'
storage="$(docker run --rm --entrypoint sh -v "$SRC_VOL:/source:ro" postgres:16-alpine -ec '
  test -f /source/pgdata/PG_VERSION
  set -- $(du -sk /source); used=$1
  set -- $(df -Pk /source | tail -n 1); free=$4
  printf "%s %s\n" "$used" "$free"
')"
read -r used_kb free_kb <<< "$storage"
[[ "$used_kb" =~ ^[0-9]+$ && "$free_kb" =~ ^[0-9]+$ ]] || fail 'failed to calculate Docker volume disk space'
required_kb=$(( used_kb * 2 + 524288 ))
printf 'Current primary volume: %s KiB; Docker free: %s KiB; target minimum: %s KiB\n' "$used_kb" "$free_kb" "$required_kb"
(( free_kb >= required_kb )) || fail 'not enough Docker volume disk space for safe no-delete failback'

# Ensure this exact project's bootstrap uses a CA path readable by postgres.
# Source archive had two old paths; patch only when both old occurrences exist.
if grep -q 'PGSSLROOTCERT=/etc/ticket/tls/ca.crt' infra/ha/start-replica.sh; then
  info 'Fixing original standby bootstrap TLS CA access (before changing topology)'
  cp -p infra/ha/start-replica.sh "$D/backups/start-replica.pre-failback_${STAMP}.sh"
  python3 - <<'PY_TLS'
from pathlib import Path
p = Path('infra/ha/start-replica.sh')
s = p.read_text()
old = '/etc/ticket/tls/ca.crt'
assert s.count(old) == 2, 'unexpected CA references: review start-replica.sh manually'
key_line = 'cp /etc/ticket/tls/server.key /var/lib/postgresql/tls/server.key\n'
assert s.count(key_line) == 1
owner = 'chown postgres:postgres /var/lib/postgresql/tls/server.crt /var/lib/postgresql/tls/server.key "$PGDATA"'
assert s.count(owner) == 1
s = s.replace(owner, 'chown postgres:postgres /var/lib/postgresql/tls/server.crt /var/lib/postgresql/tls/server.key /var/lib/postgresql/tls/ca.crt "$PGDATA"')
mode = 'chmod 600 /var/lib/postgresql/tls/server.key'
assert s.count(mode) == 1
s = s.replace(mode, mode + '\nchmod 644 /var/lib/postgresql/tls/ca.crt')
s = s.replace(old, '/var/lib/postgresql/tls/ca.crt')
s = s.replace(key_line, key_line + 'cp /etc/ticket/tls/ca.crt /var/lib/postgresql/tls/ca.crt\n')
p.write_text(s)
PY_TLS
  sh -n infra/ha/start-replica.sh
fi

info 'Checking data on currently promoted primary:5435'
BEFORE="$(postgres 5435 -AtF '|' -c "$COUNT_SQL")"
printf 'Snapshot row counts [venues|events|orders|tickets|ticket_scans]: %s\n' "$BEFORE"
printf '%s\n' "before=$BEFORE" > "$LOG"
info 'Creating a logical backup using existing HA script'
./scripts/ha.sh backup || fail 'pg_dump failed; no topology changed'
latest_dump="$(find "$D/backups" -maxdepth 1 -type f -name 'ticket_platform_*.dump' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)"
[[ -n "$latest_dump" && -s "$latest_dump" ]] || fail 'backup file not found'
pg_restore --list "$latest_dump" >/dev/null || fail 'pg_restore cannot read backup'
printf 'backup=%s\n' "$latest_dump" >> "$LOG"

cat <<'EOT'

IMPORTANT: The next step causes planned downtime.
Stop ALL direct clients/writers using ports 5435 and 5436.
Do not run HA watcher or ./scripts/ha.sh demo during this operation.
The old primary and old replica volumes WILL NOT BE DELETED.
Two additional full PostgreSQL volumes need free Docker disk space.
EOT
read -r -p 'Confirm no writers remain, and type FAILBACK to proceed: ' ANSWER
[[ "$ANSWER" == 'FAILBACK' ]] || fail 'cancelled safely before downtime'

info 'Stopping application proxy and currently promoted primary cleanly'
"${C[@]}" stop -t 120 proxy
"${C[@]}" --profile replica stop -t 120 replica
node_running proxy && fail 'proxy still running'
node_running replica && fail 'promoted replica still running'
node_running primary && fail 'old primary unexpectedly running'
# Remove stopped containers, NOT data volumes: they must not be docker-started
# with their outdated data after we remove failover.lock.
"${C[@]}" --profile replica rm -sf replica
"${C[@]}" rm -sf primary

info 'Creating NEW physical PostgreSQL volumes (no old volume removal)'
docker volume create --label "com.docker.compose.project=$PROJECT" \
  --label 'com.docker.compose.volume=ha_primary_after_failback' "$DEST_VOL" >/dev/null
docker volume create --label "com.docker.compose.project=$PROJECT" \
  --label 'com.docker.compose.volume=ha_replica_after_failback' "$NEW_REPLICA_VOL" >/dev/null

info "Cold-copying old promoted primary volume $SRC_VOL to $DEST_VOL"
docker run --rm --entrypoint sh \
  -v "$SRC_VOL:/source:ro" -v "$DEST_VOL:/destination" \
  postgres:16-alpine -euc '
  test -f /source/pgdata/PG_VERSION
  test ! -e /source/pgdata/standby.signal
  test ! -e /source/pgdata/postmaster.pid
  test ! -e /destination/pgdata/PG_VERSION
  cp -a /source/. /destination/
  test -s /destination/pgdata/global/pg_control
  test ! -e /destination/pgdata/standby.signal
  echo "Physical offline copy completed"
'

info 'Switching Compose volumes; saving original Compose outside Git'
cp -p docker-compose.ha.yml "$D/backups/docker-compose.ha.pre-failback_${STAMP}.yml"
python3 - <<'PY'
from pathlib import Path
p=Path('docker-compose.ha.yml')
s=p.read_text()
a='- ha_primary:/var/lib/postgresql/data'
b='- ha_replica:/var/lib/postgresql/data'
v='volumes:\n  ha_primary:\n  ha_replica:\n  ha_restore:'
assert s.count(a)==1 and s.count(b)==1, 'expected volume mounts absent or duplicated'
assert s.count(v)==1, 'top-level volumes block differs from original project'
s=s.replace(a,'- ha_primary_after_failback:/var/lib/postgresql/data')
s=s.replace(b,'- ha_replica_after_failback:/var/lib/postgresql/data')
s=s.replace(v,'volumes:\n  ha_primary:\n  ha_replica:\n  ha_primary_after_failback:\n  ha_replica_after_failback:\n  ha_restore:')
p.write_text(s)
PY
"${C[@]}" config -q || fail 'Compose config invalid; restore backed-up YAML'

info 'Fencing check: both old services must remain stopped'
node_running replica && fail 'replica unexpectedly running: do not remove lock'
node_running primary && fail 'primary unexpectedly running: do not remove lock'

info 'Archiving failover.lock, routing to primary:5434'
mv "$LOCK" "$D/state/failover.lock.before_${STAMP}"
printf 'TICKET_ACTIVE_DB=primary\n' > "$ROUTING"

info 'Starting NEW primary:5434 with cloned current database'
"${C[@]}" up -d --no-deps --force-recreate primary
ready=no
for i in $(seq 1 120); do
  if [[ "$(postgres 5434 -Atqc 'SELECT pg_is_in_recovery()' 2>/dev/null || true)" == f ]]; then
    ready=yes; break
  fi
  sleep 1
done
[[ "$ready" == yes ]] || fail 'new primary not ready. Do not start any former primary/replica; inspect docker logs'
AFTER="$(postgres 5434 -AtF '|' -c "$COUNT_SQL")"
printf 'before=%s\nafter=%s\n' "$BEFORE" "$AFTER" | tee -a "$LOG"
[[ "$AFTER" == "$BEFORE" ]] || fail 'row counts differ: proxy remains stopped, inspect before routing writes'

info 'Ensuring roles and physical replication slot on NEW primary'
./scripts/ha.sh roles || fail 'role/replication slot creation failed: proxy remains stopped'

info 'Rebuilding standby:5435 into NEW empty volume using pg_basebackup'
"${C[@]}" --profile replica up -d --no-deps --force-recreate replica
standby_ready=no
for i in $(seq 1 600); do
  if [[ "$(postgres 5435 -Atqc 'SELECT pg_is_in_recovery()' 2>/dev/null || true)" == t ]]; then
    standby_ready=yes; break
  fi
  if (( i % 30 == 0 )); then echo "waiting for basebackup... ${i}s"; fi
  sleep 1
done
[[ "$standby_ready" == yes ]] || fail 'standby not ready yet; new primary:5434 is already serving. Read replica logs.'

info 'Confirming PostgreSQL streaming state and actual data arrival'
streaming=no
for i in $(seq 1 60); do
  if [[ "$(postgres 5434 -Atqc "SELECT count(*) FROM pg_stat_replication WHERE application_name='ticket_replica' AND state='streaming'" 2>/dev/null || true)" == 1 ]]; then
    streaming=yes; break
  fi
  sleep 1
done
[[ "$streaming" == yes ]] || fail 'standby connected but primary streaming not confirmed'

info 'Starting HAProxy routing to new primary:5434'
"${C[@]}" up -d --no-deps --force-recreate proxy
[[ "$(postgres 5436 -Atqc 'SELECT pg_is_in_recovery()')" == f ]] || \
  fail 'proxy does not route to writable primary; inspect routing configuration'

./scripts/ha.sh replcheck || fail 'replication proof failed; inspect logs before declaring success'

printf '\nSUCCESS: original topology restored with fresh data and original Docker volumes preserved.\n'
printf 'Primary:5434 writable, replica:5435 standby, HAProxy:5436 -> primary.\n'
printf 'Verification and backup record: %s\n' "$LOG"
printf 'Original volumes remain: %s, %s. Do not delete them before separate review.\n' "$ORIGINAL_PRIMARY_VOL" "$SRC_VOL"
./scripts/ha.sh status
