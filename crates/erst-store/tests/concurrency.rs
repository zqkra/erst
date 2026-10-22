//! Concurrent writer and reader access through one Store.

mod common;

use std::sync::Arc;

use common::{TestResult, begin_segment, open_store, simple_frame};

#[test]
fn writer_and_reader_share_the_store_without_deadlock() -> TestResult {
    let (_dir, store) = open_store()?;
    let segment_id = begin_segment(&store)?;
    let store = Arc::new(store);

    std::thread::scope(|scope| -> TestResult {
        let writer_store = Arc::clone(&store);
        let writer = scope.spawn(move || -> TestResult {
            for index in 0..100_i64 {
                let frame = simple_frame(segment_id, 1_000 + index, &["concurrent needle"]);
                writer_store.insert_frame(&frame)?;
            }
            Ok(())
        });

        let first_reader_store = Arc::clone(&store);
        let first_reader = scope.spawn(move || -> TestResult {
            for _ in 0..100 {
                let frames = first_reader_store.frames_in_range(0, i64::MAX)?;
                assert!(frames.len() <= 100);
                first_reader_store.storage_stats(0)?;
            }
            Ok(())
        });

        let second_reader_store = Arc::clone(&store);
        let second_reader = scope.spawn(move || -> TestResult {
            for _ in 0..100 {
                let segments = second_reader_store.segments()?;
                assert!(!segments.is_empty(), "segment row missing");
            }
            Ok(())
        });

        writer
            .join()
            .map_err(|_| std::io::Error::other("writer panicked"))??;
        first_reader
            .join()
            .map_err(|_| std::io::Error::other("first reader panicked"))??;
        second_reader
            .join()
            .map_err(|_| std::io::Error::other("second reader panicked"))??;
        Ok(())
    })?;

    assert_eq!(store.storage_stats(0)?.frame_count, 100);
    Ok(())
}
