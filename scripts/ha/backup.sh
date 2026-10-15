#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
DIR="$TICKET_SECRETS_DIR/backups"
mkdir -p "$DIR"
umask 077
file="$DIR/ticket_platform_$(date -u +%Y%m%dT%H%M%SZ).dump"
PGPASSWORD="$TICKET_ADMIN_PASSWORD" pg_dump \
  -h localhost -p "${TICKET_PROXY_PORT:-5436}" -U ticket_admin \
  -d ticket_platform -Fc --no-owner --no-acl -f "$file"
pg_restore --list "$file" >/dev/null
printf 'Backup verified with pg_restore --list: %s\n' "$file"
