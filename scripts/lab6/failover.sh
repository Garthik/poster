#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lab6/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_secrets
runner status
control="$LAB6_ARTIFACTS/control"
mkdir -p "$control"
rm -f "$control/ready" "$control/stopped" "$control/recovered" "$control/restarted" "$control/done" "$control/primary-service"
target=''; cid=''
cleanup() {
  local code=$?
  if [[ -n "$target" ]]; then compose start "$target" || code=1; fi
  if [[ -n "$cid" ]]; then
    docker logs "$cid" > "$LAB6_ARTIFACTS/logs/failover-client.log" 2>&1 || true
    docker rm -f "$cid" >/dev/null 2>&1 || true
  fi
  if (( code != 0 )); then echo 'FAIL: failover experiment; attempted to restore stopped node. See logs/failover-client.log' >&2; fi
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
cid="$(compose run -d -T --no-deps runner failover-client)"
wait_file() {
  local file="$1" i
  for ((i=0;i<180;i++)); do
    [[ -s "$control/$file" ]] && return 0
    if [[ "$(docker inspect -f '{{.State.Running}}' "$cid")" != true ]]; then
      # The client can publish the final signal and exit between the file test
      # and docker inspect. Recheck the signal before treating an exit as failure.
      [[ -s "$control/$file" ]] && return 0
      docker logs "$cid"
      return 1
    fi
    sleep 1
  done
  echo "Timed out waiting for $file" >&2; return 1
}
wait_file ready
read -r target < "$control/primary-service"
case "$target" in mongo1|mongo2|mongo3) ;; *) echo 'Invalid PRIMARY target' >&2; exit 2;; esac
printf 'Stopping dynamically discovered PRIMARY service: %s\n' "$target"
compose stop -t 10 "$target"
printf 'stopped\n' > "$control/stopped"
wait_file recovered
compose start "$target"
printf 'restarted\n' > "$control/restarted"
wait_file 'done'
exit_code="$(docker wait "$cid")"
printf 'Failover client process exit code: <%s>\n' "$exit_code"
docker inspect --format '{{json .State}}' "$cid" > "$LAB6_ARTIFACTS/logs/failover-client-state.json"
docker logs "$cid"
[[ "$exit_code" == 0 ]]
docker logs "$cid" > "$LAB6_ARTIFACTS/logs/failover-client.log" 2>&1
docker rm "$cid" >/dev/null
cid=''
runner check --with-failover
