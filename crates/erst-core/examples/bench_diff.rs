//! Times the frame keep decision on a 160x90 thumbnail.
//!
//! Run with `cargo run -p erst-core --release --example bench_diff`.
//! The budget for one call is 50 microseconds.

#![allow(clippy::print_stdout, clippy::cast_precision_loss)]

use std::hint::black_box;
use std::time::Instant;

use erst_core::{FrameContext, KeepPolicy, KeepState, Thumbnail};

const WIDTH: u32 = 160;
const HEIGHT: u32 = 90;
const CALLS: u32 = 100_000;
const BUDGET_NS_PER_CALL: f64 = 50_000.0;

fn main() {
    let previous = gradient();
    let mut next = previous.clone();
    for row in 20..50 {
        for column in 20..80 {
            let index = usize::try_from(row * WIDTH + column).unwrap_or(0);
            next.luma[index] = next.luma[index].wrapping_add(60);
        }
    }
    let policy = KeepPolicy::default();
    let ctx = FrameContext {
        now_ms: 300_000,
        last_kept_ms: Some(0),
        focus_changed: false,
    };

    for _ in 0..1_000 {
        let decision = policy.decide(
            Some(black_box(&previous)),
            black_box(&next),
            &ctx,
            KeepState::default(),
        );
        black_box(decision);
    }

    let mut kept = 0_u32;
    let started = Instant::now();
    for _ in 0..CALLS {
        let decision = policy.decide(
            Some(black_box(&previous)),
            black_box(&next),
            &ctx,
            KeepState::default(),
        );
        kept = kept.wrapping_add(u32::from(black_box(decision).keep));
    }
    let elapsed = started.elapsed();
    let ns_per_call = elapsed.as_secs_f64() * 1_000_000_000.0 / f64::from(CALLS);
    let verdict = if ns_per_call < BUDGET_NS_PER_CALL {
        "within budget"
    } else {
        "OVER BUDGET"
    };
    println!(
        "{CALLS} calls in {:.3} ms, {ns_per_call:.1} ns per call ({verdict}, budget {BUDGET_NS_PER_CALL:.0} ns, {kept} kept)",
        elapsed.as_secs_f64() * 1_000.0
    );
}

fn gradient() -> Thumbnail {
    let luma = (0..HEIGHT)
        .flat_map(|row| {
            (0..WIDTH).map(move |column| u8::try_from((column * 3 + row * 5) % 251).unwrap_or(0))
        })
        .collect();
    Thumbnail {
        width: WIDTH,
        height: HEIGHT,
        luma,
    }
}
