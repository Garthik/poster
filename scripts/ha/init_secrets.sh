#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"
if [[ -e "$DIR/primary.env" ]]; then
  echo "Refusing to overwrite existing secrets: $DIR" >&2
  echo 'To retain database access, DO NOT regenerate passwords on an initialized cluster.' >&2
  exit 1
fi
command -v openssl >/dev/null || { echo 'openssl is required' >&2; exit 127; }
umask 077
mkdir -p "$DIR/tls" "$DIR/tls/primary" "$DIR/tls/replica" "$DIR/state" "$DIR/restore-state" "$DIR/backups"
chmod 700 "$DIR" "$DIR/tls" "$DIR/tls/primary" "$DIR/tls/replica" "$DIR/state" "$DIR/restore-state" "$DIR/backups"
secret() { openssl rand -hex 24; }
root_pw="$(secret)"
admin_pw="$(secret)"
app_pw="$(secret)"
analyst_pw="$(secret)"
repl_pw="$(secret)"
cat > "$DIR/primary.env" <<ENV
POSTGRES_DB=ticket_platform
POSTGRES_USER=ticket_root
POSTGRES_PASSWORD=$root_pw
PGDATA=/var/lib/postgresql/data/pgdata
ENV
cat > "$DIR/roles.env" <<ENV
TICKET_ADMIN_PASSWORD=$admin_pw
TICKET_APP_PASSWORD=$app_pw
TICKET_ANALYST_PASSWORD=$analyst_pw
TICKET_REPLICATION_PASSWORD=$repl_pw
ENV
cat > "$DIR/replica.env" <<ENV
PGDATA=/var/lib/postgresql/data/pgdata
TICKET_REPLICATION_PASSWORD=$repl_pw
ENV
printf 'TICKET_ACTIVE_DB=primary\n' > "$DIR/routing.env"
cd "$DIR/tls"
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 \
  -subj '/CN=Ticket Platform Lab CA' -keyout ca.key -out ca.crt >/dev/null 2>&1
for node in primary replica; do
  openssl req -new -newkey rsa:2048 -nodes \
    -subj "/CN=$node" -keyout "$node.key" -out "$node.csr" >/dev/null 2>&1
  cat > "$node.ext" <<EXT
subjectAltName=DNS:$node,DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EXT
  openssl x509 -req -in "$node.csr" -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out "$node.crt" -days 365 -sha256 \
    -extfile "$node.ext" >/dev/null 2>&1
  cp "$node.crt" "$node/server.crt"
  cp "$node.key" "$node/server.key"
  cp ca.crt "$node/ca.crt"
  rm -f "$node.csr" "$node.ext"
done
chmod 600 "$DIR"/*.env "$DIR/tls"/*.key "$DIR/tls"/*/*.key
chmod 644 "$DIR/tls"/*.crt "$DIR/tls"/*/*.crt  # CA cert must be readable by postgres on standby
printf 'Created private files outside repository: %s\n' "$DIR"
echo 'NOTE: certificates are lab CA certificates; clients must use sslmode=verify-full and ca.crt.'
echo 'To replace credentials rotate roles and certificates explicitly; do not rerun init against an existing cluster.'
