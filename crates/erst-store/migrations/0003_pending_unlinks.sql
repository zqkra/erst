-- A video file cannot be unlinked inside a transaction. The erase and retention
-- paths record every relative path they detach here, in the same transaction
-- that removes the row, so a crash between the commit and the unlink cannot
-- lose the path. The engine drains this table when it opens the database.
CREATE TABLE pending_unlinks (path TEXT PRIMARY KEY);

-- Two identical lines on one row (the same "OK" twice) are separate boxes. The
-- primary key needs x to tell them apart. Rebuild the table and copy its rows,
-- then recreate the lookup index the search plans read.
CREATE TABLE frame_lines_v3 (
  frame_id INTEGER NOT NULL REFERENCES frames(id) ON DELETE CASCADE,
  line_id  INTEGER NOT NULL REFERENCES text_lines(id),
  x INTEGER NOT NULL, y INTEGER NOT NULL, w INTEGER NOT NULL, h INTEGER NOT NULL,
  PRIMARY KEY (frame_id, line_id, y, x)
) WITHOUT ROWID;

INSERT INTO frame_lines_v3 (frame_id, line_id, x, y, w, h)
SELECT frame_id, line_id, x, y, w, h FROM frame_lines;

DROP TABLE frame_lines;
ALTER TABLE frame_lines_v3 RENAME TO frame_lines;
CREATE INDEX frame_lines_line ON frame_lines(line_id);
