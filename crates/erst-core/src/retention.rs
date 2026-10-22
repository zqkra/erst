//! Storage retention planning: when to reduce and when to delete video.

/// Share of the original bytes that a reduced segment keeps.
pub const REDUCED_SIZE_FACTOR: f64 = 0.35;

/// Quality level currently stored for a segment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Tier {
    /// Original video is kept.
    Full,
    /// Video was re-encoded at a lower quality.
    Reduced,
    /// Only text and metadata remain.
    TextOnly,
}

/// What the user chose for a segment once its lighter copy period ends.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AfterLighterCopy {
    /// Delete the video and keep the text and metadata.
    KeepText,
    /// Delete the segment with its frames and text.
    DeleteEverything,
}

/// One stored segment as retention sees it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SegmentInfo {
    /// Database identifier.
    pub id: i64,
    /// Start time in Unix milliseconds.
    pub started_at: i64,
    /// Size on disk in bytes.
    pub bytes: u64,
    /// Current quality tier.
    pub tier: Tier,
}

/// Limits that drive retention.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RetentionPolicy {
    /// How long original video is kept, in milliseconds.
    pub full_quality_ms: i64,
    /// Extra time a reduced video is kept before its video is deleted.
    pub reduced_ms: Option<i64>,
    /// Optional total storage budget in bytes.
    pub budget_bytes: Option<u64>,
    /// What happens to a segment after its lighter copy period.
    pub after_lighter_copy: AfterLighterCopy,
}

/// A single thing to do to a segment.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RetentionAction {
    /// Segment the action applies to.
    pub segment_id: i64,
    /// What to do with it.
    pub action: RetentionKind,
}

/// The kind of retention work to perform.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum RetentionKind {
    /// Re-encode the video at a lower quality.
    Reduce,
    /// Delete the video, keeping text and metadata.
    DeleteVideo,
    /// Delete the video and every frame of the segment, text included.
    DeleteSegment,
}

/// Plans retention actions for `segments` at `now_ms`.
///
/// The newest segment (the one with the greatest `started_at`) is never
/// touched, because it may still be open, and neither is any segment tied with
/// it. Older segments are reduced after `full_quality_ms`. After
/// `full_quality_ms + reduced_ms` they lose their video, or the whole segment
/// when the policy says to delete everything. Text only segments only get an
/// action in that last case. When a budget is set, the oldest remaining videos
/// are deleted, keeping their text, until the estimated size fits. Actions are
/// sorted oldest first and there is at most one per segment.
pub fn plan(
    policy: &RetentionPolicy,
    segments: &[SegmentInfo],
    now_ms: i64,
) -> Vec<RetentionAction> {
    if segments.is_empty() {
        return Vec::new();
    }
    let newest_started = segments
        .iter()
        .map(|segment| segment.started_at)
        .max()
        .unwrap_or(i64::MIN);
    let delete_after = policy
        .reduced_ms
        .map(|reduced_ms| policy.full_quality_ms.saturating_add(reduced_ms));
    let mut actions: Vec<Option<RetentionKind>> = vec![None; segments.len()];
    for (index, segment) in segments.iter().enumerate() {
        if segment.started_at == newest_started {
            continue;
        }
        let age = now_ms.saturating_sub(segment.started_at);
        if delete_after.is_some_and(|limit| age > limit) {
            actions[index] = aging_kind(policy.after_lighter_copy, segment.tier);
            continue;
        }
        if segment.tier == Tier::Full && age > policy.full_quality_ms {
            actions[index] = Some(RetentionKind::Reduce);
        }
    }
    if let Some(budget) = policy.budget_bytes {
        apply_budget(budget, segments, newest_started, &mut actions);
    }
    let mut planned: Vec<(i64, i64, RetentionKind)> = segments
        .iter()
        .enumerate()
        .filter_map(|(index, segment)| {
            actions[index].map(|action| (segment.started_at, segment.id, action))
        })
        .collect();
    planned.sort_by_key(|(started_at, id, _)| (*started_at, *id));
    planned
        .into_iter()
        .map(|(_, segment_id, action)| RetentionAction { segment_id, action })
        .collect()
}

/// The action that ends a segment's lighter copy period, or `None` when the
/// user keeps the text of a segment whose video is already gone.
fn aging_kind(after: AfterLighterCopy, tier: Tier) -> Option<RetentionKind> {
    match (after, tier) {
        (AfterLighterCopy::DeleteEverything, _) => Some(RetentionKind::DeleteSegment),
        (AfterLighterCopy::KeepText, Tier::TextOnly) => None,
        (AfterLighterCopy::KeepText, Tier::Full | Tier::Reduced) => {
            Some(RetentionKind::DeleteVideo)
        }
    }
}

fn apply_budget(
    budget: u64,
    segments: &[SegmentInfo],
    newest_started: i64,
    actions: &mut [Option<RetentionKind>],
) {
    let mut estimated = segments
        .iter()
        .zip(actions.iter())
        .fold(0_u64, |total, (segment, action)| {
            total.saturating_add(retained_bytes(segment, *action))
        });
    while estimated > budget {
        let Some(index) = oldest_with_video(segments, newest_started, actions) else {
            break;
        };
        let before = retained_bytes(&segments[index], actions[index]);
        actions[index] = Some(RetentionKind::DeleteVideo);
        estimated = estimated.saturating_sub(before);
    }
}

fn oldest_with_video(
    segments: &[SegmentInfo],
    newest_started: i64,
    actions: &[Option<RetentionKind>],
) -> Option<usize> {
    segments
        .iter()
        .enumerate()
        .filter(|(index, segment)| {
            keeps_video(actions[*index])
                && segment.tier != Tier::TextOnly
                && segment.started_at != newest_started
        })
        .min_by_key(|(index, segment)| (segment.started_at, segment.id, *index))
        .map(|(index, _)| index)
}

/// Whether the planned action leaves the segment's video on disk.
fn keeps_video(action: Option<RetentionKind>) -> bool {
    matches!(action, None | Some(RetentionKind::Reduce))
}

fn retained_bytes(segment: &SegmentInfo, action: Option<RetentionKind>) -> u64 {
    match action {
        Some(RetentionKind::DeleteVideo | RetentionKind::DeleteSegment) => 0,
        Some(RetentionKind::Reduce) => reduced_bytes(segment.bytes),
        None => match segment.tier {
            Tier::TextOnly => 0,
            Tier::Full | Tier::Reduced => segment.bytes,
        },
    }
}

#[allow(
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss
)] // sizes stay below 2^53
fn reduced_bytes(bytes: u64) -> u64 {
    (bytes as f64 * REDUCED_SIZE_FACTOR) as u64
}

#[cfg(test)]
mod tests;
