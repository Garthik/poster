\set ON_ERROR_STOP on
-- This file must be run as ticket_root; passwords arrive via -v, never stored in SQL.
SELECT 'CREATE ROLE ticket_admin LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
WHERE NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='ticket_admin') \gexec
SELECT 'CREATE ROLE ticket_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
WHERE NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='ticket_app') \gexec
SELECT 'CREATE ROLE ticket_analyst LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
WHERE NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='ticket_analyst') \gexec
SELECT 'CREATE ROLE ticket_replication LOGIN REPLICATION NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS'
WHERE NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='ticket_replication') \gexec
ALTER ROLE ticket_admin PASSWORD :'admin_pw';
ALTER ROLE ticket_app PASSWORD :'app_pw';
ALTER ROLE ticket_analyst PASSWORD :'analyst_pw';
ALTER ROLE ticket_replication PASSWORD :'repl_pw';
REVOKE CONNECT, TEMPORARY, CREATE ON DATABASE ticket_platform FROM PUBLIC;
GRANT CONNECT, CREATE, TEMPORARY ON DATABASE ticket_platform TO ticket_admin;
GRANT CONNECT ON DATABASE ticket_platform TO ticket_app, ticket_analyst;
-- Install trusted pgcrypto in public as bootstrap owner before the app migrations.
-- The migration has CREATE EXTENSION IF NOT EXISTS, so this is idempotent.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO ticket_admin, ticket_app;
-- Create a persistent physical replication slot before basebackup (idempotently).
SELECT 'SELECT pg_create_physical_replication_slot(''ticket_replica_slot'');'
WHERE NOT EXISTS(SELECT 1 FROM pg_replication_slots WHERE slot_name='ticket_replica_slot') \gexec
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication
FROM pg_roles WHERE rolname IN ('ticket_admin','ticket_app','ticket_analyst','ticket_replication')
ORDER BY rolname;
