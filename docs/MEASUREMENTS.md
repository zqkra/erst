# Measurements

## Before: run

- Date: 2026-10-20 23:49 to 2026-10-21 00:19 local, 30.0 minutes.
- Machine: Apple M4, macOS 27.0.1 (26A434).
- Display: 2560 x 1440 at 144 Hz.
- Capture: 2560 x 1440 BGRA, HEVC quality 0.45 ("smaller").
- Workload: the owner used the Mac normally (browser, chat, video).

## Configuration

`ErstProbe --production` builds its recorder the way the app does from `ErstSettings.default`, mirroring `FfiConversions.configuration(_:)` in `app/Sources/ErstKit/Live/FfiConversions.swift`.

| Setting | Value | Source |
|---|---|---|
| Capture interval | 2 s | `ErstSettings.default` |
| Segment duration | 300 s | `RecorderConfiguration` default |
| Compression | smaller, HEVC quality 0.45 | `ErstSettings.default` |
| Idle threshold | 120 s | `RecorderConfiguration` default |
| Excluded apps | 1Password | `ErstSettings.default` |

Deviation: the idle gate was disabled (31,536,000 s) for this run. On this macOS build `CGEventSource.secondsSinceLastEventType(.combinedSessionState, .null)` returned 36,476 s at start instead of the time since the last input, so `FocusTracker` marked the owner idle and the recorder kept no frames. The probe raised only the idle threshold through `Recorder.apply`; capture, segments, compression, OCR, and exclusions stayed at production values.

## Before: numbers

| Metric | Value |
|---|---|
| Wall time | 1800.2 s (30.0 min) |
| Frames seen | 899 |
| Frames kept | 640 |
| Stored frames | 640 |
| OCR coverage | 640 of 640 kept frames with text (100%) |
| OCR jobs | 640, 138.5 ms average |
| OCR warm-up | 106 ms |
| Segments | 6 |
| Video bytes | 2,253,034 (2.3 MB) |
| Database bytes (`erst.sqlite` plus `-wal`) | 5,915,448 (5.9 MB; 1.6 MB plus 4.4 MB WAL) |
| Total bytes | 8,168,482 (8.2 MB) |
| Average CPU | 7.00% of one core (126.1 s CPU) |
| Static-screen CPU | 1.97% of one core over 285.2 s |
| Peak resident memory | 181.6 MB |
| Median resident memory | 108.7 MB |
| Bytes per hour of capture | 16.3 MB |
| 8-hour day, direct linear | 130.7 MB |
| 8-hour day, steady state | about 65 MB |
| `evaluate_frame` | p50 0.105 ms, p95 0.141 ms, max 0.239 ms (899 calls) |
| `record_frame` | p50 0.543 ms, p95 1.251 ms, max 4.033 ms (640 calls) |
| Thumbnail | 19.97 ms average (899 frames) |
| Lines per frame | 43.7 average, 9 to 109 |
| Unique text lines | 2,323 |
| Frame lines | 27,994 |
| Spans | 2 |

Static-screen CPU uses the 275 one-second samples in which capture delivered a frame and none was kept (285.2 s). It is an upper bound: OCR from the last kept frame can run during the next sample. Thumbnail and evaluate work alone account for about 1.0% of one core.

Search: three words from the recorded text were searched with the bundled `erst` CLI. Each returned moments over the 2,323 unique lines. The CLI took 11.2 ms p50 and 26.1 ms max per search over 20 runs, including process start.

## Keep policy tuning

The old policy kept a frame whenever 0.5% of the tiles changed. A frame is now kept at once when the change reaches `major_ratio`, while a change between `keep_ratio` and `major_ratio` waits for `minor_gap_ms`, and continuous motion is throttled to one keep per `motion_gap_ms`.

`ErstProbe --trace <file>` writes every captured thumbnail so the thresholds can be tuned without another long run. The file is one header and one fixed-size record per captured frame, all integers little endian:

```text
header: "ERSTTRE1" (8 bytes), width (u32), height (u32)
record: captured_at_ms (i64), focus_changed (u8, 0 or 1), luma (width * height bytes)
```

The probe writes the header once and appends one record per captured thumbnail before the keep decision. `cargo run --release -p erst-core --example replay_keep -- <trace>` replays the trace through the old policy and through candidate threshold sets. It reports kept frames, keep rate, the longest gap between keeps, the reasons, and how late a candidate records each frame the old policy kept.

The tuning trace is 20.0 minutes of the owner's normal use (browser, chat, video): 572 frames, 20 focus changes, 54 stable page changes. A stable page change is a frame that differs from the previous one by at least 8% of the tiles while the next frame settles, so continuous motion is not counted. OCR was failing intermittently during this run because of another change in progress; that does not affect the thumbnails or the keep decision.

| Policy | major ratio | minor gap | motion gap | Kept | Keep rate | Longest gap | Page changes within the minor gap | Worst page change |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Old policy (`keep_ratio 0.005`) | none | 0 s | none | 516 of 572 | 90.2% | 29.5 s | n/a | n/a |
| start, chosen default | 0.08 | 20 s | 10 s | 168 of 572 | 29.4% | 29.5 s | 54 of 54 | 8.0 s |
| fast-motion | 0.08 | 20 s | 5 s | 227 of 572 | 39.7% | 29.5 s | 54 of 54 | 4.0 s |
| slow-motion | 0.08 | 20 s | 20 s | 126 of 572 | 22.0% | 29.5 s | 54 of 54 | 18.0 s |
| calm | 0.08 | 30 s | 15 s | 136 of 572 | 23.8% | 29.5 s | 54 of 54 | 20.0 s |
| steady | 0.10 | 25 s | 12 s | 162 of 572 | 28.3% | 29.5 s | 54 of 54 | 10.0 s |
| tight | 0.06 | 15 s | 10 s | 170 of 572 | 29.7% | 29.5 s | 54 of 54 | 8.0 s |

Every candidate keeps all 20 app switches (19 `FocusChanged` plus the first frame) because focus always passes. The start thresholds were chosen as the defaults: they keep every app switch and every stable page change, record the worst page change 8 s late, and keep 67% fewer frames than the old policy (168 against 516). The motion gap moves the count most on this trace. Halving it (fast-motion) keeps 35% more frames; doubling it (slow-motion) saves 7 percentage points but makes a page change 18 s late. The major ratio between 0.06 and 0.10 changes the count by two frames, because a motion-heavy trace produces mostly major changes.

### Keep policy fix

The motion run measured its gap from the last kept frame and reset on every unchanged or minor frame, so on real use it almost never engaged: 18 minutes of the installed app kept 201 frames, 152 of them major changes a median 4 s apart. `KeepState` now also records when the last major change was seen, kept or throttled, and minor and unchanged frames carry the run forward. On the tuning trace the default policy keeps 152 of 572 frames (26.6%) instead of 168, with the same 29.5 s longest gap, all 54 stable page changes within the minor gap, and the worst page change still 8.0 s late.

## Before: eight-hour day

The direct linear extrapolation from 16.3 MB per hour is 131 MB per day. Of the 8.2 MB on disk after 30 minutes, 4.4 MB is the rolling SQLite WAL, which is present at any moment but does not grow once per run. Excluding that fixed part, the run grew by 3.8 MB in 30 minutes, or 7.6 MB per hour: 36 MB of video, 25 MB of main database, plus one 4.4 MB WAL, about 65 MB per day. Both estimates are above the 10 to 30 MB target.

## Before: budget verdicts

| Budget | Verdict |
|---|---|
| `evaluate_frame` (160x90) under 50 microseconds | Not met as called by the recorder: 105 microseconds p50 through `EngineAdapter` and UniFFI. The core diff was not isolated; `docs/ARCHITECTURE.md` reports 3.3 microseconds for it. |
| `record_frame` with 80 lines under 2 milliseconds | Met at p95 (1.25 ms) with 43.7 lines per frame on average; max 4.03 ms. |
| `search` over 1 million lines under 50 milliseconds | Not tested at 1 million lines. The 2,323-line store returned in 11.2 ms p50, 26.1 ms max, including CLI startup. |
| Capture CPU while idle on a static screen under 1% | Not met at face value: 1.97% over the no-keep samples. Thumbnail and evaluate alone are about 1.0%; the rest is OCR spillover from the last kept frame. |
| Memory of the running app under 150 MB | Not met at peak: 181.6 MB peak, 108.7 MB median, recorder only. The app adds its UI on top. |
| Storage for a normal day 10 to 30 MB | Not met: about 65 MB per day steady state, 131 MB per day direct linear. |

## After: blocked

The final 30-minute production run could not be measured on 2026-10-21. `swift run -c release ErstProbe --verify` passed its OCR check twice at 03:42 and 03:43, then failed again at 04:44. Every OCR job on a captured frame failed with `TextRecognition.CRImageReaderError` (E5RT code 13), from another change in progress in ErstKit; the failure affects every capturing process on the machine, not only this probe. A 10.5 minute partial production run kept 77 of 294 frames (26.2%) and wrote 1.70 MB of video before it was stopped; only 10 of its 77 stored frames had text, so its database bytes are not comparable and are not used. The after row stays open until captured frames regain text.

## After: recorder

- Date: 2026-10-21 06:01 to 06:11 local, 10.0 minutes.
- Machine: Apple M4, macOS 27.0.1 (26A434).
- Display: 2560 x 1440 at 144 Hz.
- Capture: 2560 x 1440 BGRA, HEVC quality 0.45 ("smaller").
- Workload: nobody touched the Mac. Capture delivered 290 frames, one per 2 s interval, so the screen changed all run, but the keep policy rejected all but 16 because the visible window changed in small steps (terminal output). A second 10-minute run on an unchanged screen delivered only 22 frames and kept 2; it confirmed the thumbnail figure (3.025 ms) and is not used below.
- Recognition level: fast fallback. The accurate request failed during this run's warm-up (27,492 ms), so every OCR job ran at the fast level. Accurate recognition is intermittent here: two `--verify` runs before this recording passed the strict check, and every attempt after it fell back to fast.

| Metric | Value |
|---|---|
| Wall time | 600.6 s (10.0 min) |
| Frames seen | 290 |
| Frames kept | 16 |
| Stored frames | 16 |
| OCR coverage | 16 of 16 kept frames with text (100.0%) |
| OCR jobs | 16, 147.4 ms average |
| OCR warm-up | 27,492 ms (the failed accurate attempt runs first) |
| Segments | 2 |
| Video bytes | 401,463 (0.4 MB) |
| Database bytes after checkpoint (`erst.sqlite`) | 249,856 (0.2 MB) |
| Write-ahead log after checkpoint | 0 bytes |
| Total bytes (video plus checkpointed database) | 651,319 (0.7 MB) |
| Average CPU | 1.36% of one core (8.1 s CPU over 600.6 s) |
| Static-screen CPU after warm-up | 0.43% of one core over 285.0 s (273 of 577 sampled seconds) |
| Static-screen CPU, whole run | 0.99% of one core over 287.1 s (275 of 577 sampled seconds) |
| Peak resident memory | 128.9 MB |
| Median resident memory | 47.3 MB |
| Bytes per hour of capture | 3.9 MB |
| 8-hour day, direct linear | 31.2 MB |
| `evaluate_frame` | p50 0.097 ms, p95 0.108 ms, max 0.159 ms (290 calls) |
| `record_frame` | p50 0.579 ms, p95 1.438 ms, max 1.438 ms (16 calls) |
| Thumbnail | 3.119 ms average (290 frames) |
| Lines per frame | 76.4 average, 12 to 101 |
| Unique text lines | 363 |
| Frame lines | 1,223 |
| Spans | 3 |

Deviation: the idle gate was disabled (31,536,000 s) with `--no-idle-gate`, because nobody touches the Mac during the run and `FocusTracker` now reads any-input idle time, which reaches the real 120 s threshold. The display was kept awake with `caffeinate -d -u`, because a locked or sleeping display pauses capture (the app does this on purpose) and a first attempt at 05:37 on a locked session captured 0 frames. Capture, segments, compression, OCR, and exclusions stayed at production values.

Static-screen CPU uses the one-second samples in which capture delivered a frame and none was kept. The after-warm-up figure is the budget figure: it leaves out the failed accurate warm-up, which costs about 4 s of CPU inside the first 27.5 s. Both are upper bounds, because OCR from the last kept frame can run during the next sample.

The thumbnail average did not reach its 2 ms budget. The new 2x2-strided pass reads 921,600 samples per 2560x1440 frame instead of 3,686,400, and on a surface the process has already touched that loop costs 0.5 ms (0.4 ms on a synthetic frame, and 1.6 ms for the old full read on the same surfaces). A freshly delivered ScreenCaptureKit surface costs about 1.2 ms on first touch, and the probe sample runs every 2 s in a mostly idle process, so its per-frame average stays near 3 ms: 3.119 ms here and 3.025 ms in the second run. Reading fewer rows alone cannot remove the first-touch cost, because a strided pass still touches almost every 16 KB page.

The WAL checkpoint reports 0 bytes after the run, where the previous run added a 4.2 MB `-wal` to the total. The database is the main file only, 249,856 bytes.

Bytes per hour is a floor for a normal day: this run kept 16 frames in 10 minutes, against 77 in the previous run. Re-basing that run on its 1.7 MB of video plus database, with the WAL folded in, gives about 10.4 MB per hour, or 83 MB for an 8-hour day. The 3.9 MB per hour here comes from a quiet screen, so it is not what an 8-hour day of browsing would cost.

Budget verdicts for this round:

| Budget | Verdict |
|---|---|
| Capture CPU while idle on a static screen under 1% | Met: 0.43% of one core after warm-up (0.99% for the whole run, warm-up included). |
| Memory of the running app under 150 MB | Met for the recorder: 128.9 MB peak during warm-up, 47.3 MB median. The app adds its UI on top. |
| Storage for a normal day 10 to 30 MB | Not met on a busy screen: 31.2 MB from this quiet run, about 83 MB at the previous run's keep rate. |
| `evaluate_frame` (160x90) under 50 microseconds | Not met through `EngineAdapter` and UniFFI: 97 microseconds p50. The core diff is separate. |
| `record_frame` with 80 lines under 2 milliseconds | Met at p95: 1.438 ms with 76.4 lines per frame on average. |
| Thumbnail under 2 ms | Not met as the probe measures it: 3.119 ms. The averaging loop is 0.5 ms; first touch of each capture surface and the idle process's scheduling dominate. |

## Busy desktop

- Date: 2026-10-21 14:38 to 14:53 local.
- Machine: Apple M4 (Mac16,10), macOS 27.0.1 (26A434).
- Display: 2560 x 1440 at 144 Hz.
- Workload: the desktop was in use for 900.1 s. Erst saw 447 frames and kept 140.
- Method: `ErstProbe 900 --production --no-idle-gate` with `caffeinate -d` holding the display awake, a 5 s `ps` sample of the process, and `du` before and after.
- Memory below is `ps` RSS. Erst's own summary reports a 97.8 MB median and 213.4 MB peak physical footprint, which counts dirty pages only. OCR ran at the fast level because accurate recognition failed on this host, and Accessibility was not trusted, so the text came from OCR alone.

| Metric | Erst |
|---|---:|
| Frames seen in 15 min | 447 |
| Frames stored | 140 |
| Video bytes | 4.1 MB |
| Database growth | 1.3 MB |
| Total growth | 5.5 MB |
| Bytes per stored frame (video) | 29.5 KB |
| MB per hour | 21.9 |
| 8-hour day estimate | 174.9 MB |
| CPU average / p95 (% of one core) | 3.59 / 9.4 |
| Memory median / peak (MB) | 208.0 / 281.3 |
| Frames with searchable text | 140 of 140 |

The keep policy and the codec set the storage: Erst stored 140 of the 447 frames it saw, at HEVC quality 0.45 and 29.5 KB of video per frame. It has no frame between kept changes. At 21.9 MB per hour an 8-hour day is 175 MB, well above the 10 to 30 MB budget; a quiet run measured 10.4 MB per hour, still 83 MB for a day.
