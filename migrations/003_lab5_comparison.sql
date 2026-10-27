BEGIN;
-- Temporary comparison projection, not the source of truth for editorial documents.
CREATE TABLE IF NOT EXISTS app.lab5_content_compare (
    slug TEXT PRIMARY KEY,
    payload JSONB NOT NULL,
    imported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT lab5_compare_payload_obj CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT lab5_compare_slug_match CHECK (payload->>'slug' = slug)
);
CREATE INDEX IF NOT EXISTS lab5_content_compare_status_idx
    ON app.lab5_content_compare ((payload->>'status'));
CREATE INDEX IF NOT EXISTS lab5_content_compare_keywords_gin
    ON app.lab5_content_compare USING gin ((payload->'keywords'));
INSERT INTO app.schema_migrations(version)
VALUES ('003_lab5_comparison') ON CONFLICT (version) DO NOTHING;
COMMIT;
