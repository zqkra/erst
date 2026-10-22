-- One packed layout per frame, and runs of frames per line, replace one row per
-- line per frame. The step in `schema.rs` copies `frame_lines` into them and
-- drops it in the same transaction.
CREATE TABLE frame_text (
  frame_id INTEGER PRIMARY KEY REFERENCES frames(id) ON DELETE CASCADE,
  layout   BLOB NOT NULL
);
CREATE TABLE line_runs (
  line_id     INTEGER NOT NULL REFERENCES text_lines(id),
  first_frame INTEGER NOT NULL,
  last_frame  INTEGER NOT NULL,
  PRIMARY KEY (line_id, first_frame)
) WITHOUT ROWID;
