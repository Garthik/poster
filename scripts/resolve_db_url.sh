#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${DB_URL:-}" ]]; then
    printf '%s\n' "$DB_URL"
    exit 0
fi

host_port=""
if command -v docker >/dev/null 2>&1; then
    host_port="$(
        (docker compose -f "$ROOT_DIR/docker-compose.yml" port postgres 5432 2>/dev/null \
            | tail -n 1 \
            | awk -F: '{print $NF}' \
            | tr -d '[:space:]') || true
    )"
fi

if ! [[ "$host_port" =~ ^[0-9]+$ ]]; then
    host_port="${POSTGRES_HOST_PORT:-5434}"
fi

printf 'postgresql://ticket_app:ticket_app@localhost:%s/ticket_platform\n' "$host_port"
