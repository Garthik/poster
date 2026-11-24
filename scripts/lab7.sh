#!/usr/bin/env bash
set -euo pipefail
layout=${1:-}
action=${2:-}
case "$layout" in standalone|template) ;; *) echo 'Usage: bash scripts/lab7.sh {standalone|template} {up|demo|reports|apply|refresh|rebuild|redis|status|down}' >&2; exit 2;; esac
case "$action" in up|demo|reports|apply|refresh|rebuild|redis|status|down) ;; *) echo 'Choose up, demo, reports, apply, refresh, rebuild, redis, status or down.' >&2; exit 2;; esac
export LAB7_ROOT
LAB7_ROOT=$(cd "$(dirname "$0")/.." && pwd)
export LAB7_DIR="$LAB7_ROOT/mongo/lab7" LAB7_EVIDENCE="$LAB7_ROOT/artifacts/lab7/$layout"
export LAB7_SECRET_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}/lab7/$layout"
export MONGO_KEYFILE_PATH="$LAB7_SECRET_DIR/mongo-keyfile"
mkdir -p "$LAB7_SECRET_DIR" "$LAB7_EVIDENCE"
chmod 700 "$LAB7_SECRET_DIR"
exec 9>"$LAB7_SECRET_DIR/run.lock"
flock -w 120 9 || { echo 'Another Sprint 7 run is active.' >&2; exit 1; }
for file in mongo-keyfile password; do
  if [[ ! -s "$LAB7_SECRET_DIR/$file" ]]; then
    (umask 077; openssl rand -base64 48 > "$LAB7_SECRET_DIR/$file.tmp")
    mv "$LAB7_SECRET_DIR/$file.tmp" "$LAB7_SECRET_DIR/$file"
  fi
done
export LAB7_PORT=27217
compose_file="$LAB7_DIR/compose.yaml"
shard_services=(mongo1)
if [[ $layout == template ]]; then
  export LAB7_TEMPLATE_COMPOSE="${LAB7_TEMPLATE_COMPOSE:-/mnt/c/TomeD/VSCode/sprint-06-mongodb/compose.yaml}"
  [[ -r "$LAB7_TEMPLATE_COMPOSE" ]] || { echo 'Set LAB7_TEMPLATE_COMPOSE to the supplied compose.yaml.' >&2; exit 2; }
  export LAB7_PORT=27317 MONGO1_PORT=27321 MONGO2_PORT=27322 MONGO3_PORT=27323
  # These satisfy interpolation in the original file. The router creates the cluster account.
  export MONGO_ROOT_USERNAME=lab7_admin MONGO_ROOT_PASSWORD
  MONGO_ROOT_PASSWORD=$(<"$LAB7_SECRET_DIR/password")
  export MONGO_APP_DATABASE=ticket_platform_docs MONGO_APP_USERNAME=lab7_app MONGO_ANALYST_USERNAME=lab7_analyst
  export MONGO_APP_PASSWORD="$MONGO_ROOT_PASSWORD" MONGO_ANALYST_PASSWORD="$MONGO_ROOT_PASSWORD"
  compose_file="$LAB7_DIR/compose.template.yaml"
  shard_services=(mongo1 mongo2 mongo3)
fi
compose() { docker compose -p "ticket-lab7-$layout" -f "$compose_file" "$@"; }
router_script() {
  compose exec -T -u 0 -e "LAB7_LAYOUT=$layout" -e "LAB7_ACTION=$1" router mongosh --quiet --nodb --file "/work/lab7/$2"
}
init_set() {
  local service=$1 setname=$2 hosts=$3
  compose exec -T -e "RS_NAME=$setname" -e "RS_HOSTS=$hosts" "$service" mongosh --quiet --host 127.0.0.1 --port 27017 --file /dev/stdin < "$LAB7_DIR/init-set.js"
}
wait_service() {
  local service=$1 i
  for ((i=0;i<60;i++)); do
    if compose exec -T "$service" mongosh --quiet --eval 'quit(db.adminCommand({ping:1}).ok ? 0 : 1)' >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  echo "Timeout starting $service" >&2
  return 1
}
up() {
  compose up -d cfg "${shard_services[@]}" b
  for service in cfg "${shard_services[@]}" b; do wait_service "$service"; done
  local hosts
  hosts=$(IFS=,; echo "${shard_services[*]}")
  init_set cfg cfg7 cfg
  init_set mongo1 shardA "$hosts"
  init_set b shardB b
  compose up -d router
  wait_service router
  router_script init router.js
}
case "$action" in
  up) up ;;
  demo) up; router_script demo run.js ;;
  status) router_script status router.js ;;
  reports|apply|refresh|rebuild) router_script "$action" run.js ;;
  redis)
    [[ -s "$LAB7_EVIDENCE/redis-source.json" ]] || { echo 'Run demo or reports first.' >&2; exit 2; }
    docker run --rm -i --network none -v "$LAB7_DIR:/work:ro" -v "$LAB7_EVIDENCE:/evidence:ro" redis:7.4-alpine sh /work/redis-sample.sh > "$LAB7_EVIDENCE/redis.json.tmp"
    python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["passed"]' "$LAB7_EVIDENCE/redis.json.tmp"
    mv "$LAB7_EVIDENCE/redis.json.tmp" "$LAB7_EVIDENCE/redis.json"
    echo "Redis measurements saved in $LAB7_EVIDENCE/redis.json" ;;
  down) compose down ;;
esac
