CREATE TABLE apps (
  id        INTEGER PRIMARY KEY,
  bundle_id TEXT NOT NULL UNIQUE,
  name      TEXT NOT NULL
);

CREATE TABLE segments (
  id          INTEGER PRIMARY KEY,
  path        TEXT,                 -- NULL once the video was deleted by retention
  started_at  INTEGER NOT NULL,
  ended_at    INTEGER,              -- NULL while open
  width       INTEGER NOT NULL,
  height      INTEGER NOT NULL,
  bytes       INTEGER NOT NULL DEFAULT 0,
  tier        INTEGER NOT NULL DEFAULT 0  -- 0 full, 1 reduced, 2 text only
);

CREATE TABLE frames (
  id            INTEGER PRIMARY KEY,
  captured_at   INTEGER NOT NULL,
  segment_id    INTEGER NOT NULL REFERENCES segments(id),
  pts_ms        INTEGER NOT NULL,   -- presentation time inside the segment
  app_id        INTEGER REFERENCES apps(id),
  window_title  TEXT,
  url           TEXT,
  change_ratio  REAL NOT NULL
);
CREATE INDEX frames_captured_at ON frames(captured_at);

CREATE TABLE text_lines (
  id    INTEGER PRIMARY KEY,
  hash  BLOB NOT NULL UNIQUE,       -- 16-byte hash of the normalized text
  text  TEXT NOT NULL
);

CREATE TABLE frame_lines (
  frame_id INTEGER NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  line_id  INTEGER NOT NULL REFERENCES text_lines(id),
  x INTEGER NOT NULL, y INTEGER NOT NULL, w INTEGER NOT NULL, h INTEGER NOT NULL,
  PRIMARY KEY (frame_id, line_id, y)
) WITHOUT ROWID;
CREATE INDEX frame_lines_line ON frame_lines(line_id);

CREATE VIRTUAL TABLE text_lines_fts USING fts5(
  text, content='text_lines', content_rowid='id',
  tokenize='unicode61 remove_diacritics 2', prefix='2 3'
);

CREATE TRIGGER text_lines_ai AFTER INSERT ON text_lines BEGIN
  INSERT INTO text_lines_fts(rowid, text) VALUES (new.id, new.text);
END;

CREATE TRIGGER text_lines_ad AFTER DELETE ON text_lines BEGIN
  INSERT INTO text_lines_fts(text_lines_fts, rowid, text)
  VALUES ('delete', old.id, old.text);
END;

CREATE TRIGGER text_lines_au AFTER UPDATE ON text_lines BEGIN
  INSERT INTO text_lines_fts(text_lines_fts, rowid, text)
  VALUES ('delete', old.id, old.text);
  INSERT INTO text_lines_fts(rowid, text) VALUES (new.id, new.text);
END;

CREATE TABLE spans (
  id           INTEGER PRIMARY KEY,
  app_id       INTEGER NOT NULL REFERENCES apps(id),
  window_title TEXT,
  url          TEXT,
  started_at   INTEGER NOT NULL,
  ended_at     INTEGER              -- NULL while open
);
CREATE INDEX spans_started_at ON spans(started_at);

CREATE TABLE marks (
  id          INTEGER PRIMARY KEY,
  frame_id    INTEGER REFERENCES frames(id) ON DELETE SET NULL,
  created_at  INTEGER NOT NULL,
  note        TEXT
);

CREATE TABLE reminders (
  id          INTEGER PRIMARY KEY,
  frame_id    INTEGER REFERENCES frames(id) ON DELETE SET NULL,
  created_at  INTEGER NOT NULL,
  due_at      INTEGER NOT NULL,
  note        TEXT NOT NULL,
  done_at     INTEGER
);

CREATE TABLE excluded_apps (bundle_id TEXT PRIMARY KEY);

CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
