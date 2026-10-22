//! End to end behavior of the `Engine` facade on a temporary data directory.
//!
//! The flow follows one day of recording: keep decisions, segments, frames,
//! focus spans, search, timeline, moments, activity, storage, settings,
//! reminders, and retention.

#![allow(
    clippy::too_many_lines,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::assert_is_empty
)] // tests may unwrap and one test documents the whole flow

mod common;

use std::fs;

use common::{current_time_ms, open_engine, text_line, write_video};
use erst_core::{MS_PER_DAY, MS_PER_HOUR, MS_PER_MINUTE, local_day_containing};
use erst_ffi::{
    Engine, ErstError, FfiKeepReason, FfiNewFrame, FfiRetentionAction, FfiRetentionKind,
    FfiSettings, FfiThumbnail,
};

type TestResult = Result<(), Box<dyn std::error::Error>>;

const SAFARI: &str = "com.apple.Safari";
const XCODE: &str = "com.apple.dt.Xcode";
const TERMINAL: &str = "com.apple.Terminal";

fn thumbnail(fill: u8) -> FfiThumbnail {
    FfiThumbnail {
        width: 20,
        height: 10,
        luma: vec![fill; 200],
    }
}

#[test]
fn records_one_day_end_to_end() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    assert_eq!(engine.version(), env!("CARGO_PKG_VERSION"));

    // A frame is kept when it is the first, and an identical one is skipped.
    let first = engine.evaluate_frame(thumbnail(0), 1_000, false);
    assert!(first.keep);
    assert_eq!(first.reason, FfiKeepReason::FirstFrame);
    let identical = engine.evaluate_frame(thumbnail(0), 2_000, false);
    assert!(!identical.keep);
    assert_eq!(identical.reason, FfiKeepReason::Unchanged);
    assert_eq!(engine.storage()?.frame_count, 0);

    let now = current_time_ms();
    let midnight = local_day_containing(now, |_| 0).start_ms;
    let previous_day = midnight - MS_PER_DAY;
    let frame_base = previous_day + 10 * MS_PER_HOUR;

    // Segment one is old enough for the default retention policy to reduce it.
    let segment1_path = "segments/2026/10/05/100000-1.mp4";
    let segment1_file = write_video(&data_dir, segment1_path);
    let segment1_started = midnight - 10 * MS_PER_DAY;
    let segment1 =
        engine.begin_segment(segment1_path.to_owned(), segment1_started, 1_920, 1_080)?;

    let texts = [
        "First note",
        "Second note",
        "Información de privacidad",
        "Información",
        "Fifth note",
        "Sixth note",
        "Seventh note",
        "Eighth note",
    ];
    let mut frame_times = Vec::with_capacity(texts.len());
    let mut frame_ids = Vec::with_capacity(texts.len());
    for (index, text) in texts.iter().enumerate() {
        let captured_at_ms = frame_base + i64::try_from(index)? * MS_PER_MINUTE;
        let frame = FfiNewFrame {
            captured_at_ms,
            segment_id: segment1,
            pts_ms: captured_at_ms - segment1_started,
            bundle_id: SAFARI.to_owned(),
            app_name: "Safari".to_owned(),
            window_title: Some("Apple".to_owned()),
            url: Some("https://www.apple.com/es/".to_owned()),
            change_ratio: 0.5,
            lines: vec![text_line(text, 200)],
        };
        frame_times.push(captured_at_ms);
        frame_ids.push(engine.record_frame(frame)?);
    }
    engine.finish_segment(segment1, frame_base + 8 * MS_PER_MINUTE, 1_000_000)?;

    // A frame from today proves the menu bar summary sees today's heat.
    let segment2 =
        engine.begin_segment("segments/today-2.mp4".to_owned(), midnight, 1_920, 1_080)?;
    let today_frame = FfiNewFrame {
        captured_at_ms: now,
        segment_id: segment2,
        pts_ms: now.saturating_sub(midnight),
        bundle_id: SAFARI.to_owned(),
        app_name: "Safari".to_owned(),
        window_title: Some("Apple".to_owned()),
        url: None,
        change_ratio: 0.1,
        lines: vec![text_line("Menu bar summary", 100)],
    };
    engine.record_frame(today_frame)?;
    engine.finish_segment(segment2, now, 500_000)?;
    let segment3 = engine.begin_segment("segments/open-3.mp4".to_owned(), now, 1_920, 1_080)?;

    // Focus spans: two earlier visits, the one containing the moment, one
    // visit today, and three spans used by the activity report.
    let earlier_span = engine.begin_span(
        SAFARI.to_owned(),
        "Safari".to_owned(),
        Some("Apple".to_owned()),
        None,
        previous_day + 5 * MS_PER_HOUR,
    )?;
    engine.end_span(earlier_span, previous_day + 6 * MS_PER_HOUR)?;

    let containing_span = engine.begin_span(
        SAFARI.to_owned(),
        "Safari".to_owned(),
        Some("Apple".to_owned()),
        Some("https://www.apple.com/es/".to_owned()),
        previous_day + 9 * MS_PER_HOUR,
    )?;
    engine.end_span(containing_span, previous_day + 11 * MS_PER_HOUR)?;

    let today_visit = engine.begin_span(
        SAFARI.to_owned(),
        "Safari".to_owned(),
        Some("Apple".to_owned()),
        None,
        midnight,
    )?;
    engine.end_span(today_visit, midnight + 5 * MS_PER_MINUTE)?;

    let reading = engine.begin_span(
        SAFARI.to_owned(),
        "Safari".to_owned(),
        Some("Activity".to_owned()),
        Some("https://www.example.com/article".to_owned()),
        previous_day + 15 * MS_PER_HOUR,
    )?;
    engine.end_span(reading, previous_day + 16 * MS_PER_HOUR)?;

    let building = engine.begin_span(
        XCODE.to_owned(),
        "Xcode".to_owned(),
        Some("Editor".to_owned()),
        None,
        previous_day + 16 * MS_PER_HOUR,
    )?;
    engine.end_span(
        building,
        previous_day + 16 * MS_PER_HOUR + 30 * MS_PER_MINUTE,
    )?;

    // Left open on purpose: activity closes it at the current time.
    let open_span = engine.begin_span(
        TERMINAL.to_owned(),
        "Terminal".to_owned(),
        Some("Shell".to_owned()),
        None,
        previous_day + 16 * MS_PER_HOUR + 50 * MS_PER_MINUTE,
    )?;
    assert!(open_span > 0);

    let previous_span = engine.begin_span(
        SAFARI.to_owned(),
        "Safari".to_owned(),
        Some("Previous".to_owned()),
        None,
        previous_day + 14 * MS_PER_HOUR,
    )?;
    engine.end_span(
        previous_span,
        previous_day + 14 * MS_PER_HOUR + 30 * MS_PER_MINUTE,
    )?;

    // Search matches accents and app filters, and groups the two frames into
    // one moment with the newer frame as representative.
    let hits = engine.search("informacion".to_owned(), 10, "UTC".to_owned())?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].frame_id, frame_ids[3]);
    assert_eq!(hits[0].first_seen_ms, frame_times[2]);
    assert_eq!(hits[0].last_seen_ms, frame_times[3]);
    assert_eq!(hits[0].bundle_id, SAFARI);
    assert_eq!(hits[0].app_name, "Safari");
    assert_eq!(hits[0].matched_lines.len(), 1);
    assert_eq!(hits[0].matched_lines[0].text, "Información");
    assert_eq!(
        hits[0].segment_path.as_deref(),
        Some(segment1_file.to_string_lossy().as_ref())
    );
    assert_eq!(
        engine
            .search("app:Safari informacion".to_owned(), 10, "UTC".to_owned())?
            .len(),
        1
    );
    assert!(
        engine
            .search("app:Chrome informacion".to_owned(), 10, "UTC".to_owned())?
            .is_empty()
    );
    assert!(
        engine
            .search("app:Safari".to_owned(), 10, "UTC".to_owned())?
            .is_empty()
    );
    assert!(
        engine
            .search(String::new(), 10, "UTC".to_owned())?
            .is_empty()
    );

    // Timeline heat, spans, and stamps for the frames around the moment.
    let timeline = engine.timeline(
        frame_base - 5 * MS_PER_MINUTE,
        frame_base + 15 * MS_PER_MINUTE,
        20,
    )?;
    assert_eq!(timeline.heat.len(), 20);
    assert!(timeline.heat.iter().any(|level| *level > 0));
    assert_eq!(timeline.stamps.len(), frame_ids.len());
    assert_eq!(timeline.spans.len(), 1);
    assert_eq!(timeline.spans[0].id, containing_span);
    assert_eq!(
        timeline.spans[0].started_at_ms,
        previous_day + 9 * MS_PER_HOUR
    );
    assert_eq!(
        timeline.spans[0].ended_at_ms,
        Some(previous_day + 11 * MS_PER_HOUR)
    );

    let nearest = engine.nearest_moment(frame_times[3] + 30_000)?;
    assert_eq!(nearest.map(|stamp| stamp.id), Some(frame_ids[3]));

    // The moment: on screen range, today's visits, last opened before today,
    // and three neighbors on each side.
    let moment = engine.moment(frame_ids[3], "UTC".to_owned())?;
    assert_eq!(moment.stamp.id, frame_ids[3]);
    assert_eq!(moment.stamp.captured_at_ms, frame_times[3]);
    assert_eq!(moment.bundle_id, SAFARI);
    assert_eq!(moment.app_name, "Safari");
    assert_eq!(moment.window_title.as_deref(), Some("Apple"));
    assert_eq!(moment.segment_started_at_ms, segment1_started);
    assert_eq!(moment.pts_ms, frame_times[3] - segment1_started);
    assert_eq!(moment.tier, 0);
    assert_eq!(moment.lines.len(), 1);
    assert_eq!(moment.lines[0].text, "Información");
    assert_eq!(
        moment.segment_path.as_deref(),
        Some(segment1_file.to_string_lossy().as_ref())
    );
    assert_eq!(
        moment.on_screen_from_ms,
        Some(previous_day + 9 * MS_PER_HOUR)
    );
    assert_eq!(
        moment.on_screen_to_ms,
        Some(previous_day + 11 * MS_PER_HOUR)
    );
    assert_eq!(moment.visits_today, 1);
    assert_eq!(moment.last_opened_ms, Some(previous_day + 11 * MS_PER_HOUR));
    let neighbor_ids: Vec<i64> = moment.neighbors.iter().map(|stamp| stamp.id).collect();
    assert_eq!(
        neighbor_ids,
        vec![
            frame_ids[0],
            frame_ids[1],
            frame_ids[2],
            frame_ids[4],
            frame_ids[5],
            frame_ids[6],
        ]
    );

    // Activity totals, categories, hours, apps, websites, and the previous term.
    let activity = engine.activity(
        previous_day + 15 * MS_PER_HOUR,
        previous_day + 17 * MS_PER_HOUR,
        "UTC".to_owned(),
    )?;
    assert_eq!(activity.total_ms, 100 * MS_PER_MINUTE);
    assert_eq!(activity.previous_total_ms, Some(30 * MS_PER_MINUTE));
    assert_eq!(activity.categories.len(), 4);
    let category_ms = |category: erst_ffi::FfiCategory| {
        activity
            .categories
            .iter()
            .find(|total| total.category == category)
            .map(|total| total.ms)
            .unwrap_or(0)
    };
    assert_eq!(
        category_ms(erst_ffi::FfiCategory::Reading),
        60 * MS_PER_MINUTE
    );
    assert_eq!(
        category_ms(erst_ffi::FfiCategory::Building),
        40 * MS_PER_MINUTE
    );
    assert_eq!(category_ms(erst_ffi::FfiCategory::Talking), 0);
    assert_eq!(activity.buckets.len(), 2);
    assert_eq!(activity.buckets[0].reading_ms, 60 * MS_PER_MINUTE);
    assert_eq!(activity.buckets[1].building_ms, 40 * MS_PER_MINUTE);
    assert_eq!(activity.apps.len(), 3);
    let app_ms = |bundle_id: &str| {
        activity
            .apps
            .iter()
            .find(|app| app.bundle_id == bundle_id)
            .map(|app| app.ms)
            .unwrap_or(0)
    };
    assert_eq!(app_ms(SAFARI), 60 * MS_PER_MINUTE);
    assert_eq!(app_ms(XCODE), 30 * MS_PER_MINUTE);
    assert_eq!(app_ms(TERMINAL), 10 * MS_PER_MINUTE);
    assert_eq!(
        activity
            .apps
            .iter()
            .find(|app| app.bundle_id == XCODE)
            .map(|app| app.app_name.as_str()),
        Some("Xcode")
    );
    assert_eq!(activity.websites.len(), 1);
    assert_eq!(activity.websites[0].host, "example.com");
    assert_eq!(activity.websites[0].ms, 60 * MS_PER_MINUTE);

    // The activity report saw the span while it was open; closing it at the end
    // of the report keeps it out of today's summary.
    engine.end_span(open_span, previous_day + 17 * MS_PER_HOUR)?;

    // Storage facts, including the limit read from settings.
    let storage = engine.storage()?;
    assert_eq!(storage.video_bytes, 1_500_000);
    assert_eq!(storage.frame_count, 9);
    assert_eq!(storage.segment_count, 3);
    // Eight distinct frame lines plus the shared window title.
    assert_eq!(storage.unique_line_count, 10);
    assert_eq!(storage.oldest_ms, Some(frame_times[0]));
    assert_eq!(storage.newest_ms, Some(now));
    assert_eq!(storage.kept_last_24h_bytes, 500_000);
    assert_eq!(
        storage.used_bytes,
        storage.video_bytes + storage.database_bytes
    );
    assert_eq!(storage.average_per_day_bytes, storage.used_bytes);
    assert_eq!(storage.limit_bytes, Some(20_000_000_000));

    // Today so far: the visit span recorded today and the today frame.
    let today = engine.today_summary(now, "UTC".to_owned(), 24)?;
    let expected_on_screen = (midnight + 5 * MS_PER_MINUTE).min(now) - midnight;
    assert_eq!(today.on_screen_ms, expected_on_screen);
    assert_eq!(today.kept_bytes, 500_000);
    assert_eq!(today.heat.len(), 24);
    assert!(today.heat.iter().any(|level| *level > 0));
    if expected_on_screen > 0 {
        assert_eq!(today.top_apps.len(), 1);
        assert_eq!(today.top_apps[0].bundle_id, SAFARI);
        assert_eq!(today.top_apps[0].app_name, "Safari");
        assert_eq!(today.top_apps[0].ms, expected_on_screen);
    }

    // Settings start from the defaults the app ships with; the settings
    // document itself is covered by the dedicated settings tests.
    assert_eq!(engine.settings()?, FfiSettings::default());

    // Reminders become due at their time and disappear once completed.
    let due_at = now + MS_PER_MINUTE;
    let reminder = engine.add_reminder(Some(frame_ids[3]), due_at, "Check the price".to_owned())?;
    assert!(engine.due_reminders(now)?.is_empty());
    let due = engine.due_reminders(due_at)?;
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].id, reminder);
    assert_eq!(due[0].frame_id, Some(frame_ids[3]));
    assert_eq!(due[0].due_at_ms, due_at);
    assert_eq!(due[0].note, "Check the price");
    assert_eq!(due[0].done_at_ms, None);
    engine.complete_reminder(reminder, due_at + MS_PER_MINUTE)?;
    assert!(engine.due_reminders(due_at + 2 * MS_PER_MINUTE)?.is_empty());

    // Retention: the default policy reduces the ten day old segment and never
    // touches the open one.
    let plan = engine.retention_plan(now)?;
    assert_eq!(plan.len(), 1);
    assert_eq!(plan[0].segment_id, segment1);
    assert_eq!(plan[0].kind, FfiRetentionKind::Reduce);
    assert_eq!(
        plan[0].segment_path.as_deref(),
        Some(segment1_file.to_string_lossy().as_ref())
    );
    assert!(plan.iter().all(|action| action.segment_id != segment3));

    engine.apply_retention(plan[0].clone(), Some(350_000))?;
    assert!(segment1_file.exists());
    assert_eq!(engine.storage()?.video_bytes, 850_000);

    let mut deleting = engine.settings()?;
    deleting.full_quality_days = 0;
    deleting.lighter_copy_months = Some(0);
    engine.update_settings(deleting)?;

    let plan = engine.retention_plan(now)?;
    assert_eq!(plan.len(), 1);
    assert_eq!(plan[0].segment_id, segment1);
    assert_eq!(plan[0].kind, FfiRetentionKind::DeleteVideo);
    engine.apply_retention(plan[0].clone(), None)?;
    assert!(!segment1_file.exists());
    assert_eq!(engine.storage()?.video_bytes, 500_000);
    assert!(engine.retention_plan(now)?.is_empty());

    // Failures come back as typed errors, never as panics.
    assert!(matches!(
        engine.moment(999_999, "UTC".to_owned()),
        Err(ErstError::NotFound { .. })
    ));
    assert!(matches!(
        engine.activity(10, 5, "UTC".to_owned()),
        Err(ErstError::InvalidInput { .. })
    ));
    assert!(matches!(
        engine.timeline(10, 5, 10),
        Err(ErstError::InvalidInput { .. })
    ));
    let reduce_without_size = FfiRetentionAction {
        segment_id: segment1,
        kind: FfiRetentionKind::Reduce,
        segment_path: None,
    };
    assert!(matches!(
        engine.apply_retention(reduce_without_size, None),
        Err(ErstError::InvalidInput { .. })
    ));
    let invalid = engine.evaluate_frame(
        FfiThumbnail {
            width: 2,
            height: 2,
            luma: vec![0; 3],
        },
        now,
        false,
    );
    assert!(!invalid.keep);
    assert_eq!(invalid.reason, FfiKeepReason::InvalidThumbnail);

    Ok(())
}

#[test]
fn open_rejects_an_empty_or_file_data_directory() -> TestResult {
    assert!(matches!(
        Engine::open(String::new()),
        Err(ErstError::InvalidInput { .. })
    ));

    let temp = tempfile::tempdir()?;
    let file_path = temp.path().join("not-a-directory");
    fs::write(&file_path, b"occupied")?;
    assert!(matches!(
        Engine::open(file_path.to_string_lossy().into_owned()),
        Err(ErstError::InvalidInput { .. })
    ));
    Ok(())
}

#[test]
fn empty_engine_answers_reads_without_panicking() -> TestResult {
    let (_temp, data_dir, engine) = open_engine();
    assert!(data_dir.join("segments").is_dir());
    assert!(data_dir.join("erst.sqlite").is_file());

    let timeline = engine.timeline(0, MS_PER_HOUR, 6)?;
    assert_eq!(timeline.heat.len(), 6);
    assert_eq!(timeline.heat, vec![0; 6]);
    assert!(timeline.spans.is_empty());
    assert!(timeline.stamps.is_empty());
    assert_eq!(engine.nearest_moment(1_000)?, None);

    let activity = engine.activity(0, MS_PER_HOUR, "UTC".to_owned())?;
    assert_eq!(activity.total_ms, 0);
    assert_eq!(activity.previous_total_ms, None);
    assert_eq!(activity.categories.len(), 4);
    assert_eq!(activity.buckets.len(), 1);
    assert!(activity.apps.is_empty());
    assert!(activity.websites.is_empty());

    let storage = engine.storage()?;
    assert_eq!(storage.used_bytes, storage.database_bytes);
    assert_eq!(storage.video_bytes, 0);
    assert_eq!(storage.frame_count, 0);
    assert_eq!(storage.segment_count, 0);
    assert_eq!(storage.unique_line_count, 0);
    assert_eq!(storage.oldest_ms, None);
    assert_eq!(storage.newest_ms, None);
    assert_eq!(storage.average_per_day_bytes, 0);
    assert_eq!(storage.kept_last_24h_bytes, 0);
    assert_eq!(storage.limit_bytes, Some(20_000_000_000));

    let now = current_time_ms();
    let today = engine.today_summary(now, "UTC".to_owned(), 12)?;
    assert_eq!(today.on_screen_ms, 0);
    assert_eq!(today.kept_bytes, 0);
    assert_eq!(today.heat, vec![0; 12]);
    assert!(today.top_apps.is_empty());

    assert!(engine.due_reminders(now)?.is_empty());
    assert!(engine.retention_plan(now)?.is_empty());
    assert!(
        engine
            .search("anything".to_owned(), 10, "UTC".to_owned())?
            .is_empty()
    );
    assert!(
        engine
            .search("app:Safari".to_owned(), 10, "UTC".to_owned())?
            .is_empty()
    );
    assert_eq!(engine.settings()?, FfiSettings::default());
    Ok(())
}
