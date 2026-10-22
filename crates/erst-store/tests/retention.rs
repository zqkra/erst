//! Retention mutations, segments, and storage totals.

mod common;

use common::{TestResult, begin_segment, open_store, simple_frame};
use erst_store::StoreError;

#[test]
fn retention_reduces_and_deletes_video_without_losing_segment_rows() -> TestResult {
    let (_dir, store) = open_store()?;
    let now = 1_000_000_000_i64;

    let old = store.begin_segment("segments/old.mp4", now - 200_000_000, 1920, 1080)?;
    store.finish_segment(old, now - 199_999_000, 1_000)?;
    let recent = store.begin_segment("segments/recent.mp4", now - 1_000, 1920, 1080)?;
    store.finish_segment(recent, now, 200)?;
    let boundary = store.begin_segment("segments/boundary.mp4", now - 86_400_000, 1920, 1080)?;
    store.finish_segment(boundary, now, 400)?;
    let spare = begin_segment(&store)?;
    store.insert_frame(&simple_frame(spare, now - 10_000, &["older line"]))?;
    store.insert_frame(&simple_frame(spare, now - 5_000, &["newer line"]))?;

    store.mark_segment_reduced(old, 300)?;
    let reduced = store.segments()?;
    let old_row = reduced.iter().find(|segment| segment.id == old);
    let old_row = old_row.ok_or("old segment missing")?;
    assert_eq!(old_row.bytes, 300);
    assert_eq!(old_row.tier, 1);

    assert_eq!(
        store.delete_segment_video(old)?,
        Some("segments/old.mp4".to_owned())
    );
    assert_eq!(store.delete_segment_video(old)?, None);
    let deleted = store.segments()?;
    let old_row = deleted
        .iter()
        .find(|segment| segment.id == old)
        .ok_or("deleted segment missing")?;
    assert_eq!(old_row.path, None);
    assert_eq!(old_row.bytes, 0);
    assert_eq!(old_row.tier, 2);

    // A stale Reduce after the video is gone must not revive its bytes.
    store.mark_segment_reduced(old, 1_750)?;
    let stale = store.segments()?;
    let old_row = stale
        .iter()
        .find(|segment| segment.id == old)
        .ok_or("deleted segment missing")?;
    assert_eq!(old_row.path, None);
    assert_eq!(old_row.bytes, 0);
    assert_eq!(old_row.tier, 2);

    let stats = store.storage_stats(now)?;
    assert_eq!(stats.segment_count, 4);
    assert_eq!(stats.frame_count, 2);
    // One line per frame plus their shared window title.
    assert_eq!(stats.unique_line_count, 3);
    assert_eq!(stats.video_bytes, 200 + 400);
    assert_eq!(stats.video_bytes_last_24h, 200 + 400);
    assert_eq!(stats.oldest_ms, Some(now - 10_000));
    assert_eq!(stats.newest_ms, Some(now - 5_000));
    assert!(stats.database_bytes > 0);

    assert!(matches!(
        store.mark_segment_reduced(9_999, 1),
        Err(StoreError::NotFound {
            what: "segment",
            ..
        })
    ));
    assert!(matches!(
        store.delete_segment_video(9_999),
        Err(StoreError::NotFound {
            what: "segment",
            ..
        })
    ));
    Ok(())
}

#[test]
fn retention_deletes_queue_the_video_for_a_later_unlink() -> TestResult {
    let (_dir, store) = open_store()?;
    let reduced = store.begin_segment("segments/reduced.mp4", 0, 1920, 1080)?;
    store.finish_segment(reduced, 1_000, 5_000)?;
    let removed = store.begin_segment("segments/removed.mp4", 0, 1920, 1080)?;
    store.finish_segment(removed, 1_000, 5_000)?;

    store.delete_segment_video(reduced)?;
    store.delete_segment(removed)?;

    assert_eq!(
        store.pending_unlinks()?,
        vec![
            "segments/reduced.mp4".to_owned(),
            "segments/removed.mp4".to_owned()
        ]
    );
    Ok(())
}
