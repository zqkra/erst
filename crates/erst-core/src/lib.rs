//! Pure algorithms for Erst. No I/O, no platform APIs.

pub mod activity;
pub mod diff;
pub mod error;
pub mod heat;
pub mod query;
pub mod retention;
pub mod settings;
pub mod time;
pub mod track;

pub use activity::{
    ActivityBucket, ActivitySummary, AppTotal, BucketKind, Category, SiteTotal, Span, categorize,
    summarize,
};
pub use diff::{FrameContext, KeepDecision, KeepPolicy, KeepReason, KeepState, Thumbnail};
pub use error::CoreError;
pub use heat::{DayHeat, HOURS_PER_DAY, heat_buckets, hourly_heat};
pub use query::{ParsedQuery, parse};
pub use retention::{
    AfterLighterCopy, REDUCED_SIZE_FACTOR, RetentionAction, RetentionKind, RetentionPolicy,
    SegmentInfo, Tier, plan,
};
pub use time::{
    MAX_BUCKETS, MS_PER_DAY, MS_PER_HOUR, MS_PER_MINUTE, TimeRange, days_from_civil,
    local_day_buckets, local_day_containing, local_day_count, local_day_of_text, now_ms,
};
pub use track::{SESSION_GAP_MS, SegmentKey, TrackSegment, group_segments, url_host};
