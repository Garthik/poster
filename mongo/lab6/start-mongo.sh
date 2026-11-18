#!/usr/bin/env bash
set -euo pipefail
# Bind-mounted secrets can have unsuitable ownership on Docker Desktop / DrvFS.
# Copy into the container filesystem; never relax permissions on the source.
install -o mongodb -g mongodb -m 400 /run/secrets/rs_keyfile /run/lab6-keyfile
# Compose file-backed secrets retain host mode 0600. Read as root before the
# official entrypoint re-executes as mongodb; do not make private files public.
MONGO_INITDB_ROOT_USERNAME="$(cat /run/secrets/root_user)"
MONGO_INITDB_ROOT_PASSWORD="$(cat /run/secrets/root_password)"
export MONGO_INITDB_ROOT_USERNAME MONGO_INITDB_ROOT_PASSWORD
unset MONGO_INITDB_ROOT_USERNAME_FILE MONGO_INITDB_ROOT_PASSWORD_FILE
exec /usr/local/bin/docker-entrypoint.sh "$@"
