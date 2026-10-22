-- Where a frame line came from: 0 OCR, 1 the focused window's accessibility tree,
-- 2 the frame's window title. Lines from before this migration are OCR.
ALTER TABLE frame_lines ADD COLUMN source INTEGER NOT NULL DEFAULT 0;
