# Code hygiene

These rules apply to every change, human or agent. A change that breaks one of them is not done.

## Universal

- Everything is in English: code, identifiers, comments, commit messages, docs, UI strings.
- Never use the em dash character (U+2014). Use a period, comma, colon, or parentheses.
- Name things for what they are in the domain: `Moment`, `Segment`, `Span`, `KeepPolicy`. No `Manager`, `Helper`, `Util`, `Data`, `Info` suffixes unless the domain word is exactly that.
- One concept per file: Swift files are at most 400 lines, Rust files at most 600, and `scripts/hygiene.sh` enforces both limits.
- Functions do one thing. Over 50 lines needs a reason.
- No dead code, no commented-out code, no `TODO` without an issue reference.
- Comments explain why, never what. Public items get a one-line doc comment when the name is not enough.
- No speculative abstraction. Add a protocol or trait only when there are two implementations or a test seam needs it.
- Delete before you add. The smallest change that solves the problem wins.
- Magic numbers become named constants next to the code that uses them, with the unit in the name (`max_gap_ms`, `segmentDurationSeconds`).
- Timestamps are Unix milliseconds in Rust and the database, `Date` in Swift. Convert only at the FFI boundary.

## Rust

- Edition 2024, stable toolchain. `cargo fmt` and `cargo clippy --all-targets -- -D warnings` are clean. Workspace lints in the root `Cargo.toml` deny `unsafe_code` (except in `erst-ffi`, where UniFFI generates it), `unwrap_used`, `expect_used` outside tests, and `print_stdout` outside `erst-cli`.
- Errors: one `thiserror` enum per crate. Libraries never panic on bad input. `anyhow` only in `erst-cli`.
- No `unwrap()` or `expect()` outside tests. Use `?` and typed errors.
- Pure logic lives in `erst-core` and has unit tests next to it. Every public function in `erst-core` has at least one test, including edge cases (empty input, boundaries, overflow).
- `erst-store` tests use a temporary database and cover every query, migrations from zero, and FTS behavior with accents.
- Hot paths (frame diff, insert_frame) are allocation conscious and have a benchmark or a timing test.
- Dependencies need a reason. Prefer the standard library. Current allowed set: `rusqlite` (bundled), `thiserror`, `uniffi`, `blake3` or `xxhash-rust`, `serde` and `serde_json`, `clap`, `anyhow`, `chrono` or `time`, `tempfile` (dev), an MCP SDK in `erst-cli`. Add others only with a line in the change description explaining why.
- Rust libraries do not log. They return typed errors and counts (for example `pending_file_count`), and the Swift app logs through `os.Logger`.
- The engine repairs at open whatever a crash or a kill leaves behind: open spans, open segments, pending file deletions. New persistent state that has an open or in-progress phase gets the same repair and a reopen test.
- `rusqlite`'s `execute_batch` steps each statement once. A statement that works one step at a time, such as `PRAGMA incremental_vacuum`, goes through `query` and is stepped until done, or it does a single step and stops.
- A storage change is proven on a copy of a real database, never only on fixtures: compare every frame and every search before and after, and record the measured size in `docs/ARCHITECTURE.md`.

## Swift

- Swift 6 language mode, strict concurrency, zero warnings. `swift format` (bundled with the toolchain) using `app/.swift-format`.
- Value types by default. `final class` only for identity or reference semantics. `@Observable` for UI state, on the main actor.
- Never write `@State`. In the macOS 26 SDK it is a SwiftUI macro, and its compiler plugin (`SwiftUIMacros`) ships only with Xcode, so the build fails here. A screen owns its `@Observable` model with `@StateObject`; the model class also conforms to `ObservableObject` for that reason only. Local view state (hover, a loaded thumbnail) lives in that model. `@FocusState`, `@Environment`, and `@Binding` are property wrappers and are fine.
- Actors for anything that owns mutable state touched from more than one task (capture, encoder, OCR).
- No force unwraps (`!`) and no `try!` outside previews. Handle errors where the user can act on them; log the rest.
- `async`/`await` everywhere. No completion handlers in new APIs, no `DispatchQueue` unless an Apple API requires it.
- Views stay small: a view over 150 lines is split into subviews with names from the design (`HeatStrip`, `TimelineDock`, `MomentInspector`).
- No hard-coded colors, fonts, radii, or spacing in views. Use the tokens in `ErstUI/Theme`.
- No `#Preview` blocks: they need Xcode. `ErstSnapshots` renders every screen and state from `ErstPreview` instead.
- UI strings are short and specific. No exclamation marks, no emoji, no filler.
- Paths the engine returns are absolute. Open them as they are; never prepend the data directory again.
- A window whose content forces the dark color scheme also takes the dark appearance (`darkWindowAppearance()`). `preferredColorScheme(.dark)` alone leaves the system glass and material light behind light text.
- The app bundle is built with `swift build --build-system native` (`scripts/build-app.sh`), so the binary declares the installed SDK and macOS draws it with the current appearance.

## Design (UI code)

- Native macOS 26+ Liquid Glass: `.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)`. Do not imitate glass with custom gradients, glows, colored shadows, or bevels.
- Butter (`#F8D677`) is the only accent. Heat colors (coral, orange, butter) are reserved for activity data.
- No status dots in badges, no separators made of middle dots, no monospaced fonts in the interface.
- Typeface: Schibsted Grotesk, bundled. Tracking tightens as size grows (display -0.03em, body 0).
- See `docs/DESIGN.md` for tokens and each screen.

## Tests and verification

- A change is done when `scripts/check.sh` passes and the behavior it adds was exercised (a test, or a documented manual run with output).
- Tests describe behavior, not implementation. Name them after the rule they protect: `skips_frame_when_only_clock_changed`.
- Do not mock what you own. Mock only system boundaries (screen capture, clock, file system where needed).
- Swift unit tests cannot run without Xcode on this machine. Keep logic that needs tests in Rust; keep Swift thin around Apple APIs.
- Swift behavior is checked by `ErstProbe --verify` and the `ErstSnapshots` contracts. A check goes through the code path the app uses (for example `LiveMemoryService.image(for:)`), never through inputs it builds itself, and a fix comes with a check that fails on the old code.
- When something fails in the running app, read the failing component in the system log first (`/usr/bin/log show --predicate 'process == "Erst"' --info --debug`), then change code.

## Performance budgets

| Path | Budget |
|---|---|
| `evaluate_frame` (160x90) | under 50 microseconds |
| `record_frame` with 80 lines | under 2 milliseconds |
| `search` over 1 million lines | under 50 milliseconds |
| Capture CPU while idle on a static screen | under 1% |
| Memory of the running app | under 150 MB |
| Storage for a normal day | target 10 to 30 MB |

## Commits

- Imperative subject under 72 characters (`Add tile diff to keep policy`), body explains why when it is not obvious.
- One logical change per commit. No generated noise mixed with hand-written changes.
- No `Co-Authored-By` or "Generated with" trailers.
