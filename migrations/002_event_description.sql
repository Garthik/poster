BEGIN;

ALTER TABLE app.events
    ADD COLUMN IF NOT EXISTS description TEXT;

COMMENT ON COLUMN app.events.description IS
    'Optional public description. Additive nullable change for backward-compatible deployment.';

INSERT INTO app.schema_migrations(version)
VALUES ('002_event_description')
ON CONFLICT (version) DO NOTHING;

COMMIT;
