\set ON_ERROR_STOP on
-- Run as ticket_admin AFTER migrations, so only the administrator owns schema objects.
REVOKE ALL ON SCHEMA app FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA app FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO ticket_app, ticket_analyst;
-- pgcrypto.digest() resides in public, and the generator runs as ticket_app.
GRANT SELECT, INSERT, UPDATE, DELETE ON
  app.users, app.venues, app.events, app.venue_seats, app.ticket_categories,
  app.event_seats, app.orders, app.order_items, app.tickets, app.payments,
  app.refunds, app.ticket_scans TO ticket_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO ticket_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO ticket_app;
-- Analyst reads business data but not password_hash or internal migration metadata.
GRANT SELECT ON
  app.venues, app.events, app.venue_seats, app.ticket_categories,
  app.event_seats, app.orders, app.order_items, app.tickets, app.payments,
  app.refunds, app.ticket_scans TO ticket_analyst;
GRANT SELECT (id,email,role,created_at) ON app.users TO ticket_analyst;
-- Only the administrator may create new objects; no role may modify schema_migrations.
ALTER DEFAULT PRIVILEGES FOR ROLE ticket_admin IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ticket_app;
ALTER DEFAULT PRIVILEGES FOR ROLE ticket_admin IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO ticket_app;
ALTER DEFAULT PRIVILEGES FOR ROLE ticket_admin IN SCHEMA app
  GRANT EXECUTE ON FUNCTIONS TO ticket_app;
-- PG16 PUBLIC EXECUTE default must also be revoked for future functions.
ALTER DEFAULT PRIVILEGES FOR ROLE ticket_admin
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
