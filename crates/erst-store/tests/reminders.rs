//! Reminder writes and due filtering.

mod common;

use common::{TestResult, begin_segment, open_store, simple_frame};
use erst_store::StoreError;

#[test]
fn due_reminders_skip_done_and_later_ones() -> TestResult {
    let (_dir, store) = open_store()?;
    let early = store.add_reminder(None, 900, 100, "early")?;
    let later = store.add_reminder(None, 900, 200, "later")?;
    let middle = store.add_reminder(None, 900, 150, "middle")?;

    let all = store.reminders()?;
    assert_eq!(
        all.iter().map(|reminder| reminder.id).collect::<Vec<_>>(),
        vec![early, middle, later]
    );
    assert!(all.iter().all(|reminder| reminder.done_at.is_none()));
    assert!(all.iter().all(|reminder| reminder.frame_id.is_none()));

    let due = store.due_reminders(150)?;
    assert_eq!(
        due.iter().map(|reminder| reminder.id).collect::<Vec<_>>(),
        vec![early, middle]
    );
    assert_eq!(due[0].note, "early");

    store.complete_reminder(early, 160)?;
    let due = store.due_reminders(1_000)?;
    assert_eq!(
        due.iter().map(|reminder| reminder.id).collect::<Vec<_>>(),
        vec![middle, later]
    );
    let completed = store
        .reminders()?
        .into_iter()
        .find(|reminder| reminder.id == early)
        .ok_or("completed reminder missing")?;
    assert_eq!(completed.done_at, Some(160));

    assert!(matches!(
        store.complete_reminder(9_999, 200),
        Err(StoreError::NotFound {
            what: "reminder",
            ..
        })
    ));
    Ok(())
}

#[test]
fn reminders_can_anchor_to_a_frame() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let frame_id = store.insert_frame(&simple_frame(segment_id, 1_000, &["remember this"]))?;
    let id = store.add_reminder(Some(frame_id), 1_100, 2_000, "come back")?;

    let reminder = store
        .reminders()?
        .into_iter()
        .find(|reminder| reminder.id == id)
        .ok_or("reminder missing")?;
    assert_eq!(reminder.frame_id, Some(frame_id));
    assert_eq!(reminder.created_at, 1_100);
    assert_eq!(reminder.due_at, 2_000);
    assert_eq!(reminder.note, "come back");
    assert_eq!(reminder.done_at, None);
    Ok(())
}
