#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
mkdir -p "$ROOT_DIR/artifacts/ha"
LOG="$ROOT_DIR/artifacts/ha/security_checks.txt"
: > "$LOG"
pass() { echo "PASS: $*" | tee -a "$LOG"; }
fail() { echo "FAIL: $*" | tee -a "$LOG"; exit 1; }
expect_fail() {
  local label="$1"; shift
  if "$@" > "$ROOT_DIR/artifacts/ha/denied_last.txt" 2>&1; then
    fail "$label unexpectedly SUCCEEDED"
  fi
  pass "$label denied (expected)"
}
query() {
  local username="$1" pass="$2" sql="$3"
  psql_node proxy "$username" "$pass" -Atqc "$sql"
}
query ticket_admin "$TICKET_ADMIN_PASSWORD" 'SELECT 1' >/dev/null || fail 'admin login'
pass 'Administrator login over verified TLS'
query ticket_app "$TICKET_APP_PASSWORD" 'SELECT count(*) FROM app.events' >/dev/null || fail 'application read'
pass 'Application SELECT permitted'
query ticket_app "$TICKET_APP_PASSWORD" "BEGIN; INSERT INTO app.venues(name,capacity) VALUES ('HA APP ALLOWED INSERT TEST',10); ROLLBACK;" >/dev/null || fail 'application DML'
pass 'Application INSERT permitted (rolled back)'
expect_fail 'Administrator CREATE ROLE' query ticket_admin "$TICKET_ADMIN_PASSWORD" 'CREATE ROLE should_not_exist_ha_admin;' 
query ticket_analyst "$TICKET_ANALYST_PASSWORD" 'SELECT count(*) FROM app.orders' >/dev/null || fail 'analyst read'
pass 'Analyst SELECT permitted'
expect_fail 'Analyst CREATE TABLE' query ticket_analyst "$TICKET_ANALYST_PASSWORD" 'CREATE TABLE app.should_not_exist_ha_analyst(id int);'
query ticket_analyst "$TICKET_ANALYST_PASSWORD" 'SELECT id,email,role FROM app.users LIMIT 1' >/dev/null || fail 'analyst projected users'
pass 'Analyst nonsensitive user columns permitted'
expect_fail 'Application CREATE ROLE' query ticket_app "$TICKET_APP_PASSWORD" 'CREATE ROLE should_not_exist_ha_lab;'
expect_fail 'Application CREATE TABLE' query ticket_app "$TICKET_APP_PASSWORD" 'CREATE TABLE app.should_not_exist_ha_lab(id integer);'
expect_fail 'Application migration metadata' query ticket_app "$TICKET_APP_PASSWORD" 'SELECT * FROM app.schema_migrations;'
expect_fail 'Analyst INSERT' query ticket_analyst "$TICKET_ANALYST_PASSWORD" "INSERT INTO app.venues(name,capacity) VALUES ('DENIED',1);"
expect_fail 'Analyst password_hash' query ticket_analyst "$TICKET_ANALYST_PASSWORD" 'SELECT password_hash FROM app.users LIMIT 1;'
query ticket_admin "$TICKET_ADMIN_PASSWORD" 'CREATE TABLE app.ha_admin_permission_test(id integer); DROP TABLE app.ha_admin_permission_test;' >/dev/null || fail 'admin DDL'
pass 'Administrator schema DDL permitted'
flags="$(query ticket_admin "$TICKET_ADMIN_PASSWORD" "SELECT count(*) FROM pg_roles WHERE rolname IN ('ticket_admin','ticket_app','ticket_analyst') AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)")"
[[ "$flags" == 0 ]] || fail 'One or more nonprivileged roles holds a cluster-level privilege'
pass 'All three login roles are non-superusers, non-createdb, non-createrole, non-replication'
"$(dirname "$0")/tls.sh" | tee -a "$LOG"
echo "Security test log: $LOG"
