//! Frame change detection: luma thumbnails, tile diffing, and the keep policy.

use crate::error::CoreError;

/// A downsampled grayscale frame with row-major luma samples.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Thumbnail {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// One luma byte per pixel, `width * height` bytes in total.
    pub luma: Vec<u8>,
}

impl Thumbnail {
    /// Builds a thumbnail after checking its geometry.
    ///
    /// # Errors
    ///
    /// Returns [`CoreError::InvalidThumbnail`] when a dimension is zero or when
    /// `luma.len()` is not `width * height`.
    pub fn new(width: u32, height: u32, luma: Vec<u8>) -> Result<Self, CoreError> {
        if width == 0 || height == 0 {
            return Err(CoreError::InvalidThumbnail {
                reason: format!("dimensions must be non-zero, got {width}x{height}"),
            });
        }
        let expected = u64::from(width) * u64::from(height);
        if u64::try_from(luma.len()).unwrap_or(u64::MAX) != expected {
            return Err(CoreError::InvalidThumbnail {
                reason: format!(
                    "luma buffer has {} bytes, expected {expected} for {width}x{height}",
                    luma.len()
                ),
            });
        }
        Ok(Self {
            width,
            height,
            luma,
        })
    }

    fn has_consistent_buffer(&self) -> bool {
        let expected = u64::from(self.width) * u64::from(self.height);
        u64::try_from(self.luma.len()).unwrap_or(u64::MAX) == expected
    }
}

/// Side length of a comparison tile in thumbnail pixels.
const DEFAULT_TILE_SIZE: u32 = 10;
/// Mean absolute luma difference that marks a tile as changed.
const DEFAULT_TILE_THRESHOLD: u8 = 6;
/// Changed tile fraction that makes a frame worth keeping at all.
const DEFAULT_KEEP_RATIO: f32 = 0.005;
/// Changed tile fraction that marks a major change, kept at once.
const DEFAULT_MAJOR_RATIO: f32 = 0.08;
/// Top part of the image to ignore, as a fraction of its height.
const DEFAULT_IGNORE_TOP_FRACTION: f32 = 0.04;
/// Longest allowed gap between kept frames, in milliseconds.
const DEFAULT_MAX_GAP_MS: i64 = 300_000;
/// Shortest gap between keeps caused by a minor change, in milliseconds.
const DEFAULT_MINOR_GAP_MS: i64 = 20_000;
/// Gap between keeps while the screen shows continuous motion, in milliseconds.
const DEFAULT_MOTION_GAP_MS: i64 = 10_000;
/// Quick major keeps in a row that mark continuous motion.
const DEFAULT_MOTION_RUN_KEEPS: u8 = 3;

/// Thresholds and gaps that decide whether a frame is worth keeping.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct KeepPolicy {
    /// Side length of a comparison tile in pixels.
    pub tile_size: u32,
    /// Mean absolute luma difference that marks a tile as changed.
    pub tile_threshold: u8,
    /// Changed tile fraction that makes a frame worth keeping at all.
    pub keep_ratio: f32,
    /// Changed tile fraction that marks a major change, kept at once.
    pub major_ratio: f32,
    /// Top part of the image to ignore, as a fraction of its height.
    pub ignore_top_fraction: f32,
    /// Longest allowed gap between kept frames in milliseconds.
    pub max_gap_ms: i64,
    /// Shortest gap between keeps caused by a minor change, in milliseconds.
    ///
    /// Minor changes accumulate against the last kept thumbnail, so a long
    /// edit still crosses [`KeepPolicy::major_ratio`] and is kept at once.
    pub minor_gap_ms: i64,
    /// Gap that keeps major changes in one motion run, in milliseconds. A
    /// major change within this gap of the last major change, kept or
    /// throttled, counts toward the run.
    pub motion_gap_ms: i64,
    /// Quick major changes in a row that mark continuous motion. After these,
    /// continuous motion is kept at most once per [`KeepPolicy::motion_gap_ms`].
    /// `0` behaves like `1`.
    pub motion_run_keeps: u8,
}

impl Default for KeepPolicy {
    fn default() -> Self {
        Self {
            tile_size: DEFAULT_TILE_SIZE,
            tile_threshold: DEFAULT_TILE_THRESHOLD,
            keep_ratio: DEFAULT_KEEP_RATIO,
            major_ratio: DEFAULT_MAJOR_RATIO,
            ignore_top_fraction: DEFAULT_IGNORE_TOP_FRACTION,
            max_gap_ms: DEFAULT_MAX_GAP_MS,
            minor_gap_ms: DEFAULT_MINOR_GAP_MS,
            motion_gap_ms: DEFAULT_MOTION_GAP_MS,
            motion_run_keeps: DEFAULT_MOTION_RUN_KEEPS,
        }
    }
}

impl KeepPolicy {
    /// Fraction of compared tiles whose mean luma difference is above the
    /// threshold.
    ///
    /// Tiles are `tile_size` square. Partial tiles at the right and bottom edges
    /// use their real pixel count. The grid starts right below the top
    /// `ignore_top_fraction` of the image, so only the ignored band is skipped.
    /// Returns `1.0` when the thumbnails cannot be compared (different
    /// dimensions, zero `tile_size`, or a buffer that does not match its
    /// dimensions) and `0.0` when no tile is compared. Allocates nothing.
    #[allow(clippy::cast_precision_loss)] // tile counts stay far below 2^24
    pub fn change_ratio(&self, a: &Thumbnail, b: &Thumbnail) -> f32 {
        if a.width != b.width || a.height != b.height || self.tile_size == 0 {
            return 1.0;
        }
        if !a.has_consistent_buffer() || !b.has_consistent_buffer() {
            return 1.0;
        }
        let width = a.width;
        let height = a.height;
        if width == 0 || height == 0 {
            return 0.0;
        }
        let ignored_rows = ignored_rows(height, self.ignore_top_fraction);
        let width_index = as_index(width);
        let mut changed = 0_u32;
        let mut compared = 0_u32;
        let mut top = ignored_rows;
        while top < height {
            let bottom = top.saturating_add(self.tile_size).min(height);
            let mut left = 0_u32;
            while left < width {
                let right = left.saturating_add(self.tile_size).min(width);
                let pixels = u64::from(bottom - top) * u64::from(right - left);
                let mut difference_sum = 0_u64;
                for row in top..bottom {
                    let row_start = as_index(row) * width_index;
                    let start = row_start + as_index(left);
                    let end = row_start + as_index(right);
                    for (left_byte, right_byte) in
                        a.luma[start..end].iter().zip(&b.luma[start..end])
                    {
                        difference_sum += u64::from(left_byte.abs_diff(*right_byte));
                    }
                }
                compared += 1;
                if difference_sum > u64::from(self.tile_threshold) * pixels {
                    changed += 1;
                }
                left = right;
            }
            top = bottom;
        }
        if compared == 0 {
            return 0.0;
        }
        changed as f32 / compared as f32
    }

    /// Decides whether `next` should be kept, and returns the state to pass to
    /// the next decision.
    ///
    /// The reason follows this priority: first frame, focus change, maximum
    /// gap, major change, minor change, unchanged. A major change is kept at
    /// once unless continuous motion is under way. Motion is measured from the
    /// last major change seen, kept or throttled: each major within
    /// [`KeepPolicy::motion_gap_ms`] of the previous one continues the run, and
    /// after the first [`KeepPolicy::motion_run_keeps`] the frame is kept at
    /// most once per motion gap. Minor and unchanged frames carry the run
    /// forward instead of starting it over, so a quiet frame between two major
    /// changes does not defeat the throttle. A pause longer than the motion gap
    /// without a major change ends the run, and a focus change, the maximum gap,
    /// or a first frame clears it. A minor change is kept only once
    /// [`KeepPolicy::minor_gap_ms`] passed since the last kept frame. When a
    /// previous thumbnail exists the reported ratio is always the real tile
    /// ratio, even when focus or the maximum gap forced the keep.
    pub fn decide(
        &self,
        previous: Option<&Thumbnail>,
        next: &Thumbnail,
        ctx: &FrameContext,
        state: KeepState,
    ) -> KeepDecision {
        let Some(previous) = previous else {
            return KeepDecision::decided(1.0, KeepReason::FirstFrame, KeepState::default());
        };
        let change_ratio = self.change_ratio(previous, next);
        let Some(last_kept_ms) = ctx.last_kept_ms else {
            return KeepDecision::decided(
                change_ratio,
                KeepReason::FirstFrame,
                KeepState::default(),
            );
        };
        let since_last_kept_ms = ctx.now_ms.saturating_sub(last_kept_ms);
        if ctx.focus_changed {
            return KeepDecision::decided(
                change_ratio,
                KeepReason::FocusChanged,
                KeepState::default(),
            );
        }
        if since_last_kept_ms >= self.max_gap_ms {
            return KeepDecision::decided(change_ratio, KeepReason::MaxGap, KeepState::default());
        }
        if change_ratio >= self.major_ratio {
            let quick = state
                .last_major_ms
                .is_some_and(|at| ctx.now_ms.saturating_sub(at) <= self.motion_gap_ms);
            let major_run = if quick {
                state.major_run.saturating_add(1)
            } else {
                1
            };
            let next = KeepState {
                major_run,
                last_major_ms: Some(ctx.now_ms),
            };
            let in_motion = major_run > self.motion_run_keeps.max(1);
            if in_motion && since_last_kept_ms < self.motion_gap_ms {
                return KeepDecision {
                    keep: false,
                    change_ratio,
                    reason: KeepReason::MotionThrottled,
                    next_state: next,
                };
            }
            return KeepDecision::decided(change_ratio, KeepReason::MajorChanged, next);
        }
        if change_ratio >= self.keep_ratio {
            if since_last_kept_ms >= self.minor_gap_ms {
                return KeepDecision::decided(change_ratio, KeepReason::Changed, state);
            }
            return KeepDecision {
                keep: false,
                change_ratio,
                reason: KeepReason::MinorDeferred,
                next_state: state,
            };
        }
        KeepDecision {
            keep: false,
            change_ratio,
            reason: KeepReason::Unchanged,
            next_state: state,
        }
    }
}

/// The keep policy memory that travels between frames.
///
/// It counts major changes that follow one another within
/// [`KeepPolicy::motion_gap_ms`], so continuous motion can be told apart from a
/// single change of screen. Quiet frames carry it forward unchanged. The engine
/// stores it beside the last kept thumbnail and passes it back with the next
/// frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct KeepState {
    /// Major changes in a row, each within [`KeepPolicy::motion_gap_ms`] of the
    /// previous one, kept or not.
    major_run: u8,
    /// When the last major change was seen, kept or throttled.
    last_major_ms: Option<i64>,
}

/// Everything about the moment a frame arrived, apart from the image itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameContext {
    /// Capture time in Unix milliseconds.
    pub now_ms: i64,
    /// Capture time of the last kept frame, if there is one.
    pub last_kept_ms: Option<i64>,
    /// Whether the focused app or window changed since the last frame.
    pub focus_changed: bool,
}

/// The outcome of [`KeepPolicy::decide`].
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct KeepDecision {
    /// Whether the frame should be stored.
    pub keep: bool,
    /// Changed tile fraction against the previous thumbnail.
    pub change_ratio: f32,
    /// Why the decision came out this way.
    pub reason: KeepReason,
    /// The state to pass to the next decision, whether or not this frame was
    /// kept.
    pub next_state: KeepState,
}

impl KeepDecision {
    fn decided(change_ratio: f32, reason: KeepReason, next_state: KeepState) -> Self {
        Self {
            keep: true,
            change_ratio,
            reason,
            next_state,
        }
    }
}

/// Why a frame was kept or skipped.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum KeepReason {
    /// There was nothing to compare against.
    FirstFrame,
    /// The focused app or window changed.
    FocusChanged,
    /// The maximum gap since the last kept frame elapsed.
    MaxGap,
    /// A minor change was kept after the minor gap.
    Changed,
    /// The frame looks like the previous one.
    Unchanged,
    /// The change reached `major_ratio`, so the frame was kept at once.
    MajorChanged,
    /// A minor change arrived before the minor gap passed, so it was skipped.
    /// The comparison accumulates against the last kept thumbnail, so the
    /// change is kept once it grows or the gap elapses.
    MinorDeferred,
    /// Continuous motion is throttled to one keep per motion gap.
    MotionThrottled,
}

fn as_index(value: u32) -> usize {
    usize::try_from(value).unwrap_or(0)
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)] // range checked first
fn ignored_rows(height: u32, fraction: f32) -> u32 {
    if !fraction.is_finite() {
        return 0;
    }
    let clamped = f64::from(fraction.clamp(0.0, 1.0));
    let rows = clamped * f64::from(height);
    if rows <= 0.0 {
        0
    } else if rows >= f64::from(height) {
        height
    } else {
        rows.floor() as u32
    }
}

#[cfg(test)]
mod tests;
