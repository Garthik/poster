#!/bin/sh
set -eu
if [ -f /etc/ticket/state/failover.lock ]; then
  echo >&2 'REFUSING START: this node was the old primary. Rebuild it as standby; do not risk split brain.'
  exit 77
fi
mkdir -p /var/lib/postgresql/tls
cp /etc/ticket/tls/server.crt /var/lib/postgresql/tls/server.crt
cp /etc/ticket/tls/server.key /var/lib/postgresql/tls/server.key
chown postgres:postgres /var/lib/postgresql/tls/server.crt /var/lib/postgresql/tls/server.key
chmod 600 /var/lib/postgresql/tls/server.key
exec /usr/local/bin/docker-entrypoint.sh postgres \
  -c ssl=on \
  -c ssl_min_protocol_version=TLSv1.2 \
  -c ssl_cert_file=/var/lib/postgresql/tls/server.crt \
  -c ssl_key_file=/var/lib/postgresql/tls/server.key \
  -c hba_file=/etc/ticket/pg_hba.conf \
  -c wal_level=replica \
  -c max_wal_senders=10 \
  -c max_replication_slots=10 \
  -c max_slot_wal_keep_size=2GB \
  -c wal_keep_size=512MB \
  -c hot_standby=on \
  -c password_encryption=scram-sha-256
