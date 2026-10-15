#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
psql_node primary ticket_admin "$TICKET_ADMIN_PASSWORD" -f "$ROOT_DIR/seeds/002_seed_data.sql"
