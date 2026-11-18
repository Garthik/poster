#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lab6/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lab6/lib.sh"
usage() {
  cat <<'USAGE'
bash scripts/lab6.sh init          # private credentials/key, no overwrites
bash scripts/lab6.sh up            # 3 authenticated nodes, bootstrap, wait for all
bash scripts/lab6.sh status        # rs.status(), exactly 1 PRIMARY + 2 SECONDARY
bash scripts/lab6.sh seed          # deterministic Lab6-only documents
bash scripts/lab6.sh benchmark     # 2 queries, warmups, >=5 before/after explains
bash scripts/lab6.sh bulk          # unordered bulk, partial failure, assertions
bash scripts/lab6.sh transaction   # commit / rollback / real error-label retries
bash scripts/lab6.sh index-write   # same-data insertion/update/storage experiment
bash scripts/lab6.sh check         # live state + semantic artifact verification
bash scripts/lab6.sh all           # up + all nondisruptive experiments + check
bash scripts/lab6.sh failover --yes # explicitly stop current PRIMARY and recover
bash scripts/lab6.sh check --with-failover # require completed failover evidence too
bash scripts/lab6.sh test          # local unit tests inside runner
bash scripts/lab6.sh shell [mongo1|mongo2|mongo3] # authenticated interactive mongosh
bash scripts/lab6.sh down          # stop only Lab6, keep volumes
USAGE
}
main() {
  case "${1:-help}" in
    init) bash "$ROOT_DIR/scripts/lab6/init.sh" ;;
    up)
      require_secrets
      compose up -d --no-recreate --wait --wait-timeout 240 mongo1 mongo2 mongo3
      compose exec -T mongo1 mongosh --quiet --port 27101 --file /work/mongo/lab6/bootstrap.js
      compose build runner
      runner status ;;
    status|seed|benchmark|bulk|transaction|index-write|check|test) runner "$@" ;;
    all)
      main up
      local step
      for step in seed benchmark bulk transaction index-write test check; do runner "$step"; done ;;
    failover)
      [[ "${2:-}" == --yes ]] || { echo 'Disruptive test stops the current Lab6 PRIMARY. Explicit command: bash scripts/lab6.sh failover --yes' >&2; return 2; }
      bash "$ROOT_DIR/scripts/lab6/failover.sh" ;;
    shell)
      local service="${2:-mongo1}" port
      case "$service" in mongo1) port=27101;; mongo2) port=27102;; mongo3) port=27103;; *) return 2;; esac
      compose exec "$service" mongosh --quiet --port "$port" --file /work/mongo/lab6/shell.js --shell ;;
    down) require_secrets; compose down ;;
    help|-h|--help) usage ;;
    *) usage >&2; return 2 ;;
  esac
}
case "${1:-help}" in help|-h|--help|shell) main "$@"; exit $?;; esac
# Serialize fixture/index changes and failpoint experiments across invocations.
exec 9> "$LAB6_ARTIFACTS/.lab6.lock"
flock -n 9 || { echo 'Another Lab6 command is running' >&2; exit 2; }
log="$LAB6_ARTIFACTS/logs/$(date -u +%Y%m%dT%H%M%SZ)-${1:-help}-$$.log"
trap 'snapshot' EXIT
main "$@" 2>&1 | tee "$log"
