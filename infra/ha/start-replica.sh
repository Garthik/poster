#!/bin/sh
set -eu
PGDATA=${PGDATA:-/var/lib/postgresql/data/pgdata}
mkdir -p /var/lib/postgresql/tls "$PGDATA"
cp /etc/ticket/tls/server.crt /var/lib/postgresql/tls/server.crt
cp /etc/ticket/tls/server.key /var/lib/postgresql/tls/server.key
cp /etc/ticket/tls/ca.crt /var/lib/postgresql/tls/ca.crt
chown postgres:postgres /var/lib/postgresql/tls/server.crt /var/lib/postgresql/tls/server.key /var/lib/postgresql/tls/ca.crt "$PGDATA"
chmod 700 "$PGDATA"
chmod 600 /var/lib/postgresql/tls/server.key
chmod 644 /var/lib/postgresql/tls/ca.crt
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo 'Cloning primary over verified TLS ...'
  export PGPASSWORD="$TICKET_REPLICATION_PASSWORD"
  export PGSSLMODE=verify-full
  export PGSSLROOTCERT=/var/lib/postgresql/tls/ca.crt
  su-exec postgres pg_basebackup -h primary -p 5432 -U ticket_replication \
    -D "$PGDATA" -Fp -Xs -R -S ticket_replica_slot -P
  printf 'primary:5432:replication:ticket_replication:%s\n' "$TICKET_REPLICATION_PASSWORD" > "$PGDATA/.pgpass"
  chown postgres:postgres "$PGDATA/.pgpass"
  chmod 600 "$PGDATA/.pgpass"
  cat >> "$PGDATA/postgresql.auto.conf" <<'CONF'
primary_conninfo = 'host=primary port=5432 user=ticket_replication passfile=/var/lib/postgresql/data/pgdata/.pgpass sslmode=verify-full sslrootcert=/var/lib/postgresql/tls/ca.crt application_name=ticket_replica'
primary_slot_name = 'ticket_replica_slot'
CONF
  chown postgres:postgres "$PGDATA/postgresql.auto.conf"
fi
exec /usr/local/bin/docker-entrypoint.sh postgres \
  -c ssl=on \
  -c ssl_min_protocol_version=TLSv1.2 \
  -c ssl_cert_file=/var/lib/postgresql/tls/server.crt \
  -c ssl_key_file=/var/lib/postgresql/tls/server.key \
  -c hba_file=/etc/ticket/pg_hba.conf \
  -c hot_standby=on \
  -c password_encryption=scram-sha-256
