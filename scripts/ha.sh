#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TICKET_SECRETS_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"
case "${1:-help}" in
  init) exec "$ROOT_DIR/scripts/ha/init_secrets.sh" ;;
  help|-h|--help)
    cat <<'HELP'
Usage: ./scripts/ha.sh COMMAND
  init      Create outside-repo secrets, self-signed lab CA and node certificates
  up        Start primary and proxy; wait for readiness
  roles     Create restricted login roles and replication slot
  migrate   Apply current migrations as ticket_admin and grants
  seed      Insert current seed data as ticket_admin
  replica   Clone/start the standby from primary
  status    Display recovery/replication status and current proxy target
  check     Run role and TLS positive/negative tests
  replcheck Insert via HAProxy, SELECT on replica, verify direction
  backup    Save a pg_dump custom-format backup
  restore   Restore latest backup into separate CLEAN restore container
  lag       Sample replication lag during a bulk load (defaults to dev)
  probe     Application connectivity probe through proxy
  watch     Watch for primary failure and automatically promote/switch
  failover  One-time controlled failover (requires stopped primary)
  demo      End-to-end lightweight HA acceptance demonstration
  app CMD   Execute existing project command as nonsuperuser ticket_app
  admin CMD Execute existing project command as nonsuperuser ticket_admin
  down      Stop HA containers (do not remove volumes)
HELP
    ;;
  up|roles|migrate|seed|replica|status|check|replcheck|backup|restore|lag|probe|watch|failover|demo|down|app|admin)
    cmd="$1"; shift
    exec "$ROOT_DIR/scripts/ha/${cmd}.sh" "$@" ;;
  *) echo "Unknown command: $1" >&2; exit 2 ;;
esac
