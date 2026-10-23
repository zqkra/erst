//! SQLite persistence and full-text search for Erst.
//!
//! [`Store`] owns one writer and one reader connection to the same database.
//! Writes go through the writer behind a mutex; reads use the reader on a
//! separate connection, so a UI query never waits for a capture transaction
//! longer than one statement. Everything is synchronous; callers run it off the
//! main thread.
//!
//! All timestamps are Unix milliseconds. Text bounding boxes are normalized to
//! the frame and scaled to `0..=10000`.

#![allow(clippy::missing_errors_doc)]

mod error;
mod model;
mod normalize;
mod schema;
mod store;

pub use error::StoreError;
pub use model::{
    EraseOutcome, FrameDetail, FrameStamp, LineBox, LineSource, NewFrame, NewLine,
    RecoveredSegment, ReminderRow, SearchHit, SearchParams, SearchPlan, SegmentRow, SpanRow,
    StorageStats, TrackFrameRow,
};
pub use store::Store;
