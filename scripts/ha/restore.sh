#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
mkdir -p "$ROOT_DIR/artifacts/ha"
file="${1:-$(ls -1t "$TICKET_SECRETS_DIR"/backups/*.dump 2>/dev/null | head -n1)}"
[[ -n "$file" && -f "$file" ]] || { echo >&2 'Backup not found. Run ./scripts/ha.sh backup first'; exit 1; }
# Reset ONLY the isolated restore container/volume, never the primary/replica volumes.
"${COMPOSE[@]}" --profile restore stop restore >/dev/null 2>&1 || true
"${COMPOSE[@]}" --profile restore rm -sf restore >/dev/null 2>&1 || true
restore_volume="$(docker volume ls --filter 'label=com.docker.compose.project=ticket-platform-ha' --filter 'label=com.docker.compose.volume=ha_restore' --format '{{.Name}}' | head -n 1)"
[[ -z "$restore_volume" ]] || docker volume rm "$restore_volume" >/dev/null
"${COMPOSE[@]}" --profile restore up -d restore
for i in $(seq 1 60); do
  if psql_node restore ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT 1' >/dev/null 2>&1; then break; fi
  sleep 1
done
psql_node restore ticket_root "$POSTGRES_PASSWORD" -Atqc 'SELECT 1' >/dev/null
PGPASSWORD="$POSTGRES_PASSWORD" pg_restore \
  -h localhost -p "${TICKET_RESTORE_PORT:-5437}" -U ticket_root \
  -d ticket_platform -v --no-owner --no-acl "$file" \
  > "$ROOT_DIR/artifacts/ha/restore.log" 2>&1 || {
    tail -n 45 "$ROOT_DIR/artifacts/ha/restore.log" >&2; exit 1;
  }
echo 'Restore completed in isolated clean PostgreSQL instance.'
for table in events orders tickets ticket_scans; do
  source_rows="$(psql_node proxy ticket_admin "$TICKET_ADMIN_PASSWORD" -Atqc "SELECT count(*) FROM app.$table")"
  restored_rows="$(psql_node restore ticket_root "$POSTGRES_PASSWORD" -Atqc "SELECT count(*) FROM app.$table")"
  echo "$table source_current=$source_rows restore=$restored_rows"
  # Concurrent writes can occur after backup; output is evidence, not strict live equality.
done
cat > "$ROOT_DIR/artifacts/ha/restore_verification.sql" <<'SQL'
SELECT count(*) FROM app.events;
SELECT count(*) FROM app.orders;
SELECT count(*) FROM app.tickets;
SELECT count(*) FROM app.ticket_scans;
SQL
printf 'Backup used: %s\n' "$file"
printf 'Restore log: artifacts/ha/restore.log\n'
