-- Privacy: overwrite erased terms in the full-text index instead of leaving
-- them in freed pages. The bundled SQLite is 3.53.2, which supports
-- 'secure-delete'. The setting is stored in the FTS5 configuration table, so it
-- applies to every later write on this database.
INSERT INTO text_lines_fts(text_lines_fts, rank) VALUES('secure-delete', 1);

-- Last visit lookup for the moment inspector: the most recent span of one app
-- before a point in time reads straight from this index.
CREATE INDEX spans_app_started ON spans(app_id, started_at);
